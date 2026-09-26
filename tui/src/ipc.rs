//! The shell's way in, as tmux's socket is: a running hn listens on /tmp/hn-<uid>/<name>.sock
//! (-L name, else `default`; a second client of the name on <name>@<pid>.sock beside it; 0600, in
//! a 0700 directory, as tmux's /tmp/tmux-<uid>), and `hn <tmux command>` from any shell runs the
//! command there and prints what it prints — `hn display -p '#{pane_current_path}'`,
//! `hn send-keys -t 1 'make' Enter`, `hn capture-pane -p`, `hn list-panes -F '#{pane_id}'`. A
//! command naming a session another client of the name has goes to that client.

use std::path::PathBuf;

use serde_json::{json, Value};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::sync::{mpsc, oneshot};

use crate::event::Event;

unsafe extern "C" { fn getuid() -> u32; }

/// Where the sockets live: short enough for a socket path (104 bytes on macOS), private to you.
/// This client's own socket, once it listens: what HN_SOCKET says to the commands it runs, and
/// #{socket_path}.
static HERE: std::sync::OnceLock<PathBuf> = std::sync::OnceLock::new();
pub fn here() -> Option<PathBuf> { HERE.get().cloned() }

pub fn dir() -> PathBuf {
    let base = std::env::var("HN_TMPDIR").or_else(|_| std::env::var("TMUX_TMPDIR")).unwrap_or_else(|_| "/tmp".into());
    PathBuf::from(base).join(format!("hn-{}", unsafe { getuid() }))
}

/// Listen for commands from shells; each is run on the app loop, its output sent back.
pub fn serve(sink: mpsc::UnboundedSender<Event>, port: u16) -> Option<PathBuf> {
    let dir = dir();
    std::fs::create_dir_all(&dir).ok()?;
    #[cfg(unix)] { use std::os::unix::fs::PermissionsExt; let _ = std::fs::set_permissions(&dir, std::fs::Permissions::from_mode(0o700)); }
    // Sockets of clients gone are swept.
    sweep(&dir);
    // Named with -L (as tmux's), else `default`. The name's socket is its first client's: one
    // already listening there keeps it (commands go there), and this one listens beside it,
    // named with its pid — both reach every session of the name (a command naming one goes to
    // the client that has it).
    let name = std::env::var("HN_SOCKET_NAME").ok().filter(|n| !n.is_empty()).unwrap_or_else(|| "default".into());
    let primary = dir.join(format!("{name}.sock"));
    let (listener, path) = match tokio::net::UnixListener::bind(&primary) {
        Ok(l) => (l, primary),
        Err(_) => {
            let beside = dir.join(format!("{name}@{}.sock", std::process::id()));
            let _ = std::fs::remove_file(&beside);
            (tokio::net::UnixListener::bind(&beside).ok()?, beside)
        }
    };
    let _ = HERE.set(path.clone());
    #[cfg(unix)] { use std::os::unix::fs::PermissionsExt; let _ = std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o600)); }
    // Which daemon this client talks to, beside its socket: `hn -L name list-harnesses` asks that
    // one, never another it happens to find on the default port.
    let _ = std::fs::write(path.with_extension("port"), port.to_string());
    tokio::spawn(async move {
        while let Ok((stream, _)) = listener.accept().await {
            let sink = sink.clone();
            tokio::spawn(async move {
                let (read, mut write) = stream.into_split();
                let mut line = String::new();
                // A connection that says nothing (whether this client answers) runs nothing.
                if BufReader::new(read).read_line(&mut line).await.is_err() || line.trim().is_empty() { return }
                // {"argv": [...], "cwd": "..."} (or just the words, from an older hn).
                let request: Value = serde_json::from_str(line.trim()).unwrap_or(Value::Null);
                let words: Vec<String> = request.get("argv").or(Some(&request)).and_then(|v| serde_json::from_value(v.clone()).ok()).unwrap_or_default();
                let cwd = request.get("cwd").and_then(Value::as_str).map(str::to_string);
                let stdin = request.get("stdin").and_then(Value::as_str).map(str::to_string);
                let (tx, rx) = oneshot::channel::<crate::app::Reply>();
                let _ = sink.send(Event::Apply(Box::new(move |app: &mut crate::app::App| {
                    app.capture = Some(Vec::new());
                    app.capture_err = Some(Vec::new());
                    app.cli_tx = Some(tx);
                    app.cli_code = 0;
                    app.cli_cwd = cwd;
                    app.cli_stdin = stdin;
                    crate::commands::execute_args(app, &words);
                    // Still waiting on a job (run-shell, if-shell): it answers when it is done.
                    if app.capture.is_some() { app.finish_cli() }
                })));
                let (mut out, err, code) = rx.await.unwrap_or_default();
                // A last line marked bare (show-buffer's data without a newline) is printed bare.
                let bare = out.last().map(|l| l.ends_with(crate::app::BARE)).unwrap_or(false);
                if let Some(l) = out.last_mut() { if let Some(s) = l.strip_suffix(crate::app::BARE) { *l = s.to_string() } }
                let _ = write.write_all(format!("{}\n", json!({ "out": out, "err": err, "code": code, "bare": bare })).as_bytes()).await;
            });
        }
    });
    Some(path)
}

/// What hn's jobs (run-shell, if-shell, #(), copy-pipe) run with, as tmux's run with TMUX set:
/// HN_SOCKET naming this client, TMUX saying they run under one, and a `tmux` on the PATH that
/// is hn — so a script's (or a plugin's) `tmux …` reaches this client, never a tmux server.
pub fn job_env() -> Vec<(String, String)> {
    let mut env = Vec::new();
    let Some(sock) = here() else { return env };
    env.push(("HN_SOCKET".into(), sock.display().to_string()));
    env.push(("TMUX".into(), format!("{},{},0", sock.display(), std::process::id())));
    if let Some(bin) = shim() {
        let path = std::env::var("PATH").unwrap_or_default();
        env.push(("PATH".into(), format!("{}:{path}", bin.display())));
    }
    env
}

/// The folder holding hn's `tmux` (made once): a script running this hn as tmux.
fn shim() -> Option<PathBuf> {
    static SHIM: std::sync::OnceLock<Option<PathBuf>> = std::sync::OnceLock::new();
    SHIM.get_or_init(|| {
        // One folder per hn binary: a test build's tmux never stands in for another hn's.
        let me = std::env::current_exe().ok()?;
        let tag = { use std::hash::{Hash, Hasher}; let mut h = std::collections::hash_map::DefaultHasher::new(); me.hash(&mut h); h.finish() };
        let bin = dir().join(format!("bin-{tag:016x}"));
        std::fs::create_dir_all(&bin).ok()?;
        let script = format!("#!/bin/sh\n# hn's tmux: what hn runs reaches hn, not a tmux server.\nHN_AS_TMUX=1 exec '{}' \"$@\"\n", me.display().to_string().replace('\'', "'\\''"));
        let path = bin.join("tmux");
        if std::fs::read_to_string(&path).ok().as_deref() != Some(script.as_str()) {
            let tmp = bin.join(format!(".tmux.{}", std::process::id()));
            std::fs::write(&tmp, &script).ok()?;
            #[cfg(unix)] { use std::os::unix::fs::PermissionsExt; std::fs::set_permissions(&tmp, std::fs::Permissions::from_mode(0o755)).ok()?; }
            std::fs::rename(&tmp, &path).ok()?;
        }
        Some(bin)
    }).clone()
}

/// tmux's find_cwd: $PWD when it is where we are (symlinks kept, as the shell shows it), else
/// the real folder.
fn find_cwd() -> Option<String> {
    let cwd = std::env::current_dir().ok()?;
    let Some(pwd) = std::env::var("PWD").ok().filter(|p| !p.is_empty()) else { return Some(cwd.display().to_string()) };
    match (std::fs::canonicalize(&pwd), std::fs::canonicalize(&cwd)) {
        (Ok(a), Ok(b)) if a == b => Some(pwd),
        _ => Some(cwd.display().to_string()),
    }
}

/// Remove sockets nobody answers on (a client that was killed), and the ports beside them.
fn sweep(dir: &std::path::Path) {
    let Ok(entries) = std::fs::read_dir(dir) else { return };
    for e in entries.flatten() {
        let p = e.path();
        if p.extension().map(|x| x == "sock").unwrap_or(false) && std::os::unix::net::UnixStream::connect(&p).is_err() { let _ = std::fs::remove_file(&p); let _ = std::fs::remove_file(p.with_extension("port")); }
        if p.extension().map(|x| x == "port").unwrap_or(false) && !p.with_extension("sock").exists() { let _ = std::fs::remove_file(&p); }
    }
}

/// The daemon port of the client a command names (-S, -L, $HN_SOCKET, else the newest one): what
/// it wrote beside its socket. None when no client is found.
pub fn client_port(socket: Option<&str>, name: Option<&str>) -> Option<u16> {
    let path = chosen(socket, name)?;
    std::fs::read_to_string(path.with_extension("port")).ok()?.trim().parse().ok()
}

/// Which client to ask: -S path, -L name, $HN_SOCKET, $HN_SOCKET_NAME (what a client sets for
/// what it runs, as tmux's $TMUX: a job's `hn …` reaches the client that ran it), else the newest.
/// A name's first client, else another of its clients still running.
fn chosen(socket: Option<&str>, name: Option<&str>) -> Option<PathBuf> {
    // -S and -L say which, before $HN_SOCKET (a job's `tmux -L other ls` asks the other).
    if let Some(p) = socket { return Some(PathBuf::from(p)) }
    if let Some(n) = name { return Some(clients_of(n).into_iter().next().unwrap_or_else(|| dir().join(format!("{n}.sock")))) }
    if let Some(p) = std::env::var("HN_SOCKET").ok().filter(|s| !s.is_empty()) { return Some(PathBuf::from(p)) }
    let name = std::env::var("HN_SOCKET_NAME").ok().filter(|n| !n.is_empty());
    if let Some(n) = name { return Some(clients_of(&n).into_iter().next().unwrap_or_else(|| dir().join(format!("{n}.sock")))) }
    if let Some(p) = clients_of("default").into_iter().next() { return Some(p) }
    newest()
}

/// Whether a client listens at [path] (the connection is let go at once, and runs nothing).
pub fn answers(path: &std::path::Path) -> bool { std::os::unix::net::UnixStream::connect(path).is_ok() }

/// A server name's running clients: its first one's socket (`work.sock`), then the others'
/// (`work@4242.sock`), the newest first.
pub fn clients_of(name: &str) -> Vec<PathBuf> {
    let dir = dir();
    let primary = dir.join(format!("{name}.sock"));
    let mut found = Vec::new();
    if answers(&primary) { found.push(primary) }
    let prefix = format!("{name}@");
    let mut more: Vec<(std::time::SystemTime, PathBuf)> = std::fs::read_dir(&dir).map(|d| d.filter_map(|e| e.ok()).map(|e| e.path())
        .filter(|p| p.extension().map(|x| x == "sock").unwrap_or(false) && p.file_name().and_then(|f| f.to_str()).map(|f| f.starts_with(&prefix)).unwrap_or(false))
        .filter_map(|p| std::fs::metadata(&p).and_then(|m| m.modified()).ok().map(|t| (t, p))).collect()).unwrap_or_default();
    more.sort();
    found.extend(more.into_iter().rev().map(|(_, p)| p).filter(|p| answers(p)));
    found
}

/// Whether a client is running where a command would go (its socket answers).
pub fn alive(socket: Option<&str>, name: Option<&str>) -> bool {
    chosen(socket, name).map(|p| answers(&p)).unwrap_or(false)
}

/// A command run by another client, from this one's loop (a command naming a session that
/// client has; that client giving a session up): what it printed, its errors and its status —
/// none when it does not answer in time.
pub fn ask(path: &std::path::Path, words: &[String]) -> Option<crate::app::Reply> {
    use std::io::{BufRead, Write};
    let mut s = std::os::unix::net::UnixStream::connect(path).ok()?;
    s.set_read_timeout(Some(std::time::Duration::from_secs(5))).ok()?;
    s.set_write_timeout(Some(std::time::Duration::from_secs(2))).ok()?;
    writeln!(s, "{}", json!({ "argv": words, "cwd": find_cwd() })).ok()?;
    let mut line = String::new();
    std::io::BufReader::new(&s).read_line(&mut line).ok()?;
    let reply: Value = serde_json::from_str(line.trim()).ok()?;
    let lines = |k: &str| -> Vec<String> { reply.get(k).and_then(Value::as_array).map(|a| a.iter().filter_map(|l| l.as_str().map(str::to_string)).collect()).unwrap_or_default() };
    let mut out = lines("out");
    if reply.get("bare").and_then(Value::as_bool).unwrap_or(false) { if let Some(l) = out.last_mut() { l.push(crate::app::BARE) } }
    Some((out, lines("err"), reply.get("code").and_then(Value::as_i64).unwrap_or(0) as i32))
}

/// The sessions file held for this client alone while it is read and written again (flock):
/// clients of one name keep their sessions in one file.
pub fn lock(path: &std::path::Path) -> Option<std::fs::File> {
    use std::os::unix::io::AsRawFd;
    if let Some(dir) = path.parent() { let _ = std::fs::create_dir_all(dir); }
    let f = std::fs::OpenOptions::new().create(true).truncate(false).write(true).open(path.with_extension("lock")).ok()?;
    // SAFETY: a valid descriptor, held open for as long as the lock.
    (unsafe { libc::flock(f.as_raw_fd(), libc::LOCK_EX) } == 0).then_some(f)
}

/// The newest running client's socket.
fn newest() -> Option<PathBuf> {
    let mut socks: Vec<(std::time::SystemTime, PathBuf)> = std::fs::read_dir(dir()).ok()?.filter_map(|e| e.ok()).map(|e| e.path())
        .filter(|p| p.extension().map(|x| x == "sock").unwrap_or(false))
        .filter_map(|p| std::fs::metadata(&p).and_then(|m| m.modified()).ok().map(|t| (t, p))).collect();
    socks.sort();
    socks.into_iter().rev().map(|(_, p)| p).next()
}

/// `hn <command> …` from a shell: 0 when it ran, 1 with its error, 1 "no client" when none runs.
pub async fn call(words: &[String], socket: Option<&str>, name: Option<&str>) -> i32 {
    let mut tried = 0;
    let pinned = socket.is_some() || name.is_some() || std::env::var("HN_SOCKET").map(|s| !s.is_empty()).unwrap_or(false);
    loop {
        let Some(path) = chosen(socket, name) else { eprintln!("{}", no_server(&dir().join("default.sock"))); return 1 };
        match call_at(&path, words).await {
            Some(code) => return code,
            // A socket left by a client that died: gone, try the next.
            None => {
                if pinned || tried > 8 { eprintln!("{}", no_server(&path)); return 1 }
                let _ = std::fs::remove_file(&path); tried += 1;
            }
        }
    }
}

/// tmux's words for no server at [path]: none there (ENOENT), or one that is gone (ECONNREFUSED).
pub fn no_server(path: &std::path::Path) -> String {
    if path.exists() { format!("no server running on {}", path.display()) } else { format!("error connecting to {} (No such file or directory)", path.display()) }
}

/// A command run by the client at [path], its output printed here; None when nothing answers.
pub async fn call_at(path: &std::path::Path, words: &[String]) -> Option<i32> {
    {
        match tokio::net::UnixStream::connect(path).await {
            Ok(stream) => {
                let (read, mut write) = stream.into_split();
                let cwd = find_cwd();
                // load-buffer - and source-file -: what is piped in goes with the command.
                let reads_stdin = words.first().and_then(|w| crate::cmd::find(w).ok()).map(|e| matches!(e.name, "load-buffer" | "source-file")).unwrap_or(false) && words.iter().skip(1).any(|w| w == "-");
                let stdin = if reads_stdin { let mut s = String::new(); let _ = std::io::Read::read_to_string(&mut std::io::stdin(), &mut s); Some(s) } else { None };
                if write.write_all(format!("{}\n", json!({ "argv": words, "cwd": cwd, "stdin": stdin })).as_bytes()).await.is_err() { return Some(1) }
                let mut line = String::new();
                let _ = BufReader::new(read).read_line(&mut line).await;
                let reply: Value = serde_json::from_str(line.trim()).unwrap_or(Value::Null);
                // Written quietly: `hn … | head` closing the pipe is not an error.
                use std::io::Write;
                let mut out = std::io::stdout().lock();
                // The last line without its newline when the command printed none (show-buffer).
                let lines = reply.get("out").and_then(Value::as_array).cloned().unwrap_or_default();
                let bare = reply.get("bare").and_then(Value::as_bool).unwrap_or(false);
                for (i, l) in lines.iter().enumerate() {
                    let l = l.as_str().unwrap_or("");
                    let r = if bare && i + 1 == lines.len() { write!(out, "{l}") } else { writeln!(out, "{l}") };
                    if r.is_err() { break }
                }
                let err: Vec<Value> = reply.get("err").and_then(Value::as_array).cloned().unwrap_or_default();
                let mut e = std::io::stderr().lock();
                for l in &err { let _ = writeln!(e, "{}", l.as_str().unwrap_or("")); }
                Some(match reply.get("code").and_then(Value::as_i64) { Some(c) => c as i32, None => if err.is_empty() { 0 } else { 1 } })
            }
            Err(_) => None,
        }
    }
}

#[cfg(test)]
mod tests {
    /// A command naming a client asks that client's daemon (the port it wrote beside its socket),
    /// and a client that wrote none gives no port — never a guess.
    #[test]
    fn a_named_client_says_which_daemon() {
        let tmp = std::env::temp_dir().join(format!("hn-port-test-{}", std::process::id()));
        std::fs::create_dir_all(&tmp).unwrap();
        unsafe { std::env::set_var("HN_TMPDIR", &tmp) }
        let dir = super::dir();
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(dir.join("work.sock"), "").unwrap();
        std::fs::write(dir.join("work.port"), "18999\n").unwrap();
        assert_eq!(super::client_port(None, Some("work")), Some(18999));
        assert_eq!(super::client_port(None, Some("other")), None);
        assert_eq!(super::client_port(Some(dir.join("work.sock").to_str().unwrap()), None), Some(18999));
        let _ = std::fs::remove_dir_all(&tmp);
    }
}
