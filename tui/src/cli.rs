//! hn from a shell, as `tmux ls` and `tmux send-keys` are used from scripts and editors:
//!
//!   hn list-harnesses (lsh)                every harness on every machine
//!   hn send-message -t <harness> <text>    a message to a harness (a turn, as if typed and sent)
//!   hn tim                                 tim, the creature
//!
//! (`hn ls` and `hn send` are tmux's: list-sessions and send-keys.)
//!
//! Anything else starts the client.

use std::time::Duration;

use serde_json::{json, Value};
use tokio::sync::mpsc;

use crate::daemon::{http_json, Link};
use crate::fleet::agent_from;

/// Run a CLI subcommand; None when `args` is not one (the client should start).
/// tmux's usage line, hn's flags.
pub const USAGE: &str = "usage: hn [-hV] [-f file] [-L socket-name] [-S socket-path] [--port port]\n          [command [flags]]";

/// The command line, read as tmux reads its own: flags, then a command.
#[derive(Default, Debug)]
pub struct Flags { pub help: bool, pub long_help: bool, pub version: bool, pub keys: bool, pub licenses: bool, pub config: Option<String>, pub socket: Option<String>, pub name: Option<String>, pub port: Option<u16>, pub rest: Vec<String> }

pub fn flags(args: &[String]) -> Result<Flags, String> {
    let mut f = Flags::default();
    let mut i = 0;
    while i < args.len() {
        let a = args[i].as_str();
        if a == "--" { i += 1; break }
        if !a.starts_with('-') || a == "-" { break }
        match a {
            "--help" => f.long_help = true,
            "--version" => f.version = true,
            "--keys" => f.keys = true,
            "--licenses" => f.licenses = true,
            "--port" => { i += 1; f.port = Some(args.get(i).and_then(|p| p.parse().ok()).ok_or("--port needs a port")?) }
            _ if a.starts_with("--") => return Err(format!("unknown option -- {}", &a[2..])),
            _ => {
                // Short flags, bundled as getopt allows (-hV); -f -L -S take the rest or the next word.
                let chars: Vec<char> = a[1..].chars().collect();
                let mut j = 0;
                while j < chars.len() {
                    match chars[j] {
                        'h' => f.help = true,
                        'V' => f.version = true,
                        c @ ('f' | 'L' | 'S') => {
                            let value: String = if j + 1 < chars.len() { chars[j + 1..].iter().collect() } else { i += 1; args.get(i).cloned().ok_or(format!("option requires an argument -- {c}"))? };
                            match c { 'f' => f.config = Some(value), 'L' => f.name = Some(value), _ => f.socket = Some(value) }
                            break;
                        }
                        c => return Err(format!("unknown option -- {c}")),
                    }
                    j += 1;
                }
            }
        }
        i += 1;
    }
    f.rest = args[i.min(args.len())..].to_vec();
    Ok(f)
}

/// Run a command given on the command line; None when there is none (the client starts).
pub async fn run(args: &[String], explicit_port: Option<u16>, socket: Option<&str>, name: Option<&str>) -> Option<i32> {
    // hn's own commands ask a daemon: --port or $PORT, else the one the named (or newest) client
    // talks to, else the default — never a daemon other than the client's the command names.
    let port = explicit_port.or_else(|| crate::ipc::client_port(socket, name)).unwrap_or(18473);
    let socket = socket.map(str::to_string);
    let name = name.map(str::to_string);
    let cmd = args.first()?.as_str();
    match cmd {
        // Every harness on every machine (hn's; `ls` is tmux's list-sessions).
        "list-harnesses" | "lsh" => Some(ls(port).await),
        "send-message" => Some(send(port, &args[1..]).await),
        "tim" => { println!("{}", crate::tim::cli_line()); Some(0) }
        // attach / a: the client itself, as `tmux attach` is.
        "attach" | "attach-session" | "a" | "at" => None,
        // new-session: a client here, as `tmux new` from a shell is — unless it is -d (a session
        // for the running client to keep) or comes from inside a client (one of its jobs), which
        // asks that client.
        c if crate::cmd::find(c).map(|e| e.name == "new-session").unwrap_or(false) => {
            let detached = crate::cmd::find(c).ok().and_then(|e| crate::cmd::parse(e, args).ok()).map(|a| a.has('d') > 0).unwrap_or(false);
            // $HN_SOCKET: what a client sets for what it runs, as tmux's $TMUX.
            let inside = std::env::var("HN_SOCKET").map(|v| !v.is_empty()).unwrap_or(false);
            if detached && !crate::ipc::alive(socket.as_deref(), name.as_deref()) { return Some(offline(port, args, name.as_deref()).await) }
            if detached || inside { Some(crate::ipc::call(args, socket.as_deref(), name.as_deref()).await) } else { None }
        }
        // No client running: what tmux's server would answer — the sessions a client left (and the
        // desk's), from where they are kept.
        c if matches!(crate::cmd::find(c).map(|e| e.name), Ok("list-sessions" | "has-session" | "kill-session")) && !crate::ipc::alive(socket.as_deref(), name.as_deref()) => Some(offline(port, args, name.as_deref()).await),
        // Any tmux command: run on the newest running client, its output printed here.
        // Any tmux command (by name, alias, or the start of one), or hn's: run by the client.
        c if crate::commands::is_command_name(c) || crate::cmd::find(c).is_ok() => Some(crate::ipc::call(args, socket.as_deref(), name.as_deref()).await),
        c if !c.starts_with('-') => { eprintln!("{}", crate::cmd::find(c).err().unwrap_or_default()); Some(1) }
        _ => None,
    }
}

/// What `hn new …` or `hn attach …` asks of the client it starts: the session (-s, or attach's
/// -t), made if it is new-session (-A: attached to if it is there), its first window's name (-n),
/// folder (-c) and command.
pub fn start_session(args: &[String]) -> Option<crate::app::StartSession> {
    let entry = crate::cmd::find(args.first()?).ok()?;
    let a = crate::cmd::parse(entry, args).ok()?;
    match entry.name {
        "new-session" => Some(crate::app::StartSession {
            name: a.get('s').map(str::to_string), create: true, attach_existing: a.has('A') > 0, window: a.get('n').map(str::to_string),
            cwd: a.get('c').map(str::to_string), command: (!a.values.is_empty()).then(|| a.values.join(" ")),
        }),
        "attach-session" => Some(crate::app::StartSession { name: a.get('t').map(|t| t.split(':').next().unwrap_or(t).to_string()).filter(|t| !t.is_empty()), cwd: a.get('c').map(str::to_string), ..Default::default() }),
        _ => None,
    }
}

/// Sessions with no client running (tmux's server answering alone): listed, checked, killed, or
/// made in the background (`new -d`: its shell started now, the session there for the next client).
async fn offline(port: u16, args: &[String], name: Option<&str>) -> i32 {
    let Ok(entry) = crate::cmd::find(&args[0]) else { return 1 };
    let a = match crate::cmd::parse(entry, args) { Ok(a) => a, Err(e) => { eprintln!("{e}"); return 1 } };
    let path = crate::app::sessions_path(name);
    let mut doc: Value = std::fs::read_to_string(&path).ok().and_then(|t| serde_json::from_str(&t).ok()).unwrap_or(json!({ "sessions": [] }));
    if !doc.get("sessions").map(Value::is_array).unwrap_or(false) { doc["sessions"] = json!([]) }
    // The desk's session: named as it was, else for this computer; its windows the desk's tabs.
    let (local, list) = machines(port).await.unwrap_or_default();
    let machine_name = list.iter().find(|(id, _, _)| *id == local).map(|(_, n, _)| n.clone()).unwrap_or_else(crate::app::hostname);
    let rows = doc["sessions"].as_array().cloned().unwrap_or_default();
    let desk_row = rows.iter().find(|r| r.get("desk").and_then(Value::as_bool).unwrap_or(false));
    let desk_name = desk_row.and_then(|r| r.get("name").and_then(Value::as_str)).map(str::to_string).unwrap_or(machine_name);
    let desk = http_json(port, "GET", "/api/desk", None).await.unwrap_or(json!({}));
    let desk_windows = desk.get("tabs").and_then(Value::as_array).map(|t| t.iter().filter(|t| t.get("panes").and_then(Value::as_array).map(|p| !p.is_empty()).unwrap_or(false)).count()).unwrap_or(0);
    let now = crate::app::epoch_secs();
    let mut sessions: Vec<(String, usize, i64, bool)> = vec![(desk_name.clone(), desk_windows, desk_row.and_then(|r| r.get("created").and_then(Value::as_i64)).unwrap_or(now), true)];
    for r in rows.iter().filter(|r| !r.get("desk").and_then(Value::as_bool).unwrap_or(false)) {
        let Some(n) = r.get("name").and_then(Value::as_str) else { continue };
        sessions.push((n.to_string(), r.get("windows").and_then(Value::as_array).map(|w| w.len()).unwrap_or(0), r.get("created").and_then(Value::as_i64).unwrap_or(now), false));
    }
    sessions.sort_by(|x, y| x.0.cmp(&y.0));
    // cmd_find_get_session: exact, the only one it starts, the only one it matches.
    let find = |t: &str| -> Option<usize> {
        let (exact, t) = match t.strip_prefix('=') { Some(t) => (true, t), None => (false, t) };
        let t = t.split(':').next().unwrap_or(t);
        if let Some(i) = sessions.iter().position(|s| s.0 == t) { return Some(i) }
        if exact { return None }
        let starts: Vec<usize> = (0..sessions.len()).filter(|i| sessions[*i].0.starts_with(t)).collect();
        if starts.len() == 1 { return Some(starts[0]) }
        if !starts.is_empty() { return None }
        let matched: Vec<usize> = (0..sessions.len()).filter(|i| crate::cmd::fnmatch(t, &sessions[*i].0)).collect();
        (matched.len() == 1).then(|| matched[0])
    };
    let save = |doc: &Value| { if let Some(dir) = path.parent() { let _ = std::fs::create_dir_all(dir); } let _ = std::fs::write(&path, doc.to_string()); };
    match entry.name {
        "list-sessions" => {
            let fmt = a.get('F').unwrap_or("#{session_name}: #{session_windows} windows (created #{t:session_created})");
            for (n, w, c, _) in &sessions {
                let line = fmt.replace("#{session_name}", n).replace("#S", n).replace("#{session_windows}", &w.to_string()).replace("#{t:session_created}", &crate::format::strftime_at("%a %b %e %H:%M:%S %Y", *c))
                    .replace("#{session_created}", &c.to_string()).replace("#{session_attached}", "0").replace("#{?session_attached, (attached),}", "");
                if !out(&format!("{line}\n")) { break }
            }
            0
        }
        "has-session" => {
            let t = a.get('t').unwrap_or("");
            if t.is_empty() || find(t).is_some() { 0 } else { eprintln!("can't find session: {t}"); 1 }
        }
        "kill-session" => {
            let t = a.get('t').unwrap_or("");
            let Some(i) = find(t) else { eprintln!("can't find session: {t}"); return 1 };
            let (n, _, _, is_desk) = sessions[i].clone();
            if is_desk { eprintln!("hn: the desk's session ({n}) is killed from a client: its windows are the account's tabs"); return 1 }
            // Its shells end, as its windows' would.
            let row = rows.iter().find(|r| r.get("name").and_then(Value::as_str) == Some(n.as_str())).cloned().unwrap_or(Value::Null);
            for w in row.get("windows").and_then(Value::as_array).cloned().unwrap_or_default() {
                for p in w.get("panes").and_then(Value::as_array).cloned().unwrap_or_default() {
                    let (Some(m), Some(id), true) = (p.get(0).and_then(Value::as_str), p.get(1).and_then(Value::as_str), p.get(2).and_then(Value::as_bool).unwrap_or(false)) else { continue };
                    let (tx, _rx) = mpsc::unbounded_channel();
                    let link = Link::spawn(port, m, 0, tx);
                    let _ = link.rpc("agent_delete", json!({ "agentId": id }), Duration::from_secs(15)).await;
                }
            }
            let kept: Vec<Value> = rows.into_iter().filter(|r| r.get("name").and_then(Value::as_str) != Some(n.as_str())).collect();
            doc["sessions"] = json!(kept);
            if doc.get("current").and_then(Value::as_str) == Some(n.as_str()) { doc["current"] = Value::Null }
            save(&doc);
            0
        }
        "new-session" => {
            let n = match a.get('s') { Some(s) => match crate::app::session_check_name(s) { Some(n) => n, None => { eprintln!("invalid session: {s}"); return 1 } }, None => { let mut k = 0; while sessions.iter().any(|s| s.0 == k.to_string()) { k += 1 } k.to_string() } };
            if sessions.iter().any(|s| s.0 == n) {
                if a.has('A') > 0 { return 0 }
                eprintln!("duplicate session: {n}"); return 1
            }
            if local.is_empty() { eprintln!("hn: the daemon is not running (harness start)"); return 1 }
            let cwd = a.get('c').map(str::to_string).or_else(|| std::env::current_dir().ok().map(|d| d.display().to_string()));
            let (tx, _rx) = mpsc::unbounded_channel();
            let link = Link::spawn(port, &local, 0, tx);
            let mut payload = json!({ "engine": "terminal", "creationId": uuid::Uuid::new_v4().to_string(), "bypassPermission": false });
            if let Some(c) = &cwd { payload["cwd"] = json!(c) }
            let reply = match link.rpc("agent_create", payload, Duration::from_secs(60)).await { Ok(r) => r, Err(e) => { eprintln!("create session failed: {e}"); return 1 } };
            let Some(id) = reply.pointer("/agent/id").and_then(Value::as_str) else { eprintln!("create session failed: no shell"); return 1 };
            let command = (!a.values.is_empty()).then(|| a.values.join(" "));
            if let Some(c) = &command { link.send("message", json!({ "agentId": id, "content": c })); }
            let shell = std::env::var("SHELL").unwrap_or_else(|_| "sh".into());
            let window = a.get('n').map(str::to_string).unwrap_or_else(|| command.as_deref().and_then(|c| c.split_whitespace().next()).unwrap_or(&shell).rsplit('/').next().unwrap_or("sh").to_string());
            let mut kept = rows;
            kept.push(json!({ "name": n, "desk": false, "created": now, "active": 0, "windows": [{ "name": window, "named": a.get('n').is_some(), "num": 0, "layout": "", "panes": [[local, id, true]], "focus": 0 }] }));
            doc["sessions"] = json!(kept);
            save(&doc);
            if a.has('P') > 0 { out(&format!("{}\n", a.get('F').unwrap_or("#{session_name}:").replace("#{session_name}", &n))); }
            0
        }
        _ => 1,
    }
}

async fn machines(port: u16) -> Result<(String, Vec<(String, String, bool)>), String> {
    let status = http_json(port, "GET", "/api/status", None).await.map_err(|e| format!("the daemon is not running ({e}) — harness start"))?;
    let local = status.get("machineId").and_then(Value::as_str).unwrap_or("").to_string();
    let reply = http_json(port, "GET", "/api/machines", None).await.unwrap_or(json!({}));
    let mut out = vec![(local.clone(), crate::app::hostname(), true)];
    for row in reply.get("machines").and_then(Value::as_array).cloned().unwrap_or_default() {
        let id = row.get("machineId").and_then(Value::as_str).unwrap_or("").to_string();
        let name = ["name", "hostname"].iter().filter_map(|k| row.get(*k).and_then(Value::as_str)).find(|s| !s.trim().is_empty()).unwrap_or(&id).to_string();
        // This computer by the name the fleet (and the status line) gives it.
        if id == local { out[0].1 = name; continue }
        if id.is_empty() { continue }
        let up = matches!(row.get("status").and_then(Value::as_str).unwrap_or("").to_ascii_lowercase().as_str(), "running" | "online" | "connected" | "ready");
        out.push((id, name, up));
    }
    Ok((local, out))
}

async fn roster(port: u16, machine: &str) -> Vec<crate::fleet::Agent> {
    let (tx, _rx) = mpsc::unbounded_channel();
    let link = Link::spawn(port, machine, 0, tx);
    let reply = link.rpc("agents_list", json!({}), Duration::from_secs(8)).await.unwrap_or(json!({}));
    reply.get("agents").and_then(Value::as_array).cloned().unwrap_or_default().iter().map(|r| agent_from(machine, r, None)).collect()
}

/// `hn list-harnesses`: `machine: name (engine) status  folder`, one line each, as `tmux ls` is
/// one per session.
async fn ls(port: u16) -> i32 {
    let (_, list) = match machines(port).await { Ok(m) => m, Err(e) => { eprintln!("hn: {e}"); return 1 } };
    for (id, name, up) in list {
        if !up { if !out(&format!("{name}: offline\n")) { break } continue }
        for a in roster(port, &id).await {
            if a.status == "stopped" { continue }
            if !out(&format!("{name}: {} ({}) {}  {}\n", a.name, a.engine, if a.working { "working" } else { a.status.as_str() }, a.cwd)) { return 0 }
        }
    }
    0
}

/// Standard output, written quietly: `hn … | head` closing the pipe is not an error (tmux's exits
/// the same way). False once nobody is reading.
pub fn out(text: &str) -> bool {
    use std::io::Write;
    let mut o = std::io::stdout().lock();
    o.write_all(text.as_bytes()).and_then(|_| o.flush()).is_ok()
}

/// `hn send-message -t <harness> <text…>`: the harness is a name (its start will do) or an id.
async fn send(port: u16, args: &[String]) -> i32 {
    let mut target = None;
    let mut text = Vec::new();
    let mut i = 0;
    while i < args.len() {
        if args[i] == "-t" { target = args.get(i + 1).cloned(); i += 2; continue }
        text.push(args[i].clone());
        i += 1;
    }
    let (Some(target), false) = (target, text.is_empty()) else { eprintln!("usage: hn send-message -t <harness> <text>"); return 2 };
    let (_, list) = match machines(port).await { Ok(m) => m, Err(e) => { eprintln!("hn: {e}"); return 1 } };
    let want = target.to_lowercase();
    for (id, _, up) in list {
        if !up { continue }
        if let Some(a) = roster(port, &id).await.into_iter().find(|a| a.id == target || a.name.to_lowercase().starts_with(&want)) {
            let (tx, _rx) = mpsc::unbounded_channel();
            let link = Link::spawn(port, &id, 0, tx);
            let _ = link.rpc("agents_list", json!({}), Duration::from_secs(8)).await;
            link.send("message", json!({ "agentId": a.id, "content": text.join(" ") }));
            tokio::time::sleep(Duration::from_millis(300)).await;
            return 0;
        }
    }
    eprintln!("hn: can't find harness: {target}");
    1
}
