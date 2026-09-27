//! The whole TUI's state and everything that changes it — except keys, which are `input.rs`, and
//! drawing, which is `ui.rs`. One owner, one loop: machine frames, terminal bytes, keys and the
//! results of background requests all arrive as `Event`s and are applied here in order.

use std::collections::{HashMap, HashSet};
use std::time::{Duration, Instant};

use ratatui::layout::Rect;
use ratatui::style::{Color, Modifier, Style};
use serde_json::{json, Value};
use tokio::sync::mpsc::UnboundedSender;
use uuid::Uuid;

use crate::daemon::{http_json, Link, RpcError};
use crate::event::{Event, MachineEvent};
use crate::fleet::{self, Fleet, Machine, Reach};
use crate::layout::{self, Dir, Node, Preset, Toward};
use crate::modal::Modal;
use crate::pane::{self, Pane, Phase};
use crate::proto::{self, Kind};
use crate::theme;

/// What tmux's parser asks of the server: its global environment, formats, home folders.
impl crate::cmdparse::Env for App {
    fn var(&self, name: &str) -> Option<String> { self.global_env.get(name).and_then(|e| e.value.clone()) }
    fn assign(&mut self, assignment: &str, hidden: bool) {
        let Some((k, v)) = assignment.split_once('=') else { return };
        self.global_env.insert(k.to_string(), EnvVar { value: Some(v.to_string()), hidden });
    }
    fn expand(&mut self, format: &str) -> String { crate::format::expand_nojobs(self, format) }
    fn home(&self, user: Option<&str>) -> Option<String> {
        if user.is_none() { if let Some(h) = self.var("HOME").filter(|h| !h.is_empty()) { return Some(h) } }
        let pw = unsafe { match user { Some(u) => { let c = std::ffi::CString::new(u).ok()?; libc::getpwnam(c.as_ptr()) } None => libc::getpwuid(libc::getuid()) } };
        if pw.is_null() { return None }
        Some(unsafe { std::ffi::CStr::from_ptr((*pw).pw_dir) }.to_string_lossy().into_owned())
    }
}

/// tmux's winlink alert flags.
pub const ACTIVITY: u8 = 1;
pub const BELL: u8 = 2;
pub const SILENCE: u8 = 4;

/// An environment's variable, as tmux's environ keeps one: a value, or none (cleared: `-NAME`,
/// taken away from what runs), and whether it is hidden (%hidden, set-environment -h).
#[derive(Clone, Debug, PartialEq)]
pub struct EnvVar { pub value: Option<String>, pub hidden: bool }

/// A session not on screen (tmux's sessions): its windows and what a session keeps of them,
/// swapped in whole when the client switches to it — or for a moment, while a command that names
/// it (`-t work:2`) runs. The session on screen keeps the same in App's own fields.
pub struct Stash {
    pub id: u32,
    /// Its name; None for the desk's session while it is named for this computer.
    pub alias: Option<String>,
    /// The desk's session: its windows are the desk's tabs, shared with every window on the account.
    pub desk: bool,
    pub tabs: Vec<Tab>,
    pub active: usize,
    pub lastw: Vec<String>,
    pub nums: HashMap<String, usize>,
    pub created: i64,
    /// When it was last used (session_update_activity): when the client left it, else when made.
    pub activity: i64,
    pub options: std::collections::BTreeMap<String, String>,
    pub env: std::collections::BTreeMap<String, EnvVar>,
}

/// What `hn new` or `hn attach` asked for when it started this client.
#[derive(Clone, Debug, Default)]
pub struct StartSession { pub name: Option<String>, pub create: bool, pub attach_existing: bool, pub window: Option<String>, pub cwd: Option<String>, pub command: Option<String>, pub target: Option<String> }

/// A session this client does not have: another client of this server name has it (`owner`, the
/// socket that client listens on), or none does (its client detached). As the sessions file says:
/// listed with this client's own, and made this client's when it is gone to.
#[derive(Clone, Debug)]
pub struct RemoteSession { pub id: u32, pub name: String, pub owner: Option<String>, pub front: bool, pub created: i64, pub activity: i64, pub active: usize, pub windows: Vec<(usize, String, usize)> }

/// The sessions file as last read (its time and size, and when its clients were last asked after),
/// the sessions in it this client does not have, and the ids this client gives them (`$N`).
#[derive(Default)]
pub struct Remote { stamp: Option<(std::time::SystemTime, u64)>, read_at: Option<Instant>, rows: Vec<RemoteSession>, pub ids: HashMap<String, u32> }

/// A wait-for channel (cmd-wait-for.c's wait_channel): woken with nobody waiting, locked, and who
/// waits for it or for its lock.
#[derive(Default)]
pub struct WaitChannel { pub woken: bool, pub locked: bool, pub waiters: Vec<tokio::sync::oneshot::Sender<()>>, pub lockers: std::collections::VecDeque<tokio::sync::oneshot::Sender<()>> }

/// How a client writes its sessions: as its own; one of them given up to another client; or every
/// one of them left for the next (it detaches).
#[derive(Clone, Copy, PartialEq, Debug)]
pub enum Save { Stay, Release(u32), Leave }

/// The sessions file, as read (empty when there is none).
pub fn read_sessions(path: &std::path::Path) -> Value {
    let mut doc: Value = std::fs::read_to_string(path).ok().and_then(|t| serde_json::from_str(&t).ok()).unwrap_or(Value::Null);
    if !doc.is_object() { doc = json!({}) }
    if !doc.get("sessions").map(Value::is_array).unwrap_or(false) { doc["sessions"] = json!([]) }
    doc
}

/// A session's client (its row's owner) while it runs: the socket it listens on.
pub fn live_owner(row: &Value) -> Option<String> {
    row.get("owner").and_then(Value::as_str).filter(|o| crate::ipc::answers(std::path::Path::new(o))).map(str::to_string)
}

/// Where a server name's (-L) sessions are kept between clients.
pub fn sessions_path(name: Option<&str>) -> std::path::PathBuf {
    let name = name.map(str::to_string).or_else(|| std::env::var("HN_SOCKET_NAME").ok()).filter(|n| !n.is_empty()).unwrap_or_else(|| "default".into());
    std::path::PathBuf::from(std::env::var("HOME").unwrap_or_default()).join(".harness").join("tui").join(format!("sessions-{name}.json"))
}

/// The agent a reply is about (`agentId`).
fn agent_id_of(reply: &Value) -> Option<String> { reply.get("agentId").and_then(Value::as_str).map(str::to_string) }

/// Seconds since the epoch.
pub fn epoch_secs() -> i64 { std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs() as i64).unwrap_or(0) }

/// session_check_name: a session's name as tmux keeps it — `:` and `.` (which targets read) as
/// `_`; none for an empty one.
pub fn session_check_name(name: &str) -> Option<String> {
    if name.is_empty() { return None }
    Some(name.chars().map(|c| if c == ':' || c == '.' { '_' } else { c }).collect())
}

/// Marks a printed text's last line as having no newline of its own (show-buffer's data).
pub const BARE: char = '\u{2}';

/// A command's answer to the shell that ran it: printed lines, errors, exit status.
pub type Reply = (Vec<String>, Vec<String>, i32);

pub struct Tab {
    /// The desk's tab id (32 hex), shared with every other window on the account.
    pub id: String,
    /// tmux's window id (#{window_id} `@N`): given when the window is made, never reused.
    pub wid: u64,
    pub name: String,
    pub named: bool,
    pub root: Option<Node>,
    pub focus: Option<u64>,
    pub zoomed: bool,
    /// tmux's w->last_panes: the panes that were active before this one, the latest first (`;`).
    pub last: Vec<u64>,
    /// tmux's w->panes: the order the panes are numbered in, which a layout does not change
    /// (main-horizontal-mirrored draws pane 0 at the bottom).
    pub order: Vec<u64>,
    /// tmux's active_point: when each pane last became the active one (higher is later).
    pub points: HashMap<u64, u64>,
    /// tmux's winlink alert flags (alerts.c): activity, bell, silence — set while the window is
    /// not the current one, cleared when it becomes current.
    pub alerts: u8,
    /// When a pane of the window last printed, or the window was chosen (monitor-silence counts
    /// from here).
    pub last_output: Instant,
    /// The same, in seconds since the epoch: #{window_activity}.
    pub activity: i64,
    /// The named layout last applied (tmux's w->lastlayout): where `next-layout` (Space) goes on
    /// from, none until one is chosen — the cycle then starts at even-horizontal.
    pub layout_at: Option<usize>,
    /// Whether the desk knows this tab yet (a new, empty tab is local until its first harness).
    pub on_desk: bool,
    /// synchronize-panes: keys go to every pane here.
    pub sync: bool,
    /// The desk's layout document for this tab, kept whole: a preset chosen here updates its entry
    /// and leaves the sizes other windows saved alone.
    pub layout: Value,
}

impl Tab {
    pub fn new(name: &str) -> Tab {
        static WID: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
        let wid = WID.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        Tab { id: Uuid::new_v4().simple().to_string(), wid, name: name.to_string(), named: false, root: None, focus: None, zoomed: false, last: Vec::new(), order: Vec::new(), points: HashMap::new(), alerts: 0, last_output: Instant::now(), activity: crate::format::now_secs(), layout_at: None, on_desk: false, sync: false, layout: json!({}) }
    }
    /// window_update_activity: something happened in the window just now — its activity time,
    /// and the silence timer starts again (alerts_reset).
    pub fn touch(&mut self) { self.last_output = Instant::now(); self.activity = crate::format::now_secs() }
    /// The panes in tmux's order (pane_index); one the list has not placed yet comes last.
    pub fn panes(&self) -> Vec<u64> {
        let leaves = self.root.as_ref().map(Node::leaves).unwrap_or_default();
        let mut out: Vec<u64> = self.order.iter().copied().filter(|p| leaves.contains(p)).collect();
        out.extend(leaves.into_iter().filter(|p| !self.order.contains(p)));
        out
    }
    /// The pane `;` goes back to.
    pub fn last_focus(&self) -> Option<u64> { self.last.first().copied() }
    /// tmux's window_set_active_pane: the pane left goes on top of the last-panes stack.
    pub fn set_active(&mut self, pane: u64) {
        if self.focus == Some(pane) { return }
        self.last.retain(|p| *p != pane);
        if let Some(old) = self.focus { self.last.retain(|p| *p != old); self.last.insert(0, old) }
        self.focus = Some(pane);
        static POINT: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(1);
        self.points.insert(pane, POINT.fetch_add(1, std::sync::atomic::Ordering::Relaxed));
    }
    /// tmux's window_add_pane: after `other` (the active pane), before it with -b; -f at the
    /// end of the list (-bf the start).
    pub fn add_pane(&mut self, pane: u64, other: Option<u64>, before: bool, full: bool) {
        let mut order = self.panes();
        order.retain(|p| *p != pane);
        let other = other.or(self.focus).and_then(|o| order.iter().position(|p| *p == o));
        let at = match (full, other) {
            _ if order.is_empty() => 0,
            (true, _) => if before { 0 } else { order.len() },
            (false, Some(i)) => if before { i } else { i + 1 },
            (false, None) => order.len(),
        };
        order.insert(at, pane);
        self.order = order;
    }
    /// tmux's window_lost_pane: a pane leaves; if it was the active one, the last pane takes
    /// over, else the one before it in the list, else the one after. (Before it leaves the layout.)
    pub fn lose(&mut self, pane: u64) {
        let order = self.panes();
        self.last.retain(|p| *p != pane);
        if self.focus == Some(pane) {
            let at = order.iter().position(|p| *p == pane);
            let next = self.last.first().copied()
                .or_else(|| at.and_then(|i| i.checked_sub(1)).map(|i| order[i]))
                .or_else(|| at.and_then(|i| order.get(i + 1).copied()));
            if let Some(n) = next { self.last.retain(|p| *p != n) }
            self.focus = next;
        }
        self.order = order.into_iter().filter(|p| *p != pane).collect();
    }
}

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum DeskMode { Off, Read, Sync }

struct LinkState {
    link: Option<Link>,
    generation: u64,
    attempts: u32,
    retry_at: Option<Instant>,
}

pub struct App {
    pub port: u16,
    pub sink: UnboundedSender<Event>,
    pub fleet: Fleet,
    links: HashMap<String, LinkState>,
    generation: u64,
    pub tabs: Vec<Tab>,
    pub active: usize,
    pub panes: HashMap<u64, Pane>,
    next_pane: u64,
    pub modal: Option<Modal>,
    pub toast: Option<(String, Color, Instant)>,
    /// How long hn's own notice stays (a harness waiting on you: longer than display-time's
    /// 750 ms, which is for tmux's messages); none for any other message.
    pub toast_hold: Option<u64>,
    /// tmux `display-time`: how long a message holds the status line.
    pub display_ms: u64,
    pub display_panes_ms: u64,
    /// tmux `base-index` / `pane-base-index`.
    pub base_index: usize,
    /// Everything said in the status line, for `show-messages` (C-b ~).
    pub messages: Vec<(std::time::SystemTime, String)>,
    /// Paste buffers, newest first (copy mode's `y`, and `paste-buffer`).
    /// tmux's paste buffers (paste.c).
    pub paste: crate::paste::Paste,
    pub keymap: crate::keys::Keymap,
    /// Colours from ~/.tmux.conf (status, messages, borders).
    pub look: crate::tmuxconf::Look,
    /// Until when a `-r` key may be pressed again without the prefix.
    pub repeat_until: Option<Instant>,
    /// Redraw everything next frame (refresh-client).
    pub redraw_all: bool,
    /// tmux `status-position`.
    pub status_top: bool,
    pub mouse: bool,
    /// The harness focused before this one, anywhere (switch-client -l).
    pub last_harness: Option<(String, String)>,
    /// The pane next-harness (C-b a) last showed a harness in: pressed again from there, the next
    /// one takes its place, so going through the queue keeps to one window.
    pub loop_pane: Option<u64>,
    /// The harnesses this go down the queue has shown, so C-b a walks all of them once (an
    /// unanswered one is not shown again until the rest have been).
    pub loop_seen: Vec<(String, String)>,
    /// `agent_recent` answers (asks and recaps), for the preview window.
    pub recent: HashMap<(String, String), Value>,
    /// Seconds east of UTC (for the status line's clock).
    /// The prompts' histories (Up/Down), one per type: command, search, target, window-target.
    pub history: [Vec<String>; 4],
    pub size: (u16, u16),
    /// Each visible pane's full rect (header row included), from the last layout.
    pub rects: Vec<(u64, Rect)>,
    pub quit: bool,
    /// The last window went (tmux's session ended): hn says `[exited]`, not `[detached …]`.
    pub exited: bool,
    /// Where the startup shell stands: the desk has answered (or there is none), and whether
    /// the shell was asked for.
    desk_answered: bool,
    shell_asked: bool,
    pub prefix: bool,
    /// When the prefix was pressed: a pause after it shows the keys (which-key).
    pub prefix_at: Option<Instant>,
    pub tick: u64,
    pub home_cursor: usize,
    pub desk_mode: DeskMode,
    pub desk_revision: i64,
    desk_loaded: bool,
    pub started: Instant,
    pub daemon_down: bool,
    pub dsh: HashMap<String, Vec<Value>>,
    /// Each harness's selectable models (`models_list`), for ⌥I.
    pub models: HashMap<(String, String), Vec<Value>>,
    /// Each machine's local models (the grid): downloaded, running, available.
    pub local_models: HashMap<String, Vec<Value>>,
    /// Each machine's last measured round trip (the live roster request), for `@`.
    pub rtt: HashMap<String, Duration>,
    pub homes: HashMap<String, String>,
    last_focus_sent: Option<(String, String)>,
    /// The mouse event of the key whose commands are running (tmux's item event): `-t =`, the
    /// commands' target, send-keys -M and the mouse_* formats read it.
    pub mouse_ev: Option<crate::mouse::Event>,
    /// The client's mouse: the last event, a drag, the clicks being counted.
    pub mouse_state: crate::mouse::State,
    /// The last click in a list (row, when) — a second one opens it.
    pub last_click: Option<(u64, u16, u16, Instant, u8)>,
    /// What the outer terminal's title was last set to.
    pub title: String,
    pub first_frame: bool,
    /// The status line's ranges as drawn (row, range): where a click lands (status_get_range).
    pub status_ranges: Vec<(u16, crate::draw::Range)>,
    /// Terminal frames for a stream no pane has yet — the keyframe can outrun `terminal_ready`.
    orphans: HashMap<Uuid, (Instant, Vec<proto::Frame>)>,
    /// Desk writes sent and not yet answered; while any are out, the desk is not reconciled.
    desk_inflight: u32,
    /// The desk moved while writes were out: fetch it once they land.
    desk_stale: bool,
    /// tmux's s->lastw: the windows current before, the most recent first, by tab id — C-b l goes
    /// back to the first (the - flag's); closing the current window lands there.
    pub lastw: Vec<String>,
    /// tmux's window indexes, by tab id: given once, kept until the window closes (a gap stays).
    pub nums: HashMap<String, usize>,
    /// The cursor shape last sent to the terminal.
    pub cursor_shape: String,
    /// suspend-client (C-z): the main loop hands the terminal back and stops itself.
    pub suspend: bool,
    /// Output of a command run from a shell (`hn display -p …`): printed there, not on screen.
    pub capture: Option<Vec<String>>,
    /// -P [-F fmt] on split-window / new-window: print the new pane once it is there; the
    /// shell that asked waits for it (the reply is held here).
    pub print_new: Option<String>,
    /// rename-session: what this session is called here (else the machine's name).
    pub session_alias: Option<String>,
    /// The other sessions (tmux's), each kept whole until the client switches to it.
    pub sessions: Vec<Stash>,
    /// This session's id (`$N`), whether its windows are the desk's, and when it was made.
    pub session_id: u32,
    pub session_desk: bool,
    pub session_created: i64,
    /// When the session in front was last used: when the client last left it (the client's own
    /// is in use now).
    pub session_activity: i64,
    /// The session the client was in before this one (switch-client -l, C-b L).
    pub last_session: Option<u32>,
    pub next_session_id: std::cell::Cell<u32>,
    /// The sessions this client does not have (other clients', or no client's), as the file said.
    pub remote: std::cell::RefCell<Remote>,
    /// This client gave its sessions to another (a terminal attached to the one it showed, as
    /// `attach -d`): it writes none of them again.
    pub handed_over: bool,
    /// Its sessions' windows and panes as last written (save_if_changed).
    pub sessions_sig: String,
    /// wait-for's channels, by name.
    pub wait_channels: HashMap<String, WaitChannel>,
    /// No terminal (--headless): tmux's server with no client attached, holding sessions for
    /// the commands of a script until a client takes them.
    pub headless: bool,
    /// While a command runs in another session (`-t work:2`): the session to come back to.
    pub swap_back: Option<u32>,
    /// The session asked for at start (`hn new -A -s main`, `hn attach -t work`).
    pub start_session: Option<StartSession>,
    /// Why the start asked for could not be done (`can't find session: work`).
    pub start_failed: Option<String>,
    /// kill-server: no session is kept for the next client.
    pub forget_sessions: bool,
    /// Questions out to the daemons about harnesses (recaps, pull requests), at most a few at once.
    pub enriching: u32,
    /// The key being handled (its tmux name), and the one whose binding's commands are running —
    /// for the message log (`/dev/ttys003 key C-b: …`); the log starts once the config is read.
    /// Each machine's agent accounts' rate limits (usage_read), and when they were last asked.
    pub usage: HashMap<String, Vec<fleet::Usage>>,
    pub usage_checked: Option<Instant>,
    pub key_name: Option<String>,
    pub key_run: Option<String>,
    pub cfg_finished: bool,
    /// When the terminal lost focus, and the fleet's counts then (needs you, failed, done).
    pub away: Option<(Instant, (usize, usize, usize))>,
    /// When you last looked at each harness (ms), kept between runs (~/.harness/tui/seen.json):
    /// one that did something after it, while hn was closed or on another screen, is done and
    /// unread when hn next hears of it. Before [seen_since] (hn's first run) everything counts as
    /// seen. [seen_rostered]: the machines whose first roster has been read against it.
    pub seen_at: HashMap<(String, String), u64>,
    pub seen_since: u64,
    pub seen_dirty: bool,
    pub seen_rostered: HashSet<String>,
    /// select-pane -m: the marked pane (join-pane and swap-pane take it as their source).
    pub marked: Option<u64>,
    /// new-window -d: the window to go back to (and the last window then) once its shell is up.
    pub return_to: Option<(String, Vec<String>)>,
    pub held_reply: Option<tokio::sync::oneshot::Sender<Reply>>,
    /// A command that waits for what it opened (display-menu; command-prompt and confirm-before
    /// without -b): the shell that ran it is answered when that closes (CMD_RETURN_WAIT).
    pub wait_cli: bool,
    waiting_reply: Option<(tokio::sync::oneshot::Sender<Reply>, Reply)>,
    /// The shell waiting on the command it ran (hn <command>): its answer goes here when the
    /// command is done — at once, or when a job it waits on (run-shell, if-shell) has finished.
    pub cli_tx: Option<tokio::sync::oneshot::Sender<Reply>>,
    /// That command's exit status (run-shell's, when its shell command failed).
    pub cli_code: i32,
    /// That shell's folder: where run-shell and if-shell run what it asked (tmux's client cwd).
    pub cli_cwd: Option<String>,
    /// #{command_list_name} #{command_list_alias} #{command_list_usage} (list-commands -F).
    pub format_command: Option<(String, String, String)>,
    /// The config files read at start (#{config_files}).
    pub config_files: Vec<String>,
    /// #{line}: the row a list-* command is printing.
    pub format_line: Option<usize>,
    /// format_defaults' type while choose-tree expands an item's format (tree::FORMAT_*): what
    /// #{session_format}, #{window_format} and #{pane_format} say.
    pub format_type: Option<u8>,
    /// How many times the status line has been drawn again for a key (server_status_client: a
    /// key with a binding, the prefix, a table left) — a pane's tree is built again then.
    pub status_redraws: u64,
    /// The paste buffer a format is expanded for (list-buffers -F).
    pub format_buffer: Option<String>,
    /// The harness a format is about (list-harnesses -F): its #{harness_*} values.
    pub format_agent: Option<(String, String)>,
    /// What the shell running the command piped in (load-buffer -, source-file -).
    pub cli_stdin: Option<String>,
    /// The file and line the running command was read from (a config's): its errors say so.
    pub origin: Option<(std::sync::Arc<str>, usize)>,
    /// Commands to run next, before the rest of the queue (source-file's).
    pub insert_next: std::collections::VecDeque<crate::commands::Item>,
    /// The hook whose commands are running (their formats and current pane); commands run from a
    /// hook fire none of their own.
    pub hook_state: Option<std::sync::Arc<crate::commands::HookState>>,
    /// Event hooks waiting to run (notify_add queues them; they run once the event's work is
    /// done).
    pub pending_hooks: std::collections::VecDeque<crate::commands::Item>,
    /// Errors said so far (a command that failed fires command-error, not its after- hook).
    pub errors: u64,
    /// A config file's errors (cfg_add_cause), shown in the current pane's view mode once there
    /// is one (cfg_show_causes), as tmux shows them when the client attaches.
    pub config_causes: Vec<String>,
    /// pipe-pane's pipes, by pane: what the pane prints goes to the command (-O).
    pub pipes: HashMap<u64, Pipe>,
    pipe_seq: u64,
    /// What the event hooks were last told of (notify_changes compares against it).
    pub hooks_seen: HooksSeen,

    pub capture_err: Option<Vec<String>>,
    /// tmux's global environment: what hn started with, then set-environment -g and a config's
    /// `NAME=value` (%hidden ones hidden).
    pub global_env: std::collections::BTreeMap<String, EnvVar>,
    /// The session's environment: update-environment's variables, as they were when hn started
    /// (set, or cleared when hn had none).
    pub session_env: std::collections::BTreeMap<String, EnvVar>,
    /// tim, the creature in the status line.
    pub tim: crate::tim::Tim,
    /// Shells hn made for split-window / new-window: they end with their pane.
    pub shells: HashSet<(String, String)>,
    /// Keys typed while a split's shell starts, for it.
    pub starting_shell: Option<Vec<Vec<u8>>>,
    /// tmux's status/window/border/copy options from tmux.conf or `set`.
    pub opts: crate::tmuxconf::Options,
    /// The home list's order while it is on screen (see `home_agents`).
    pub home_order: std::cell::RefCell<Vec<(String, String)>>,
    pub mouse_changed: bool,
    /// Whether the terminal window has focus (focus reporting) — notifications go out when it does not.
    pub terminal_focused: bool,
    /// The Harness device on this desk, and hn's half of talking to it (dial.rs).
    pub dial: crate::dial::Dial,
    /// A key table of your own the next key is looked up in (`switch-client -T`).
    pub key_table: Option<String>,
    /// tmux's options, as set (options.rs): what show-options prints and formats read.
    pub options: crate::options::Store,
    /// `#()` commands in formats: their last output, run again every status-interval.
    pub jobs: std::cell::RefCell<std::collections::HashMap<String, crate::format::Job>>,
    pub fleet_marked: bool,
}

impl App {
    pub fn new(port: u16, sink: UnboundedSender<Event>, size: (u16, u16)) -> App {
        let desk_mode = match std::env::var("HARNESS_TUI_DESK").as_deref() {
            Ok("off") => DeskMode::Off,
            Ok("read") => DeskMode::Read,
            _ => DeskMode::Sync,
        };
        App {
            port,
            sink,
            fleet: Fleet::default(),
            links: HashMap::new(),
            generation: 0,
            tabs: vec![Tab::new("home")],
            active: 0,
            panes: HashMap::new(),
            next_pane: 1,
            modal: None,
            toast: None,
            display_ms: 750,
            toast_hold: None,
            display_panes_ms: 1000,
            base_index: 0,
            nums: HashMap::new(),
            cursor_shape: String::new(),
            suspend: false,
            capture: None,
            print_new: None,
            session_alias: None,
            sessions: Vec::new(),
            session_id: 0,
            // desk=off: the first session is a session like any other (tmux's `0`).
            session_desk: desk_mode != DeskMode::Off,
            session_created: epoch_secs(),
            session_activity: epoch_secs(),
            last_session: None,
            next_session_id: std::cell::Cell::new(1),
            remote: Default::default(),
            handed_over: false,
            sessions_sig: String::new(),
            headless: false,
            wait_channels: HashMap::new(),
            swap_back: None,
            start_session: None,
            start_failed: None,
            forget_sessions: false,
            enriching: 0,
            usage: HashMap::new(),
            usage_checked: None,
            key_name: None,
            key_run: None,
            cfg_finished: false,
            away: None,
            seen_at: HashMap::new(),
            seen_since: 0,
            seen_dirty: false,
            seen_rostered: HashSet::new(),
            marked: None,
            return_to: None,
            held_reply: None,
            wait_cli: false,
            waiting_reply: None,
            cli_tx: None,
            cli_code: 0,
            cli_cwd: None,
            origin: None,
            format_buffer: None,
            format_agent: None,
            format_line: None,
            format_type: None,
            status_redraws: 0,
            config_files: Vec::new(),
            format_command: None,
            cli_stdin: None,
            insert_next: std::collections::VecDeque::new(),
            hook_state: None,
            pending_hooks: std::collections::VecDeque::new(),
            errors: 0,
            pipes: HashMap::new(),
            config_causes: Vec::new(),
            pipe_seq: 0,
            hooks_seen: HooksSeen::default(),

            capture_err: None,
            global_env: std::env::vars().map(|(k, v)| (k, EnvVar { value: Some(v), hidden: false })).collect(),
            session_env: Default::default(),
            tim: crate::tim::Tim::load(),
            shells: HashSet::new(),
            starting_shell: None,
            opts: Default::default(),
            prefix_at: None,
            home_order: Default::default(),
            mouse_changed: false,
            messages: Vec::new(),
            paste: Default::default(),
            keymap: crate::keys::Keymap::tmux_defaults(),
            look: Default::default(),
            repeat_until: None,
            redraw_all: false,
            status_top: false,
            mouse: true,
            loop_seen: Vec::new(),
            loop_pane: None,
            last_harness: None,
            history: Default::default(),
            recent: HashMap::new(),
            size,
            rects: Vec::new(),
            quit: false,
            prefix: false,
            tick: 0,
            home_cursor: 0,
            desk_mode,
            desk_revision: -1,
            desk_loaded: false,
            exited: false,
            desk_answered: false,
            shell_asked: false,
            started: Instant::now(),
            daemon_down: false,
            dsh: HashMap::new(),
            models: HashMap::new(),
            local_models: HashMap::new(),
            rtt: HashMap::new(),
            homes: HashMap::new(),
            last_focus_sent: None,
            mouse_ev: None,
            mouse_state: Default::default(),
            last_click: None,
            title: String::new(),
            first_frame: false,
            status_ranges: Vec::new(),
            orphans: HashMap::new(),
            desk_inflight: 0,
            desk_stale: false,
            lastw: Vec::new(),
            terminal_focused: true,
            dial: Default::default(),
            options: Default::default(),
            jobs: Default::default(),
            key_table: None,
            fleet_marked: false,
        }
    }

    // ── background work ──────────────────────────────────────────────────────

    /// Run [work] off the loop and apply its result on it.
    pub fn spawn<F, T>(&self, work: F, then: impl FnOnce(&mut App, T) + Send + 'static)
    where
        F: std::future::Future<Output = T> + Send + 'static,
        T: Send + 'static,
    {
        let sink = self.sink.clone();
        tokio::spawn(async move {
            let result = work.await;
            let _ = sink.send(Event::Apply(Box::new(move |app: &mut App| then(app, result))));
        });
    }

    /// A message in the status line (tmux `display-message`), kept for `show-messages`.
    pub fn say(&mut self, text: impl Into<String>, color: Color) {
        let text = text.into();
        // A config's command: its errors say where it was read (file:line:), as tmux's do.
        let text = match &self.origin { Some((file, line)) => format!("{file}:{line}: {text}"), None => text };
        // Run from a shell: a message is the command's error, printed there.
        if let Some(err) = self.capture_err.as_mut() { err.push(text); return }
        self.add_message(format!("{} message: {text}", tty_name()));
        self.toast = Some((text, color, Instant::now()));
        self.toast_hold = None;
    }

    /// How long the message on the status line stays: display-time, or longer for hn's notice.
    pub fn toast_ms(&self) -> u64 { self.toast_hold.unwrap_or(0).max(self.display_ms) }

    /// The fleet in counts: needs you, failed, done and unread.
    pub fn fleet_counts(&self) -> (usize, usize, usize) {
        use crate::fleet::State::*;
        (self.fleet.count(NeedsInput), self.fleet.count(Failed), self.fleet.count(Done))
    }

    /// Back after a while away (the terminal's focus gone three minutes or more): what changed
    /// meanwhile, and the key that goes through it — when something did.
    pub fn welcome_back(&mut self) {
        let Some((at, (needs0, failed0, done0))) = self.away.take() else { return };
        let gone = at.elapsed();
        if gone < Duration::from_secs(180) { return }
        let (needs, failed, done) = self.fleet_counts();
        let mut parts = Vec::new();
        if done > done0 { parts.push(format!("✓{} finished", done - done0)) }
        if needs > needs0 { parts.push(format!("?{} need you", needs - needs0)) }
        if failed > failed0 { parts.push(format!("✗{} failed", failed - failed0)) }
        if parts.is_empty() { return }
        let mins = gone.as_secs() / 60;
        let away = if mins >= 60 { format!("{}h{:02}m", mins / 60, mins % 60) } else { format!("{mins}m") };
        let key = self.keymap.key_for_name("next-harness").unwrap_or_else(|| "C-b a".into());
        self.say(format!("While you were away ({away}): {} — {key} goes through them", parts.join(" · ")), crate::theme::ATTENTION);
    }

    /// server_add_message: a line into the message log (C-b ~), at most message-limit of them.
    pub fn add_message(&mut self, text: String) {
        self.messages.push((std::time::SystemTime::now(), text));
        let limit: usize = self.options.get("message-limit", "", None).and_then(|v| v.parse().ok()).unwrap_or(1000);
        if self.messages.len() > limit { let over = self.messages.len() - limit; self.messages.drain(..over); }
    }

    /// A command's error (cmdq_error): to a shell that ran the command as it is, and on the status
    /// line with its first letter a capital, as tmux shows it there ("Invalid layout: foo"); a
    /// config file's keeps its file:line and its case.
    pub fn error(&mut self, text: impl Into<String>) {
        self.errors += 1;
        let mut text = text.into();
        // A config file's command (cfg_add_cause): kept, with its file and line, for view mode.
        if self.capture_err.is_none() {
            if let Some((file, line)) = &self.origin { self.config_causes.push(format!("{file}:{line}: {text}")); return }
        }
        if self.capture_err.is_none() && self.origin.is_none() {
            if let Some(c) = text.chars().next() { text = c.to_uppercase().collect::<String>() + &text[c.len_utf8()..] }
        }
        self.say(text, theme::WARN)
    }

    pub fn link(&self, machine_id: &str) -> Option<Link> {
        self.links.get(machine_id).and_then(|s| s.link.clone()).filter(|_| self.fleet.machine(machine_id).map(Machine::usable).unwrap_or(false))
    }

    // ── start: this machine, the account's machines, the desk ─────────────────

    pub fn boot(&mut self) {
        if self.fleet.agents.is_empty() && self.fleet.machines.is_empty() { self.fleet.load_cache() }
        let port = self.port;
        self.spawn(async move { http_json(port, "GET", "/api/status", None).await }, |app, status| match status {
            Ok(status) => {
                app.daemon_down = false;
                let id = status.get("machineId").and_then(Value::as_str).unwrap_or("").to_string();
                if status.get("signedIn").and_then(Value::as_bool) == Some(false) {
                    app.say("This computer is not signed in — run `harness login`", theme::DANGER);
                }
                if id.is_empty() { return }
                app.fleet.local_id = id.clone();
                if app.fleet.machine(&id).is_none() {
                    app.fleet.machines.insert(0, Machine { id: id.clone(), name: hostname(), local: true, status: "running".into(), reach: Reach::Unknown });
                }
                app.connect(&id);
                app.refresh_machines();
            }
            Err(_) => {
                app.daemon_down = true;
                app.retry_boot();
            }
        });
    }

    fn retry_boot(&mut self) {
        let sink = self.sink.clone();
        tokio::spawn(async move {
            tokio::time::sleep(Duration::from_secs(2)).await;
            let _ = sink.send(Event::Apply(Box::new(|app: &mut App| app.boot())));
        });
    }

    pub fn refresh_machines(&mut self) {
        let port = self.port;
        self.spawn(async move { http_json(port, "GET", "/api/machines", None).await }, |app, reply| {
            let Ok(reply) = reply else { return };
            let rows = reply.get("machines").and_then(Value::as_array).cloned().unwrap_or_default();
            let local = app.fleet.local_id.clone();
            for row in rows {
                let id = row.get("machineId").and_then(Value::as_str).unwrap_or("").to_string();
                if id.is_empty() { continue }
                let name = ["name", "hostname"].iter().filter_map(|k| row.get(*k).and_then(Value::as_str)).map(str::trim).find(|s| !s.is_empty()).unwrap_or(&id[..8.min(id.len())]).to_string();
                let status = row.get("status").and_then(Value::as_str).unwrap_or("unknown").to_string();
                match app.fleet.machine_mut(&id) {
                    Some(machine) => { machine.name = name; machine.status = status }
                    None => app.fleet.machines.push(Machine { local: id == local, id: id.clone(), name, status, reach: Reach::Unknown }),
                }
            }
            // This computer first, then the ones that are up.
            app.fleet.machines.sort_by_key(|m| (!m.local, !m.online(), m.name.to_lowercase()));
            let ids: Vec<String> = app.fleet.machines.iter().filter(|m| m.online() && matches!(m.reach, Reach::Unknown | Reach::Error(_))).map(|m| m.id.clone()).collect();
            for id in ids { app.connect(&id) }
            for machine in app.fleet.machines.iter_mut() { if !machine.online() && machine.reach == Reach::Unknown { machine.reach = Reach::Offline } }
        });
    }

    pub fn connect(&mut self, machine_id: &str) {
        if let Some(state) = self.links.get(machine_id) {
            if state.link.is_some() { return }
        }
        self.generation += 1;
        let link = Link::spawn(self.port, machine_id, self.generation, self.sink.clone());
        let attempts = self.links.get(machine_id).map(|s| s.attempts).unwrap_or(0);
        self.links.insert(machine_id.to_string(), LinkState { link: Some(link), generation: self.generation, attempts, retry_at: None });
        if let Some(machine) = self.fleet.machine_mut(machine_id) { machine.reach = Reach::Connecting }
    }

    fn schedule_reconnect(&mut self, machine_id: &str) {
        let Some(state) = self.links.get_mut(machine_id) else { return };
        state.link = None;
        state.attempts += 1;
        let wait = Duration::from_millis((500 * 2u64.pow(state.attempts.min(5))).min(15_000));
        state.retry_at = Some(Instant::now() + wait);
    }

    // ── machine events ───────────────────────────────────────────────────────

    pub fn on_machine(&mut self, machine_id: String, generation: u64, event: MachineEvent) {
        let current = self.links.get(&machine_id).map(|s| s.generation) == Some(generation);
        if !current { return }
        match event {
            MachineEvent::Connected => {
                if let Some(state) = self.links.get_mut(&machine_id) { state.attempts = 0 }
                if let Some(machine) = self.fleet.machine_mut(&machine_id) { machine.reach = Reach::Ready }
                if machine_id == self.fleet.local_id { self.daemon_down = false; crate::dial::reconnected(self) }
                self.relist(&machine_id);
                // Its home folder, so its paths read `~/…` like this machine's do.
                if !self.homes.contains_key(&machine_id) {
                    if let Some(link) = self.link(&machine_id) {
                        let id = machine_id.clone();
                        self.spawn(async move { link.rpc("fs_list_dir", json!({}), Duration::from_secs(20)).await }, move |app, reply| {
                            if let Some(path) = reply.ok().and_then(|r| r.get("path").and_then(Value::as_str).map(str::to_string)) { app.homes.insert(id, path); }
                        });
                    }
                }
                if machine_id == self.fleet.local_id && !self.desk_loaded { self.load_desk() }
                // Every pane of this machine that lost its stream gets it back.
                let ids: Vec<u64> = self.panes.values().filter(|p| p.machine_id == machine_id && p.stream.is_none() && !matches!(p.phase, Phase::Card { .. })).map(|p| p.id).collect();
                for id in ids { self.open_stream(id, false) }
            }
            MachineEvent::Failed(error) | MachineEvent::Closed(error) => {
                let needs_link = error.code == "NO_PEER_LINK";
                if let Some(machine) = self.fleet.machine_mut(&machine_id) {
                    machine.reach = if needs_link { Reach::NeedsLink } else if machine.online() { Reach::Error(error.to_string()) } else { Reach::Offline };
                }
                if machine_id == self.fleet.local_id && error.code == "DAEMON_UNREACHABLE" { self.daemon_down = true }
                for pane in self.panes.values_mut().filter(|p| p.machine_id == machine_id) {
                    pane.stream = None;
                    pane.opening = false;
                    pane.open_token += 1;
                    if !matches!(pane.phase, Phase::Card { .. }) {
                        pane.phase = if needs_link {
                            Phase::Card { title: "This machine is not linked here".into(), detail: format!("Link it once with its remote password (machines, then C-l), or run:\nharness link connect {machine_id}"), keys: vec![("enter".into(), "retry".into()), (self.keymap.hint("choose-tree -m").unwrap_or_default(), "machines".into())] }
                        } else {
                            Phase::Connecting(format!("Reconnecting to {}…", self.fleet.machines.iter().find(|m| m.id == machine_id).map(|m| m.name.clone()).unwrap_or_default()))
                        };
                    }
                    pane.dirty = true;
                }
                if needs_link { if let Some(state) = self.links.get_mut(&machine_id) { state.link = None } }
                else { self.schedule_reconnect(&machine_id) }
            }
            MachineEvent::Terminal(frame) => self.on_terminal(frame),
            MachineEvent::Frame { ty, payload } => self.on_frame(&machine_id, &ty, payload),
        }
    }

    pub fn relist(&mut self, machine_id: &str) {
        let Some(link) = self.link(machine_id) else { return };
        let id = machine_id.to_string();
        // Live harnesses first: the daemon answers those in milliseconds, while the list with every
        // paused one costs it most of a second. Paint what is running, then fold the rest in.
        let fast = link.clone();
        let fast_id = id.clone();
        self.spawn(async move { let t = Instant::now(); (fast.rpc("agents_list", json!({}), Duration::from_secs(20)).await, t.elapsed()) }, move |app, (reply, took)| {
            if reply.is_ok() { app.rtt.insert(fast_id.clone(), took); }
            if let Ok(reply) = reply {
                let rows = reply.get("agents").and_then(Value::as_array).cloned().unwrap_or_default();
                app.fleet.merge_roster(&fast_id, &rows);
                app.sync_titles();
            }
        });
        let asked = Instant::now();
        self.spawn(async move { link.rpc("agents_list", json!({ "includeStopped": true }), Duration::from_secs(20)).await }, move |app, reply| {
            if let Ok(reply) = reply {
                let rows = reply.get("agents").and_then(Value::as_array).cloned().unwrap_or_default();
                app.fleet.replace_roster(&id, &rows, asked);
                app.catch_up(&id);
                app.sync_titles();
            }
        });
    }

    fn on_frame(&mut self, machine_id: &str, ty: &str, payload: Value) {
        // The dial's frames come from this computer's daemon, to the windows on it.
        if machine_id == self.fleet.local_id && crate::dial::on_frame(self, ty, &payload) { return }
        match ty {
            "agent_synced" | "agent_created" | "agent_renamed" => {
                let row = payload.get("agent").cloned().unwrap_or(payload.clone());
                let Some(id) = row.get("id").and_then(Value::as_str).map(str::to_string) else { return };
                let key = (machine_id.to_string(), id);
                if ty == "agent_renamed" && row.get("engine").is_none() {
                    if let (Some(agent), Some(name)) = (self.fleet.agents.get_mut(&key), row.get("name").and_then(Value::as_str)) { agent.name = name.to_string() }
                } else {
                    let agent = fleet::agent_from(machine_id, &row, self.fleet.agents.get(&key));
                    self.fleet.agents.insert(key, agent);
                }
                self.sync_titles();
            }
            "agent_deleted" => {
                let id = payload.get("agentId").or_else(|| payload.get("id")).and_then(Value::as_str).unwrap_or("");
                if let Some(agent) = self.fleet.agents.get_mut(&(machine_id.to_string(), id.to_string())) {
                    agent.status = "stopped".into();
                    agent.working = false;
                    agent.question = None;
                }
                self.relist(machine_id);
            }
            "turn_started" | "turn_heartbeat" | "tool_start" | "tool_end" | "text_delta" | "thinking_title" => {
                if let Some(agent) = self.fleet.event_agent(machine_id, &payload) {
                    let now = fleet::now_ms();
                    // A turn begun (or found running): the state's clock starts, what it says anew.
                    if ty == "turn_started" || !agent.working { agent.since = now; agent.doing = None; agent.said.clear() }
                    agent.working = true;
                    agent.last_beat = Some(Instant::now());
                    agent.active_at = now;
                    if ty == "turn_started" { agent.unread = false; agent.errored = false }
                    let text = |k: &str| payload.get(k).and_then(Value::as_str).unwrap_or("");
                    // What it was asked (the turn's message; not a replay of an old one).
                    if ty == "turn_started" { if let Some(l) = fleet::first_line(text("userMessage")) { agent.asked = Some(l) } }
                    // The main agent's own steps (a sub-agent's carry the tool call that spawned it).
                    let own = payload.get("parentToolUseId").map(Value::is_null).unwrap_or(true);
                    let input = payload.get("input").unwrap_or(&Value::Null);
                    // Its plan, and the sub-agents it starts and that end.
                    if ty == "tool_start" && own && text("tool") == "TodoWrite" { agent.todos = fleet::todos_of(input) }
                    if ty == "tool_start" && own && matches!(text("tool"), "Task" | "Agent") {
                        let what = input.get("description").and_then(Value::as_str).unwrap_or("an agent").to_string();
                        agent.subagents.push((text("id").to_string(), what));
                    }
                    if ty == "tool_end" { let id = text("id").to_string(); agent.subagents.retain(|(s, _)| *s != id) }
                    match ty {
                        // What it does now; the text before a tool call is not its final message.
                        "tool_start" if own => { agent.doing = Some(fleet::describe_tool(text("tool"), input)); agent.said.clear() }
                        "thinking_title" => { let t = text("title").trim(); if !t.is_empty() { agent.doing = Some(t.chars().take(160).collect()) } }
                        "text_delta" if own && agent.said.len() < 2000 => agent.said.push_str(text("content")),
                        _ => {}
                    }
                }
            }
            "turn_ended" => {
                let visible = self.visible_agents();
                let looking = self.focused().filter(|_| self.terminal_focused).and_then(|f| self.panes.get(&f)).map(|p| (p.machine_id.clone(), p.agent_id.clone()));
                let opened: Vec<(String, String)> = self.panes.values().map(|p| (p.machine_id.clone(), p.agent_id.clone())).collect();
                let flag = |k: &str| payload.get(k).and_then(Value::as_bool).unwrap_or(false);
                let (replay, subagent) = (flag("replay"), flag("subagent"));
                let aborted = payload.get("aborted").and_then(Value::as_bool).unwrap_or(false);
                if let Some(agent) = self.fleet.event_agent(machine_id, &payload) {
                    agent.working = false;
                    if !subagent { agent.subagents.clear() }
                    agent.active_at = fleet::now_ms();
                    agent.since = agent.active_at;
                    agent.doing = None;
                    // What the turn came to: the first line of its final message.
                    let said = std::mem::take(&mut agent.said);
                    if !said.trim().is_empty() && !aborted { agent.last_text = said.trim().to_string() }
                    if aborted { agent.did = Some("Interrupted".into()) } else if agent.errored { } else if let Some(line) = fleet::first_line(&said) { agent.did = Some(line) }
                    let name = agent.name.clone();
                    let mine = opened.contains(&agent.key());
                    // tim hatches on the first turn finished while you watch, and is pleased after each.
                    if mine { self.tim.turn_done() }
                    // Done and not yet read — any harness's turn (not a re-read, not a sub-agent's)
                    // that ended where you were not looking: the focused pane, with the terminal
                    // focused. A visible pane beside the one you type in is not being read.
                    let key = agent.key();
                    if !replay && !subagent && looking.as_ref() != Some(&key) {
                        agent.unread = true;
                        if mine && !visible.contains(&key) { self.say(format!("{name} finished"), theme::ONLINE) }
                    } else if looking.as_ref() == Some(&key) { self.mark_seen_key(key) }
                    if mine && !self.terminal_focused && !replay && !subagent { crate::notify("Harness", &format!("{name} finished")) }
                }
            }
            "done" => {
                // The turn's result, where the engine gives one: what it came to.
                if let Some(agent) = self.fleet.event_agent(machine_id, &payload) {
                    if let Some(line) = payload.get("result").and_then(Value::as_str).and_then(fleet::first_line) { agent.did = Some(line) }
                }
            }
            // What was typed to it (from any window): what it was asked.
            "user_message" => {
                if let Some(agent) = self.fleet.event_agent(machine_id, &payload) {
                    if let Some(l) = payload.get("content").and_then(Value::as_str).and_then(fleet::first_line) { agent.asked = Some(l) }
                }
            }
            // The daemon's recap of a finished turn ("recap\n\nbody"): what it came to, better said
            // than its last message's first line.
            "turn_summary" => {
                if let Some(agent) = self.fleet.event_agent(machine_id, &payload) {
                    if let Some(l) = payload.get("summary").and_then(Value::as_str).and_then(fleet::first_line) { agent.did = Some(l) }
                }
            }
            // A failure the engine or the daemon reports (a message not delivered, an abort).
            "error" => {
                if let Some(agent) = self.fleet.event_agent(machine_id, &payload) {
                    if let Some(l) = payload.get("message").and_then(Value::as_str).and_then(fleet::first_line) { agent.did = Some(format!("Error: {l}")) }
                    agent.errored = true;
                }
            }
            "commander_question" => {
                let visible = self.visible_agents();
                if let Some(agent) = self.fleet.event_agent(machine_id, &payload) {
                    let next = fleet::question_from(&payload, agent.question.as_ref());
                    let fresh = next.as_ref().map(|q| agent.question.as_ref().map(|p| p.request_id != q.request_id).unwrap_or(true)).unwrap_or(false);
                    if next.is_some() { agent.question = next }
                    let name = agent.name.clone();
                    let prompt = agent.question.as_ref().map(|q| q.prompt.clone()).unwrap_or_default();
                    if fresh && !visible.contains(&agent.key()) {
                        { let k = self.keymap.hint("choose-tree -a").unwrap_or_default(); self.say(format!("{name} is waiting on you — {k}"), theme::ATTENTION); self.toast_hold = Some(4000) }
                        crate::bell();
                    }
                    if fresh && !self.terminal_focused { crate::notify(&format!("{name} needs input"), &prompt) }
                }
            }
            "commander_question_close" => {
                if let Some(agent) = self.fleet.event_agent(machine_id, &payload) { agent.question = None }
            }
            "machines_changed" => self.refresh_machines(),
            "desk_changed" => {
                let revision = payload.get("revision").and_then(Value::as_i64).unwrap_or(i64::MAX);
                if revision > self.desk_revision && self.desk_mode != DeskMode::Off { self.fetch_desk() }
            }
            "terminal_closed" => {
                let stream = payload.get("streamId").and_then(Value::as_str).and_then(|s| Uuid::parse_str(s).ok());
                let Some(pane) = self.panes.values_mut().find(|p| p.stream.is_some() && p.stream == stream) else { return };
                pane.stream = None;
                pane.dirty = true;
                if let Some(taken) = payload.get("takenBy") {
                    let who = taken.get("name").and_then(Value::as_str).unwrap_or("another window").to_string();
                    pane.phase = Phase::Watching(who);
                    // Still worth seeing: watch it until someone types here.
                    let id = pane.id;
                    self.open_stream(id, false);
                } else {
                    let id = pane.id;
                    self.after_end(id, payload.get("reason").and_then(Value::as_str).unwrap_or("the terminal closed").to_string());
                }
            }
            "terminal_error" => {
                let stream = payload.get("streamId").and_then(Value::as_str).and_then(|s| Uuid::parse_str(s).ok());
                if let Some(pane) = self.panes.values_mut().find(|p| p.stream.is_some() && p.stream == stream) {
                    if payload.get("code").and_then(Value::as_str) == Some("TERMINAL_INPUT_INVALID") {
                        if let Some(expected) = payload.get("expectedSeq").and_then(Value::as_u64) { pane.input_seq = expected }
                    }
                }
            }
            _ => {}
        }
    }

    fn on_terminal(&mut self, frame: proto::Frame) {
        let Some(pane) = self.panes.values_mut().find(|p| p.stream == Some(frame.stream)) else {
            // Hold it for a moment: its `terminal_ready` may still be on the way.
            if self.orphans.len() < 16 {
                let entry = self.orphans.entry(frame.stream).or_insert_with(|| (Instant::now(), Vec::new()));
                if entry.1.len() < 64 { entry.1.push(frame) }
            }
            return;
        };
        pane.last_seq = Some(pane.last_seq.map(|s| s.max(frame.seq)).unwrap_or(frame.seq));
        pane.ack_due = true;
        if frame.kind == Kind::Sync { return }
        let bytes = if frame.compressed { match pane::inflate(&frame.bytes) { Some(b) => b, None => return } } else { frame.bytes };
        if let Ok(path) = std::env::var("HARNESS_TUI_TRACE") {
            use std::io::Write;
            if let Ok(mut f) = std::fs::OpenOptions::new().create(true).append(true).open(path) {
                let _ = writeln!(f, "{} {:?} {}", if frame.kind == Kind::Keyframe { "K" } else { "O" }, frame.size, bytes.escape_ascii());
            }
        }
        if frame.kind == Kind::Keyframe {
            let (cols, rows) = frame.size.unwrap_or((pane.cols, pane.rows));
            pane.keyframe(cols, rows, &bytes);
            if matches!(pane.phase, Phase::Connecting(_)) { pane.phase = if pane.read_only { Phase::Watching(String::new()) } else { Phase::Live } }
        } else {
            pane.note_echo();
            if let Some(out) = self.pipes.get(&pane.id).and_then(|p| p.out.as_ref()) { let _ = out.send(bytes.clone()); }
            pane.feed(&bytes);
            pane.settle_predictions();
            let belled = std::mem::replace(&mut pane.bell, false);
            let copied = std::mem::take(&mut pane.copied);
            let id = pane.id;
            // set-clipboard (input.c's OSC 52): external passes it to the terminal's clipboard,
            // on a paste buffer too, off neither.
            for text in copied {
                let how = self.options.get("set-clipboard", "", None).unwrap_or_default();
                if how == "off" { continue }
                crate::clipboard::store(&text);
                if how == "on" { let limit = self.buffer_limit(); self.paste.add(text, limit) }
            }
            // alerts.c: output is activity; a BEL is a bell.
            if let Some(t) = self.tabs.iter().position(|t| t.panes().contains(&id)) {
                self.tabs[t].touch();
                // alerts_check_all: the bell first, then the activity.
                if belled { self.alert(t, BELL) }
                self.alert(t, ACTIVITY);
            }
        }
    }

    /// Acks and heartbeats for every live stream — batched once per loop turn.
    pub fn flush_acks(&mut self) {
        let now = Instant::now();
        let mut sends: Vec<(String, &'static str, Value)> = Vec::new();
        for pane in self.panes.values_mut() {
            let Some(stream) = pane.stream else { continue };
            if pane.ack_due {
                pane.ack_due = false;
                if let Some(seq) = pane.last_seq { sends.push((pane.machine_id.clone(), "terminal_ack", json!({ "streamId": stream.to_string(), "lastSeq": seq }))) }
            }
            if now.duration_since(pane.last_alive) > Duration::from_secs(10) {
                pane.last_alive = now;
                sends.push((pane.machine_id.clone(), "terminal_alive", json!({ "streamId": stream.to_string() })));
            }
        }
        for (machine, ty, payload) in sends {
            if let Some(link) = self.link(&machine) { link.send(ty, payload); }
        }
    }

    // ── streams ─────────────────────────────────────────────────────────────

    /// Open (or re-open) a pane's terminal. [takeover]: take the keyboard from any other window.
    pub fn open_stream(&mut self, pane_id: u64, takeover: bool) {
        let content = self.content_size(pane_id);
        // A harness whose start failed has no terminal: its pane says why (the daemon's words)
        // and what to do.
        let failed = self.panes.get(&pane_id).and_then(|p| self.fleet.agent(&p.machine_id, &p.agent_id)).filter(|a| a.launch == "failed").map(|a| a.launch_error.clone());
        if let Some(why) = failed {
            let restart = self.keymap.hint("confirm-before -p \"restart #T? (y/n)\" restart-harness").unwrap_or_else(|| "C-b R".into());
            let close = self.keymap.hint("confirm-before -p \"kill-pane #P? (y/n)\" kill-pane").unwrap_or_else(|| "C-b x".into());
            if let Some(pane) = self.panes.get_mut(&pane_id) {
                pane.phase = Phase::Card { title: "Failed to start".into(), detail: if why.is_empty() { "The daemon did not say why.".into() } else { why }, keys: vec![(restart, "restart".into()), (close, "close pane".into())] };
                pane.dirty = true;
            }
            return;
        }
        let Some(pane) = self.panes.get_mut(&pane_id) else { return };
        if pane.opening { return }
        let Some(link) = self.links.get(&pane.machine_id).and_then(|s| s.link.clone()) else {
            pane.phase = Phase::Connecting("Connecting…".into());
            return;
        };
        let (cols, rows) = content.unwrap_or((pane.cols, pane.rows));
        // Below the daemon's 40×12 the far terminal stays 40×12 and the tile shows the part of it
        // around the cursor, as tmux shows a window bigger than its client.
        let (cols, rows) = pane::stream_size(cols, rows);
        pane.opening = true;
        pane.want = (cols, rows);
        if !matches!(pane.phase, Phase::Watching(_)) || takeover { pane.phase = Phase::Connecting(if takeover { "Taking over…".into() } else { "Opening…".into() }) }
        let old = pane.stream.take();
        if let Some(old) = old { link.send("terminal_close", json!({ "streamId": old.to_string() })); }
        let agent_id = pane.agent_id.clone();
        let machine_id = pane.machine_id.clone();
        // Replies from an earlier open (a socket that has since dropped, a pane re-opened) are
        // recognised by this token and not allowed to overwrite the current state.
        pane.open_token += 1;
        let token = pane.open_token;
        let host = hostname();
        self.spawn(async move {
            link.request("terminal_open", json!({
                "protocolVersion": 3,
                "agentId": agent_id,
                "cols": cols,
                "rows": rows,
                "compression": ["zlib", "none"],
                "client": { "kind": "tui", "name": format!("{host} terminal") },
                "takeover": takeover,
            }), Duration::from_secs(45)).await
        }, move |app, reply| app.opened(pane_id, &machine_id, token, (cols, rows), reply));
    }

    fn opened(&mut self, pane_id: u64, machine_id: &str, token: u64, asked: (u16, u16), reply: Result<(String, Value), RpcError>) {
        let stream = reply.as_ref().ok().filter(|(ty, _)| ty == "terminal_ready").and_then(|(_, p)| p.get("streamId").and_then(Value::as_str)).and_then(|s| Uuid::parse_str(s).ok());
        let current = self.panes.get(&pane_id).map(|p| p.open_token == token).unwrap_or(false);
        if !current {
            // The pane went away (or opened again) while this was in flight: give the terminal back,
            // or this window would hold its keyboard lease with nothing on screen.
            if let (Some(stream), Some(link)) = (stream, self.links.get(machine_id).and_then(|s| s.link.clone())) {
                link.send("terminal_close", json!({ "streamId": stream.to_string() }));
            }
            return;
        }
        let Some(pane) = self.panes.get_mut(&pane_id) else { return };
        pane.opening = false;
        match reply {
            Ok((ty, payload)) if ty == "terminal_ready" => {
                pane.stream = stream;
                pane.read_only = payload.get("readOnly").and_then(Value::as_bool).unwrap_or(false);
                pane.input_seq = 0;
                pane.resize_seq = 0;
                pane.last_seq = None;
                pane.last_alive = Instant::now();
                pane.phase = if pane.read_only {
                    Phase::Watching(payload.get("heldBy").and_then(|h| h.get("name")).and_then(Value::as_str).unwrap_or("another window").to_string())
                } else { Phase::Live };
                let queued = std::mem::take(&mut pane.queued);
                let read_only = pane.read_only;
                // The tile changed size while this was opening: tell the far pane now.
                if !read_only && pane.want != asked {
                    pane.resize_seq += 1;
                    let (seq, want) = (pane.resize_seq, pane.want);
                    if let (Some(stream), Some(link)) = (stream, self.links.get(machine_id).and_then(|s| s.link.clone())) {
                        link.send("terminal_resize", json!({ "streamId": stream.to_string(), "resizeSeq": seq, "cols": want.0, "rows": want.1 }));
                    }
                }
                // Frames that raced ahead of this reply (the keyframe, often) are applied now.
                if let Some(stream) = stream {
                    for frame in self.orphans.remove(&stream).map(|(_, f)| f).unwrap_or_default() { self.on_terminal(frame) }
                }
                if !read_only { for bytes in queued { self.send_input(pane_id, &bytes) } }
                // What it runs, asked now rather than at the next two-second look: a shell's window
                // is named for it (automatic-rename) from the start, as tmux names it.
                self.refresh_pane_info(pane_id);
            }
            Ok((_, payload)) => {
                let code = payload.get("code").and_then(Value::as_str).unwrap_or("TERMINAL_OPEN_FAILED").to_string();
                if code == "TERMINAL_AGENT_NOT_FOUND" || code == "TERMINAL_RUNTIME_UNAVAILABLE" {
                    self.after_end(pane_id, code);
                } else {
                    pane.phase = Phase::Card { title: "Could not open the terminal".into(), detail: code, keys: vec![("enter".into(), "retry".into()), (self.keymap.hint("confirm-before -p \"kill-pane #P? (y/n)\" kill-pane").unwrap_or_else(|| "C-b x".into()), "close pane".into())] };
                }
            }
            Err(error) => {
                pane.phase = Phase::Card { title: "Could not open the terminal".into(), detail: error.to_string(), keys: vec![("enter".into(), "retry".into()), (self.keymap.hint("confirm-before -p \"kill-pane #P? (y/n)\" kill-pane").unwrap_or_else(|| "C-b x".into()), "close pane".into())] };
            }
        }
        if let Some(pane) = self.panes.get_mut(&pane_id) { pane.dirty = true }
    }

    /// The stream ended with nobody taking it: say why, from the agent's state.
    fn after_end(&mut self, pane_id: u64, reason: String) {
        // A popup's program that exits closes the popup (display-popup -E).
        if matches!(self.modal, Some(crate::modal::Modal::Popup { pane, .. }) if pane == pane_id) { self.close_popup(); return }
        // A split's shell that exits takes its pane with it, as in tmux.
        if let Some(key) = self.panes.get(&pane_id).map(|p| (p.machine_id.clone(), p.agent_id.clone())) {
            if self.shells.contains(&key) { self.shells.remove(&key); self.close_pane(pane_id); return }
        }
        let Some(pane) = self.panes.get_mut(&pane_id) else { return };
        let agent = self.fleet.agent(&pane.machine_id, &pane.agent_id);
        pane.stream = None;
        pane.phase = match agent.map(|a| a.status.as_str()) {
            Some("stopped") => Phase::Card { title: "Paused".into(), detail: "The conversation is saved.".into(), keys: vec![("enter".into(), "resume".into()), (self.keymap.hint("choose-tree -s").unwrap_or_default(), "open another".into()), (self.keymap.hint("confirm-before -p \"kill-pane #P? (y/n)\" kill-pane").unwrap_or_else(|| "C-b x".into()), "close pane".into())] },
            None => Phase::Card { title: "This harness is gone".into(), detail: "It is no longer on its machine.".into(), keys: vec![(self.keymap.hint("choose-tree -s").unwrap_or_default(), "open another".into()), (self.keymap.hint("confirm-before -p \"kill-pane #P? (y/n)\" kill-pane").unwrap_or_else(|| "C-b x".into()), "close pane".into())] },
            _ if agent.map(|a| a.launch == "starting").unwrap_or(false) => Phase::Connecting("Starting…".into()),
            _ => Phase::Card { title: "The terminal closed".into(), detail: reason, keys: vec![("enter".into(), "reopen".into()), (self.keymap.hint("confirm-before -p \"restart #T? (y/n)\" restart-harness").unwrap_or_else(|| "C-b R".into()), "restart".into()), (self.keymap.hint("confirm-before -p \"kill-pane #P? (y/n)\" kill-pane").unwrap_or_else(|| "C-b x".into()), "close pane".into())] },
        };
        pane.dirty = true;
        // A harness that is still starting will have a terminal in a moment.
        if matches!(pane.phase, Phase::Connecting(_)) {
            let sink = self.sink.clone();
            tokio::spawn(async move {
                tokio::time::sleep(Duration::from_millis(1200)).await;
                let _ = sink.send(Event::Apply(Box::new(move |app: &mut App| app.open_stream(pane_id, true))));
            });
        }
    }

    pub fn resume(&mut self, pane_id: u64) {
        let Some(pane) = self.panes.get_mut(&pane_id) else { return };
        let Some(link) = self.links.get(&pane.machine_id).and_then(|s| s.link.clone()) else { return };
        pane.phase = Phase::Connecting("Resuming the conversation…".into());
        let agent_id = pane.agent_id.clone();
        let machine_id = pane.machine_id.clone();
        let close_key = self.keymap.hint("confirm-before -p \"kill-pane #P? (y/n)\" kill-pane").unwrap_or_else(|| "C-b x".into());
        self.spawn(async move { link.rpc("agent_resume", json!({ "agentId": agent_id }), Duration::from_secs(120)).await }, move |app, reply| match reply {
            Ok(_) => { app.relist(&machine_id); app.open_stream(pane_id, true) }
            Err(error) => {
                if let Some(pane) = app.panes.get_mut(&pane_id) {
                    pane.phase = Phase::Card { title: "Could not resume".into(), detail: error.to_string(), keys: vec![("enter".into(), "try again".into()), (close_key, "close pane".into())] };
                }
            }
        });
    }

    pub fn send_input(&mut self, pane_id: u64, bytes: &[u8]) {
        let Some(pane) = self.panes.get_mut(&pane_id) else { return };
        let Some(stream) = pane.stream else { return };
        // select-pane -d: input to this pane is off until select-pane -e.
        if pane.read_only || pane.input_off { return }
        let Some(link) = self.links.get(&pane.machine_id).and_then(|s| s.link.clone()) else { return };
        pane.scroll_bottom();
        if pane.input_at.is_none() { pane.input_at = Some(Instant::now()) }
        for chunk in bytes.chunks(8 * 1024) {
            link.send_binary(proto::encode(Kind::Input, stream, pane.input_seq, chunk));
            pane.input_seq += 1;
        }
    }

    pub fn send_paste(&mut self, pane_id: u64, text: &str) {
        let Some(pane) = self.panes.get(&pane_id) else { return };
        let Some(stream) = pane.stream else { return };
        if pane.input_off { return }
        let Some(link) = self.links.get(&pane.machine_id).and_then(|s| s.link.clone()) else { return };
        link.send_binary(proto::encode(Kind::Paste, stream, 0, text.as_bytes()));
    }

    /// Resize every visible pane's far terminal to its tile. Called after any layout change.
    pub fn fit_panes(&mut self) {
        // Every window's cells follow the client's size (tmux resizes its windows to it), with the
        // title rows counted when the window shows them.
        let body = self.body();
        for i in 0..self.tabs.len() {
            let status = self.pane_status(&self.tabs[i]);
            if let Some(root) = self.tabs[i].root.as_mut() {
                root.status = status;
                if root.size() != (body.width, body.height) { root.resize(body.width, body.height) }
            }
        }
        self.rects = self.compute_rects();
        let visible: Vec<(u64, Rect)> = self.rects.clone();
        // A tile comes on screen without a stream (a desk tab never visited): open it as a watcher —
        // whoever has the keyboard elsewhere keeps it until someone types here.
        let idle: Vec<u64> = visible.iter().map(|(id, _)| *id).filter(|id| self.panes.get(id).map(|p| p.stream.is_none() && !p.opening && matches!(p.phase, Phase::Connecting(_))).unwrap_or(false)).collect();
        for (id, rect) in visible {
            let content = self.content_of(self.tab(), rect);
            let content = (content.width, content.height);
            if self.panes.get(&id).map(|p| !p.modes.is_empty()).unwrap_or(false) { crate::copy::fit(self, id, content.0 as u32, content.1 as u32) }
            let Some(pane) = self.panes.get_mut(&id) else { continue };
            pane.dirty = true;
            let want = pane::stream_size(content.0, content.1);
            if pane.want == want { continue }
            pane.want = want;
            let Some(stream) = pane.stream else { continue };
            if pane.read_only { continue }
            pane.resize_seq += 1;
            let seq = pane.resize_seq;
            if let Some(link) = self.links.get(&pane.machine_id).and_then(|s| s.link.clone()) {
                link.send("terminal_resize", json!({ "streamId": stream.to_string(), "resizeSeq": seq, "cols": want.0, "rows": want.1 }));
            }
        }
        for id in idle { self.open_stream(id, false) }
        self.report_focus();
    }

    /// Tell the daemon which harness is in front of the person: its terminal gets the short (2ms)
    /// output window instead of 8ms. Local machine only — a relayed machine keeps its own.
    fn report_focus(&mut self) {
        // A headless client is in front of nobody.
        if self.headless { return }
        // The dial's ring before its focus: a focus the ring does not hold yet is dropped.
        crate::dial::announce(self, false);
        let Some(id) = self.focused() else { return };
        let Some(pane) = self.panes.get(&id) else { return };
        let key = (pane.machine_id.clone(), pane.agent_id.clone());
        if self.last_focus_sent.as_ref() == Some(&key) { return }
        if let Some(link) = self.link(&pane.machine_id) {
            if link.send("app_focus", json!({ "agentId": pane.agent_id })) { self.last_focus_sent = Some(key) }
        }
    }

    /// Say the active pane again, as when this terminal comes back to the front.
    pub fn announce_focus(&mut self) {
        self.last_focus_sent = None;
        self.report_focus();
    }

    // ── tabs & panes ─────────────────────────────────────────────────────────

    pub fn tab(&self) -> &Tab { &self.tabs[self.active] }

    /// The command a shell ran is done: what it printed, its errors and its exit status go back —
    /// or, for split-window/new-window -P, once the new pane is there.
    pub fn finish_cli(&mut self) {
        let out = self.capture.take().unwrap_or_default();
        let err = self.capture_err.take().unwrap_or_default();
        let Some(tx) = self.cli_tx.take() else { return };
        if self.print_new.is_some() && err.is_empty() { self.held_reply = Some(tx); return }
        self.print_new = None;
        let code = if self.cli_code != 0 { self.cli_code } else if err.is_empty() { 0 } else { 1 };
        if std::mem::take(&mut self.wait_cli) && self.waiting_open() { self.waiting_reply = Some((tx, (out, err, code))); return }
        let _ = tx.send((out, err, code));
    }

    fn waiting_open(&self) -> bool { matches!(self.modal, Some(Modal::Menu(_)) | Some(Modal::Prompt(_)) | Some(Modal::Confirm { .. })) }

    /// The menu or prompt a shell's command opened has closed: the shell has its answer.
    pub fn release_waiting(&mut self) {
        if self.waiting_reply.is_some() && !self.waiting_open() {
            if let Some((tx, reply)) = self.waiting_reply.take() { let _ = tx.send(reply); }
        }
    }

    /// Data printed as it is (show-buffer): to a shell exactly, its last line without a newline
    /// when it has none; else shown as print shows lines.
    pub fn print_data(&mut self, title: &str, data: &str) {
        let mut lines: Vec<String> = data.split('\n').map(str::to_string).collect();
        if data.ends_with('\n') { lines.pop(); } else if self.capture.is_some() { if let Some(l) = lines.last_mut() { l.push(BARE) } }
        self.print(title, lines)
    }

    /// What a command prints: to the shell that asked (hn <command>), else into the current pane's
    /// view mode as tmux shows it (server_client_print) — with no pane (a window with no harness
    /// yet), a message or a list.
    pub fn print(&mut self, title: &str, lines: Vec<String>) {
        if let Some(out) = self.capture.as_mut() { out.extend(lines); return }
        if lines.is_empty() || crate::copy::print(self, &lines, false) { return }
        if lines.len() <= 1 { self.say(lines.into_iter().next().unwrap_or_default(), crate::theme::WARN) }
        else { crate::input::picker(self, crate::modal::PickerKind::Output { title: title.to_string(), lines }, title, "") }
    }

    /// Ask the pane's machine what its tmux pane runs and where (terminal_info) — for this
    /// machine's panes; a daemon that predates it, or a peer, just leaves the fallbacks.
    pub fn refresh_pane_info(&mut self, pane_id: u64) {
        let Some(p) = self.panes.get(&pane_id) else { return };
        if p.machine_id != self.fleet.local_id || p.stream.is_none() { return }
        let (machine, agent) = (p.machine_id.clone(), p.agent_id.clone());
        let Some(link) = self.link(&machine) else { return };
        self.spawn(async move { link.rpc("terminal_info", json!({ "agentId": agent }), Duration::from_secs(3)).await }, move |app, reply| {
            let Ok(info) = reply else { return };
            if info.get("error").is_some() { return }
            let Some(p) = app.panes.get_mut(&pane_id) else { return };
            let text = |k: &str| info.get(k).and_then(Value::as_str).filter(|s| !s.is_empty()).map(str::to_string);
            p.fg_command = text("command");
            p.live_path = text("path");
            p.remote_pid = info.get("pid").and_then(Value::as_u64);
            p.remote_tty = text("tty");
            // automatic-rename follows what runs, at once.
            app.sync_titles();
        });
    }

    /// Close the popup and end its shell.
    pub fn close_popup(&mut self) {
        let Some(crate::modal::Modal::Popup { pane, .. }) = self.modal.take() else { return };
        let key = self.panes.get(&pane).map(|p| (p.machine_id.clone(), p.agent_id.clone()));
        self.drop_pane(pane);
        if let Some((m, a)) = key {
            self.shells.remove(&(m.clone(), a.clone()));
            if let Some(link) = self.link(&m) { self.spawn(async move { link.rpc("agent_delete", json!({ "agentId": a }), Duration::from_secs(30)).await }, |_, _| {}) }
        }
        self.redraw_all = true;
    }

    /// What a tmux.conf (or `set`, `source-file`) said, over what is set now.
    pub fn apply_settings(&mut self, s: &crate::tmuxconf::Settings) {
        if let Some(n) = s.base_index { self.base_index = n }
        if let Some(m) = s.mouse { self.mouse = m; self.mouse_changed = true }
        if let Some(t) = s.status_top { self.status_top = t; self.fit_panes() }
        if let Some(ms) = s.display_ms { self.display_ms = ms.max(300) }
        if let Some(ms) = s.display_panes_ms { self.display_panes_ms = ms }
        let (l, n) = (&mut self.look, &s.look);
        for (to, from) in [(&mut l.status_bg, n.status_bg), (&mut l.status_fg, n.status_fg), (&mut l.message_bg, n.message_bg), (&mut l.message_fg, n.message_fg),
            (&mut l.active_border, n.active_border), (&mut l.border, n.border), (&mut l.window_fg, n.window_fg), (&mut l.window_bg, n.window_bg),
            (&mut l.active_window_fg, n.active_window_fg), (&mut l.active_window_bg, n.active_window_bg)] {
            if from.is_some() { *to = from }
        }
        for (k, v) in &s.options.user { self.opts.user.insert(k.clone(), v.clone()); }
        // What tmux.conf set, into the options as tmux keeps them.
        let (to, from) = (&mut self.options, &s.options.store);
        for (a, b) in [(&mut to.server, &from.server), (&mut to.global_session, &from.global_session), (&mut to.global_window, &from.global_window), (&mut to.session, &from.session)] {
            for (k, v) in b { a.insert(k.clone(), v.clone()); }
        }
        let (o, n) = (&mut self.opts, &s.options);
        macro_rules! take { ($($f:ident),*) => { $( if n.$f.is_some() { o.$f = n.$f.clone() } )* } }
        if let Some(off) = s.options.tim_off { self.tim.off = off }
        take!(status_left, status_right, status_left_length, status_right_length, window_status_format, window_status_current_format,
            window_status_current_style, window_status_separator, renumber_windows, border_titles, mode_keys_emacs, status, status_justify, window_status_style, pane_border_format, main_pane_width, main_pane_height, copy_command, status_keys_vi);
        self.fit_panes();
        self.redraw_all = true;
    }

    /// swap-window: the two windows trade places and indexes; this one stays current.
    pub fn swap_tabs(&mut self, a: usize, b: usize) {
        if a == b || b >= self.tabs.len() { return }
        self.renumber();
        let (ia, ib) = (self.tabs[a].id.clone(), self.tabs[b].id.clone());
        let (na, nb) = (self.win_num(a), self.win_num(b));
        self.nums.insert(ia.clone(), nb);
        self.nums.insert(ib.clone(), na);
        let (lo, hi) = (a.min(b), a.max(b));
        self.active = lo;
        while self.active < hi { self.move_tab(1) }
        self.active = hi - 1;
        while self.active > lo { self.move_tab(-1) }
        self.active = self.tabs.iter().position(|t| t.id == ia).unwrap_or(self.active);
        self.fit_panes();
    }

    /// tmux's #S: this computer's name, as the status line's `[…]` shows it.
    pub fn session_name(&self) -> String {
        if let Some(a) = &self.session_alias { return a.clone() }
        self.machine_session_name()
    }

    /// The desk's session, named as this computer is.
    fn machine_session_name(&self) -> String {
        self.fleet.machine(&self.fleet.local_id).map(|m| m.name.clone()).unwrap_or_else(hostname)
    }

    fn stash_name(&self, s: &Stash) -> String { s.alias.clone().unwrap_or_else(|| self.machine_session_name()) }

    // ── sessions ────────────────────────────────────────────────────────────────

    fn stash_current(&mut self) -> Stash {
        let activity = self.session_activity;
        Stash {
            id: self.session_id, alias: self.session_alias.take(), desk: self.session_desk,
            tabs: std::mem::take(&mut self.tabs), active: self.active, lastw: std::mem::take(&mut self.lastw), nums: std::mem::take(&mut self.nums),
            created: self.session_created, activity, options: std::mem::take(&mut self.options.session), env: std::mem::take(&mut self.session_env),
        }
    }

    fn unstash(&mut self, s: Stash) {
        self.session_id = s.id;
        self.session_alias = s.alias;
        self.session_desk = s.desk;
        self.tabs = s.tabs;
        if self.tabs.is_empty() { self.tabs.push(Tab::new("home")) }
        self.active = s.active.min(self.tabs.len() - 1);
        self.lastw = s.lastw;
        self.nums = s.nums;
        self.session_created = s.created;
        self.session_activity = s.activity;
        self.options.session = s.options;
        self.session_env = s.env;
    }

    /// Session [id] in front, as it is, with nothing else done (a command that names it runs
    /// there); false if there is none. One no client has (its client detached) is this client's
    /// from now on.
    pub fn swap_session(&mut self, id: u32) -> bool {
        if id == self.session_id { return true }
        if !self.sessions.iter().any(|s| s.id == id) && !self.take_session(id, false) { return false }
        let Some(i) = self.sessions.iter().position(|s| s.id == id) else { return false };
        let next = self.sessions.remove(i);
        let cur = self.stash_current();
        self.sessions.push(cur);
        self.unstash(next);
        true
    }

    /// switch-client (server_client_set_session): the client shows session [id] at its current
    /// window, whose alerts are seen; the one it leaves is its last session. Another client's is
    /// given up by that client first.
    pub fn switch_session(&mut self, id: u32) {
        if id == self.session_id { return }
        if !self.sessions.iter().any(|s| s.id == id) && !self.take_session(id, true) { return }
        let from = self.session_id;
        // The session the client leaves was in use until now (session_update_activity).
        let used = std::mem::replace(&mut self.session_activity, epoch_secs());
        if !self.swap_session(id) { self.session_activity = used; return }
        self.last_session = Some(from);
        // A session left with no window (the one a client started in, before its shell came):
        // gone, as tmux has no session without a window.
        if let Some(i) = self.sessions.iter().position(|s| s.id == from && !s.desk && s.tabs.iter().all(|t| t.root.is_none())) {
            self.sessions.remove(i);
            self.last_session = None;
        }
        let a = self.active;
        self.tabs[a].alerts = 0;
        if let Some(f) = self.tabs[a].focus { self.seen(f) }
        self.home_order.borrow_mut().clear();
        self.fit_panes();
        self.redraw_all = true;
        self.save_sessions();
    }

    /// A new session id (`$N`), as tmux's next_session_id: never given twice by this client.
    pub fn alloc_session_id(&self) -> u32 {
        let id = self.next_session_id.get();
        self.next_session_id.set(id + 1);
        id
    }

    /// The id this client gives a session it does not have (the same each time it is asked).
    fn remote_id(&self, name: &str) -> u32 {
        if let Some(id) = self.remote.borrow().ids.get(name) { return *id }
        let id = self.alloc_session_id();
        self.remote.borrow_mut().ids.insert(name.to_string(), id);
        id
    }

    /// One of this client's own sessions, by its exact name.
    pub fn own_session(&self, name: &str) -> Option<u32> {
        if self.session_name() == name { return Some(self.session_id) }
        self.sessions.iter().find(|s| self.stash_name(s) == name).map(|s| s.id)
    }

    /// The sessions this client does not have — other clients' and those no client has — as the
    /// sessions file says: read again when it changes, and its clients asked after again when
    /// that is two seconds old.
    pub fn remote_rows(&self) -> Vec<RemoteSession> {
        let path = Self::sessions_path();
        let stamp = std::fs::metadata(&path).ok().map(|m| (m.modified().unwrap_or(std::time::UNIX_EPOCH), m.len()));
        let stale = {
            let r = self.remote.borrow();
            r.stamp != stamp || stamp.is_none() || r.read_at.map(|t| t.elapsed() > Duration::from_secs(2)).unwrap_or(true)
        };
        if stale {
            let me = crate::ipc::here().map(|p| p.display().to_string());
            let doc = read_sessions(&path);
            let mut rows = Vec::new();
            for row in doc["sessions"].as_array().cloned().unwrap_or_default() {
                if row.get("desk").and_then(Value::as_bool).unwrap_or(false) { continue }
                let Some(name) = row.get("name").and_then(Value::as_str).map(str::to_string) else { continue };
                if me.is_some() && row.get("owner").and_then(Value::as_str) == me.as_deref() { continue }
                let owner = live_owner(&row);
                let windows = row.get("windows").and_then(Value::as_array).map(|ws| ws.iter().map(|w| (
                    w.get("num").and_then(Value::as_u64).unwrap_or(0) as usize,
                    w.get("name").and_then(Value::as_str).unwrap_or("").to_string(),
                    w.get("panes").and_then(Value::as_array).map(|p| p.len()).unwrap_or(0),
                )).collect()).unwrap_or_default();
                let created = row.get("created").and_then(Value::as_i64).unwrap_or(0);
                rows.push(RemoteSession {
                    id: self.remote_id(&name), front: owner.is_some() && row.get("front").and_then(Value::as_bool).unwrap_or(false), owner, name, created,
                    activity: row.get("activity").and_then(Value::as_i64).unwrap_or(created), active: row.get("active").and_then(Value::as_u64).unwrap_or(0) as usize, windows,
                });
            }
            let mut r = self.remote.borrow_mut();
            r.rows = rows;
            r.stamp = stamp;
            r.read_at = Some(Instant::now());
        }
        let mine: Vec<String> = std::iter::once(self.session_name()).chain(self.sessions.iter().map(|s| self.stash_name(s))).collect();
        self.remote.borrow().rows.iter().filter(|s| !mine.contains(&s.name)).cloned().collect()
    }

    /// The client that has session [id], when another client has it: the socket it listens on.
    pub fn remote_owner(&self, id: u32) -> Option<String> {
        if id == self.session_id || self.sessions.iter().any(|s| s.id == id) { return None }
        self.remote_rows().into_iter().find(|r| r.id == id).and_then(|r| r.owner)
    }

    /// A session this client does not have, made its own, as the file has it. One another client
    /// has ([from_client]) is given up by that client first — which detaches, as `attach -d`
    /// detaches a session's other clients, when it is the session it shows.
    pub fn take_session(&mut self, id: u32, from_client: bool) -> bool {
        let Some(r) = self.remote_rows().into_iter().find(|r| r.id == id) else { return false };
        if let Some(owner) = &r.owner {
            if !from_client { return false }
            let given = crate::ipc::ask(std::path::Path::new(owner), &["hn-release-session".into(), "-t".into(), r.name.clone()]);
            if !matches!(given, Some((_, _, 0))) { self.error(format!("session {} is another client's", r.name)); return false }
        }
        // Read and claimed while the file is held: two clients never both take it.
        let path = Self::sessions_path();
        let lock = crate::ipc::lock(&path);
        let doc = read_sessions(&path);
        let row = doc["sessions"].as_array().and_then(|rows| rows.iter().find(|row| row.get("name").and_then(Value::as_str) == Some(r.name.as_str())
            && !row.get("desk").and_then(Value::as_bool).unwrap_or(false) && live_owner(row).is_none()).cloned());
        let Some(stash) = row.and_then(|row| self.stash_from_row(&row, id)) else { drop(lock); self.error(format!("can't find session: {}", r.name)); return false };
        self.sessions.push(stash);
        self.write_sessions_held(Save::Stay);
        drop(lock);
        self.remote.borrow_mut().stamp = None;
        true
    }

    /// hn-release-session: session [name] given up to the client that asked (it goes there). The
    /// session this client shows: it detaches, every session it had left for the next client, as
    /// tmux's `attach -d` detaches the others.
    pub fn release_session(&mut self, name: &str) -> Result<(), String> {
        if !self.session_desk && self.session_name() == name {
            self.write_sessions(Save::Leave);
            self.handed_over = true;
            self.quit = true;
            return Ok(())
        }
        let Some(i) = self.sessions.iter().position(|s| !s.desk && self.stash_name(s) == name) else { return Err(format!("can't find session: {name}")) };
        let id = self.sessions[i].id;
        self.write_sessions(Save::Release(id));
        let gone = self.sessions.remove(i);
        for t in &gone.tabs { for p in t.panes() { self.drop_pane(p) } }
        let mut r = self.remote.borrow_mut();
        r.ids.insert(name.to_string(), id);
        r.stamp = None;
        Ok(())
    }

    /// A session's own formats, for a session not in front (a #{S:} loop's, list-sessions').
    pub fn stash_value(&self, id: u32, key: &str) -> Option<String> {
        let Some(s) = self.sessions.iter().find(|s| s.id == id) else {
            let r = self.remote_rows().into_iter().find(|r| r.id == id)?;
            return Some(match key {
                "session_name" => r.name.clone(),
                "session_id" => format!("${}", r.id),
                "session_windows" => r.windows.len().to_string(),
                // Attached: shown by its client.
                "session_attached" => (r.front as u8).to_string(),
                "session_many_attached" | "session_marked" | "session_alerts" => "0".into(),
                "session_created" | "session_last_attached" => r.created.to_string(),
                "session_activity" => r.activity.to_string(),
                "window_index" => r.windows.get(r.active).map(|w| w.0.to_string()).unwrap_or_default(),
                "window_name" => r.windows.get(r.active).map(|w| w.1.clone()).unwrap_or_default(),
                _ => return None,
            })
        };
        Some(match key {
            "session_name" => self.stash_name(s),
            "session_id" => format!("${}", s.id),
            "session_windows" => s.tabs.len().to_string(),
            "session_attached" | "session_many_attached" | "session_marked" | "session_alerts" => "0".into(),
            "session_created" | "session_last_attached" => s.created.to_string(),
            "session_activity" => s.activity.to_string(),
            "window_index" => s.tabs.get(s.active).and_then(|t| s.nums.get(&t.id)).map(|n| n.to_string()).unwrap_or_default(),
            "window_name" => s.tabs.get(s.active).map(|t| t.name.clone()).unwrap_or_default(),
            _ => return None,
        })
    }

    /// A session's windows (number, name, panes), whichever client has it.
    pub fn session_windows(&self, id: u32) -> Vec<(usize, String, usize)> {
        let of = |tabs: &[Tab], nums: &HashMap<String, usize>| tabs.iter().filter(|t| t.root.is_some()).map(|t| (nums.get(&t.id).copied().unwrap_or(0), t.name.clone(), t.panes().len())).collect();
        if id == self.session_id { return of(&self.tabs, &self.nums) }
        if let Some(s) = self.sessions.iter().find(|s| s.id == id) { return of(&s.tabs, &s.nums) }
        self.remote_rows().into_iter().find(|r| r.id == id).map(|r| r.windows).unwrap_or_default()
    }

    /// The harnesses open in a session's windows (this client's sessions), as fleet keys.
    pub fn session_harnesses(&self, id: u32) -> Vec<(String, String)> {
        let tabs: &[Tab] = if id == self.session_id { &self.tabs } else { match self.sessions.iter().find(|s| s.id == id) { Some(s) => &s.tabs, None => return Vec::new() } };
        tabs.iter().flat_map(|t| t.panes()).filter_map(|p| self.panes.get(&p).map(|x| (x.machine_id.clone(), x.agent_id.clone()))).collect()
    }

    /// Every session, (id, name), in tmux's order: by name — this client's and the others'.
    pub fn session_list(&self) -> Vec<(u32, String)> {
        let mut v: Vec<(u32, String)> = std::iter::once((self.session_id, self.session_name())).chain(self.sessions.iter().map(|s| (s.id, self.stash_name(s))))
            .chain(self.remote_rows().into_iter().map(|r| (r.id, r.name))).collect();
        v.sort_by(|a, b| a.1.cmp(&b.1));
        v
    }

    /// cmd_find_get_session: `$id`, the exact name, the only name it starts, or the only name it
    /// matches as a pattern (`=` first: the exact name only).
    pub fn find_session(&self, target: &str) -> Option<u32> {
        let (exact, t) = match target.strip_prefix('=') { Some(t) => (true, t), None => (false, target) };
        let all = self.session_list();
        if let Some(id) = t.strip_prefix('$') { return id.parse::<u32>().ok().filter(|id| all.iter().any(|(i, _)| i == id)) }
        if let Some((id, _)) = all.iter().find(|(_, n)| n == t) { return Some(*id) }
        if exact { return None }
        let starts: Vec<u32> = all.iter().filter(|(_, n)| n.starts_with(t)).map(|(i, _)| *i).collect();
        match starts.len() { 1 => return Some(starts[0]), 0 => {} _ => return None }
        let matched: Vec<u32> = all.iter().filter(|(_, n)| crate::cmd::fnmatch(t, n)).map(|(i, _)| *i).collect();
        if matched.len() == 1 { Some(matched[0]) } else { None }
    }

    /// session_next_session / session_previous_session: the one after (or before) this one by
    /// name, round to the first (or last); none when this is the only one.
    pub fn neighbour_session(&self, next: bool) -> Option<u32> {
        let all = self.session_list();
        let at = all.iter().position(|(i, _)| *i == self.session_id)?;
        let to = if next { (at + 1) % all.len() } else { (at + all.len() - 1) % all.len() };
        (to != at).then(|| all[to].0)
    }

    /// The session a pane (or a window, by its tab id) is in.
    pub fn session_of_pane(&self, pane: u64) -> Option<u32> {
        if self.tabs.iter().any(|t| t.panes().contains(&pane)) { return Some(self.session_id) }
        self.sessions.iter().find(|s| s.tabs.iter().any(|t| t.panes().contains(&pane))).map(|s| s.id)
    }

    pub fn session_of_window(&self, wid: u64) -> Option<u32> {
        if self.tabs.iter().any(|t| t.wid == wid) { return Some(self.session_id) }
        self.sessions.iter().find(|s| s.tabs.iter().any(|t| t.wid == wid)).map(|s| s.id)
    }

    /// session_create: a session [name] (else its number: its id, as tmux's) with one window — a
    /// shell (or [command]) in [cwd], named [window] (automatic-rename off) — made in the
    /// background ([detached]) or gone to.
    pub fn new_session(&mut self, name: Option<&str>, window: Option<&str>, cwd: Option<String>, command: Option<String>, detached: bool) -> Result<u32, String> {
        let (id, name) = match name {
            Some(n) => {
                let n = session_check_name(n).ok_or_else(|| "invalid session: ".to_string())?;
                if self.find_session(&format!("={n}")).is_some() { return Err(format!("duplicate session: {n}")) }
                (self.alloc_session_id(), n)
            }
            None => loop { let id = self.alloc_session_id(); if self.find_session(&format!("={id}")).is_none() { break (id, id.to_string()) } },
        };
        // Named as tmux names a new window, for what it runs (the shell), until automatic-rename.
        let shell = self.options.get("default-shell", "", None).filter(|s| !s.is_empty()).or_else(|| std::env::var("SHELL").ok()).unwrap_or_else(|| "sh".into());
        let program = command.as_deref().and_then(|c| c.split_whitespace().next()).unwrap_or(&shell).rsplit('/').next().unwrap_or("sh").to_string();
        let mut tab = Tab::new(window.unwrap_or(&program));
        if window.is_some() {
            tab.named = true;
            self.options.windows.entry(tab.id.clone()).or_default().insert("automatic-rename".into(), "off".into());
        }
        let tab_id = tab.id.clone();
        let base = self.base_index;
        let linked = (tab.wid, tab.name.clone());
        self.sessions.push(Stash { id, alias: Some(name.clone()), desk: false, tabs: vec![tab], active: 0, lastw: Vec::new(), nums: HashMap::from([(tab_id.clone(), base)]),
            created: epoch_secs(), activity: epoch_secs(), options: Default::default(), env: Default::default() });
        // cmd-new-session.c: its window linked (spawn_window), then the session created.
        crate::commands::notify_session(self, "window-linked", id, &name, Some(linked));
        crate::commands::notify_session(self, "session-created", id, &name, None);
        // Its shell, on this computer, into its window wherever that is by then.
        crate::input::new_shell_from(self, None, Placement::Fill(tab_id), cwd, command);
        // A headless client shows nothing: the newest session is the one a command with no -t
        // is for (cmd_find_best_session).
        if !detached || self.headless { self.switch_session(id) }
        self.save_sessions();
        Ok(id)
    }

    /// A session [name] with one empty window (its windows to come: a project's harnesses).
    pub fn empty_session(&mut self, name: &str) -> u32 {
        let id = self.alloc_session_id();
        let tab = Tab::new("home");
        let base = self.base_index;
        self.sessions.push(Stash { id, alias: Some(name.to_string()), desk: false, nums: HashMap::from([(tab.id.clone(), base)]), tabs: vec![tab], active: 0, lastw: Vec::new(),
            created: epoch_secs(), activity: epoch_secs(), options: Default::default(), env: Default::default() });
        crate::commands::notify_session(self, "session-created", id, name, None);
        id
    }

    /// Where the sessions are kept between clients (`hn` again after C-b d, or after the last
    /// window of the session in front went): one file per server name (-L).
    fn sessions_path() -> std::path::PathBuf { sessions_path(None) }

    pub fn save_sessions(&self) { self.write_sessions(Save::Stay) }

    /// Written again when its sessions' windows or panes changed: what other clients of this
    /// name list of this one's sessions (and take, when one is gone to) is how they stand.
    pub fn save_if_changed(&mut self) {
        if self.handed_over || self.start_failed.is_some() || self.quit { return }
        let mut sig = String::new();
        let mut add = |name: String, tabs: &[Tab], nums: &HashMap<String, usize>| {
            sig.push_str(&name);
            for t in tabs.iter().filter(|t| t.root.is_some()) { sig.push_str(&format!("|{}:{}:{}:{:?}", t.id, t.name, nums.get(&t.id).copied().unwrap_or(0), t.panes())) }
            sig.push('\n');
        };
        if !self.session_desk { add(self.session_name(), &self.tabs, &self.nums) }
        for s in self.sessions.iter().filter(|s| !s.desk) { add(self.stash_name(s), &s.tabs, &s.nums) }
        if sig != self.sessions_sig { self.sessions_sig = sig; self.save_sessions() }
    }

    /// Every session this client has as its windows stand — each window's name, number, layout
    /// and its panes' harnesses — marked as this client's (else left for the next, as [how]
    /// says), beside the other clients' sessions as they wrote them; the desk's name; and the
    /// session in front.
    pub fn write_sessions(&self, how: Save) {
        let path = Self::sessions_path();
        let _lock = crate::ipc::lock(&path);
        self.write_sessions_held(how)
    }

    /// write_sessions with the file's lock already held.
    fn write_sessions_held(&self, how: Save) {
        if self.handed_over || (self.capture.is_some() && self.tabs.is_empty()) { return }
        let window = |app: &App, t: &Tab, nums: &HashMap<String, usize>| {
            // A shell hn made is ended when its window is killed, by whichever client does it.
            let panes: Vec<Value> = t.panes().iter().filter_map(|p| app.panes.get(p)).map(|p| json!([p.machine_id, p.agent_id, app.shells.contains(&(p.machine_id.clone(), p.agent_id.clone()))])).collect();
            let focus = t.focus.and_then(|f| t.panes().iter().position(|p| *p == f)).unwrap_or(0);
            json!({ "name": t.name, "named": t.named, "num": nums.get(&t.id).copied(), "layout": t.root.as_ref().map(|r| r.to_tmux()).unwrap_or_default(), "panes": panes, "focus": focus, "zoomed": t.zoomed && panes.len() > 1 })
        };
        let me = crate::ipc::here().map(|p| p.display().to_string());
        let path = Self::sessions_path();
        let doc = read_sessions(&path);
        let here = Stash { id: self.session_id, alias: self.session_alias.clone(), desk: self.session_desk, tabs: Vec::new(), active: self.active, lastw: Vec::new(), nums: HashMap::new(), created: self.session_created, activity: epoch_secs(), options: Default::default(), env: Default::default() };
        let mut ours = Vec::new();
        let mut names = HashSet::new();
        let mut desk = None;
        for (s, tabs, nums, lastw, front) in std::iter::once((&here, &self.tabs, &self.nums, &self.lastw, true)).chain(self.sessions.iter().map(|s| (s, &s.tabs, &s.nums, &s.lastw, false))) {
            // The desk's session is every client's: its windows are the desk's tabs.
            if s.desk { desk = Some(json!({ "name": s.alias, "desk": true, "created": s.created, "active": s.active, "windows": [] })); continue }
            let kept: Vec<&Tab> = tabs.iter().filter(|t| t.root.is_some()).collect();
            let windows: Vec<Value> = kept.iter().map(|t| window(self, t, nums)).collect();
            if windows.is_empty() { continue }
            let name = self.stash_name(s);
            names.insert(name.clone());
            let left = how == Save::Leave || how == Save::Release(s.id);
            // The current window and the ones before it (C-b l, the - flag), by their place here.
            let at = |id: &String| kept.iter().position(|t| t.id == *id);
            let active = tabs.get(s.active).and_then(|t| at(&t.id)).unwrap_or(0);
            let last: Vec<usize> = lastw.iter().filter_map(at).collect();
            ours.push(json!({ "name": name, "desk": false, "created": s.created, "activity": s.activity, "active": active, "last": last, "windows": windows,
                "owner": if left { Value::Null } else { json!(me) }, "front": front && !left && !self.headless, "headless": self.headless && !left }));
        }
        let mut rows = Vec::new();
        if !self.forget_sessions {
            // The others: every session as its client wrote it, but for one this client has now.
            for row in doc["sessions"].as_array().cloned().unwrap_or_default() {
                if row.get("desk").and_then(Value::as_bool).unwrap_or(false) { if desk.is_none() { rows.push(row) } continue }
                if me.is_some() && row.get("owner").and_then(Value::as_str) == me.as_deref() { continue }
                if row.get("name").and_then(Value::as_str).map(|n| names.contains(n)).unwrap_or(true) { continue }
                rows.push(row);
            }
            rows.extend(desk);
            rows.extend(ours);
        }
        let current = if self.forget_sessions { Value::Null }
            else if how == Save::Stay || how == Save::Leave { if self.session_desk { Value::Null } else { json!(self.session_name()) } }
            else { doc.get("current").cloned().unwrap_or(Value::Null) };
        let doc = json!({ "current": current, "sessions": rows });
        if let Some(dir) = path.parent() { let _ = std::fs::create_dir_all(dir); }
        let temp = path.with_extension(format!("json.{}.tmp", std::process::id()));
        if std::fs::write(&temp, doc.to_string()).is_ok() { let _ = std::fs::rename(temp, &path); }
        self.remote.borrow_mut().stamp = None;
    }

    /// A session as the file keeps it: each window's harnesses in their panes, laid out as they
    /// were, numbered and named as they were. None when none of its windows has a pane.
    fn stash_from_row(&mut self, row: &Value, id: u32) -> Option<Stash> {
        let name = row.get("name").and_then(Value::as_str)?.to_string();
        let (w, h) = (self.body().width, self.body().height);
        let mut tabs = Vec::new();
        let mut nums = HashMap::new();
        for win in row.get("windows").and_then(Value::as_array).cloned().unwrap_or_default() {
            let panes: Vec<(String, String)> = win.get("panes").and_then(Value::as_array).map(|a| a.iter().filter_map(|p| Some((p.get(0)?.as_str()?.to_string(), p.get(1)?.as_str()?.to_string()))).collect()).unwrap_or_default();
            if panes.is_empty() { continue }
            for p in win.get("panes").and_then(Value::as_array).cloned().unwrap_or_default() {
                if p.get(2).and_then(Value::as_bool).unwrap_or(false) { if let (Some(m), Some(a)) = (p.get(0).and_then(Value::as_str), p.get(1).and_then(Value::as_str)) { self.shells.insert((m.to_string(), a.to_string())); } }
            }
            let ids: Vec<u64> = panes.iter().map(|(m, a)| self.new_pane(m, a)).collect();
            let mut tab = Tab::new(win.get("name").and_then(Value::as_str).unwrap_or(""));
            tab.named = win.get("named").and_then(Value::as_bool).unwrap_or(false);
            let layout = win.get("layout").and_then(Value::as_str).unwrap_or("");
            tab.root = Node::from_tmux(layout, &ids, w, h).or_else(|| layout::arrange(layout::Named::Tiled, &ids, w, h, layout::Status::Top, DESK_MAIN, ("0", "0")));
            tab.focus = ids.get(win.get("focus").and_then(Value::as_u64).unwrap_or(0) as usize).or(ids.first()).copied();
            tab.zoomed = win.get("zoomed").and_then(Value::as_bool).unwrap_or(false) && ids.len() > 1;
            if let Some(n) = win.get("num").and_then(Value::as_u64) { nums.insert(tab.id.clone(), n as usize); }
            tabs.push(tab);
        }
        if tabs.is_empty() { return None }
        let active = row.get("active").and_then(Value::as_u64).unwrap_or(0) as usize;
        let created = row.get("created").and_then(Value::as_i64).unwrap_or_else(epoch_secs);
        let lastw: Vec<String> = row.get("last").and_then(Value::as_array).map(|l| l.iter().filter_map(|i| tabs.get(i.as_u64()? as usize).map(|t| t.id.clone())).collect()).unwrap_or_default();
        Some(Stash { id, alias: Some(name), desk: false, active: active.min(tabs.len() - 1), tabs, lastw, nums,
            created, activity: row.get("activity").and_then(Value::as_i64).unwrap_or(created), options: Default::default(), env: Default::default() })
    }

    /// The sessions no running client has (save_sessions: left by clients that detached), back
    /// as they were; another client's stay with it, listed here. Then the one asked for at start
    /// (`hn attach -t work`, `hn new -A -s main`: another client's is given up by it), else the
    /// one in front when the last client left — unless another client has it.
    pub fn load_sessions(&mut self) {
        let mut doc = read_sessions(&Self::sessions_path());
        let me = crate::ipc::here().map(|p| p.display().to_string());
        // A headless hn (tmux's server with no client) hands everything to the first client that
        // attaches: one holder of the sessions again, as tmux has one server.
        if !self.headless {
            let held: HashSet<String> = doc["sessions"].as_array().map(|rows| rows.iter().filter(|r| r.get("headless").and_then(Value::as_bool).unwrap_or(false)).filter_map(live_owner).collect()).unwrap_or_default();
            for owner in &held { let _ = crate::ipc::ask(std::path::Path::new(owner), &["hn-hand-over".into()]); }
        }
        // The rows no client has are read and made this client's while the file is held: two
        // clients starting together never both take one.
        let path = Self::sessions_path();
        let lock = crate::ipc::lock(&path);
        doc = read_sessions(&path);
        for row in doc["sessions"].as_array().cloned().unwrap_or_default() {
            let name = row.get("name").and_then(Value::as_str).map(str::to_string);
            if row.get("desk").and_then(Value::as_bool).unwrap_or(false) { if name.is_some() && self.session_desk { self.session_alias = name } continue }
            let Some(name) = name else { continue };
            if live_owner(&row).filter(|o| Some(o) != me.as_ref()).is_some() { continue }
            if self.own_session(&name).is_some() { continue }
            let id = self.remote_id(&name);
            if let Some(stash) = self.stash_from_row(&row, id) { self.sessions.push(stash) }
        }
        self.write_sessions_held(Save::Stay);
        drop(lock);
        self.remote.borrow_mut().stamp = None;
        // The session in front when the last client left — or one a headless client holds (it
        // made them for a script; this client is where they are meant to be seen).
        let held = |name: &str| doc["sessions"].as_array().map(|rows| rows.iter().any(|r| r.get("name").and_then(Value::as_str) == Some(name)
            && r.get("headless").and_then(Value::as_bool).unwrap_or(false) && live_owner(r).is_some())).unwrap_or(false);
        let current = doc.get("current").and_then(Value::as_str).map(str::to_string)
            .and_then(|c| self.own_session(&c).or_else(|| if held(&c) && !self.headless { self.find_session(&format!("={c}")) } else { None }))
            .filter(|c| *c != self.session_id);
        match self.start_session.clone() {
            None => if let Some(id) = current { self.switch_session(id) },
            Some(start) => {
                // attach -t finds a session as tmux does (its name, the only one it starts, a
                // pattern); new -s is the exact name.
                let found = start.name.as_deref().and_then(|n| if start.create { self.find_session(&format!("={n}")) } else { self.find_session(n) });
                match (found, start.create) {
                    // attach -t, new -A: there already (attach -t work:2: at that window).
                    (Some(id), false) => {
                        self.switch_session(id);
                        self.start_session = None;
                        if let Some(w) = &start.target {
                            let spec = crate::cmd::Spec { kind: crate::cmd::Kind::Window, can_fail: false, window_index: false, default_marked: false };
                            match crate::cmd::resolve(self, Some(&format!(":{w}")), spec).ok().and_then(|f| f.window) {
                                Some(i) => self.select_tab(i),
                                None => { let e = format!("can't find window: {w}"); self.start_error(e); return }
                            }
                        }
                    }
                    (Some(id), true) if start.attach_existing => { self.switch_session(id); self.start_session = None }
                    (Some(_), true) => { self.start_error(format!("duplicate session: {}", start.name.clone().unwrap_or_default())) }
                    // A fresh start's first session is the desk's (desk=off: the client's first),
                    // named as asked; another is made once this computer is connected
                    // (maybe_start_shell).
                    (None, true) if self.sessions.is_empty() && self.session_alias.is_none() && start.window.is_none() => {
                        self.session_alias = start.name.as_deref().and_then(session_check_name);
                    }
                    (None, true) => {}
                    (None, false) => match &start.name {
                        Some(n) => self.start_error(format!("can't find session: {}", n.trim_start_matches('='))),
                        // attach with no -t: the session in front last, wherever it is (another
                        // terminal's is taken, as attach -t takes it); none kept: a new one.
                        None => {
                            self.start_session = None;
                            let last = doc.get("current").and_then(Value::as_str).and_then(|c| self.find_session(&format!("={c}"))).filter(|c| *c != self.session_id);
                            if let Some(id) = current.or(last) { self.switch_session(id) }
                        }
                    },
                }
            }
        }
        if self.start_failed.is_some() { return }
        // desk=off: the session the client started in is tmux's first, named by its number.
        if self.session_id == 0 && !self.session_desk && self.session_alias.is_none() {
            let mut n = 0u32;
            while self.find_session(&format!("={n}")).is_some() { n = self.alloc_session_id() }
            self.session_alias = Some(n.to_string());
        }
        self.save_sessions();
    }

    /// A start that can't be done (`hn attach -t nosuch`): said as tmux says it, and no client.
    fn start_error(&mut self, e: String) {
        self.start_session = None;
        self.start_failed = Some(e);
        self.quit = true;
    }

    /// server_destroy_session, for the session in front, whose last window has gone: another
    /// session takes the client (detach-on-destroy off: the one it was in last, or the newest;
    /// previous, next: by name), else the client exits (`[exited]`). The desk's session stays,
    /// its window the home screen, for the desk's tabs to come back to.
    pub fn session_gone(&mut self) {
        self.notify_closed();
        self.session_gone_quiet()
    }

    /// session-closed, for the session in front (session_destroy's first notify).
    fn notify_closed(&mut self) {
        if !self.session_desk { let (sid, name) = (self.session_id, self.session_name()); crate::commands::notify_session(self, "session-closed", sid, &name, None) }
    }

    fn session_gone_quiet(&mut self) {
        let gone = self.session_id;
        // A session a command ran in for a moment: gone, and nothing else changes.
        if let Some(back) = self.swap_back.filter(|b| *b != gone) {
            if self.session_desk { return }
            self.swap_session(back);
            self.sessions.retain(|s| s.id != gone);
            self.save_sessions();
            return;
        }
        let how = self.options.get("detach-on-destroy", "", None).unwrap_or_default();
        let others: Vec<u32> = self.sessions.iter().map(|s| s.id).collect();
        let next = match how.as_str() {
            "off" | "no-detached" => self.last_session.filter(|l| others.contains(l)).or_else(|| self.sessions.iter().max_by_key(|s| s.created).map(|s| s.id)),
            "previous" => self.neighbour_session(false),
            "next" => self.neighbour_session(true),
            _ => None,
        };
        let desk = self.session_desk;
        match next {
            Some(id) => {
                self.switch_session(id);
                self.last_session = None;
                if !desk { self.sessions.retain(|s| s.id != gone) }
            }
            None => {
                if !desk { if let Some(desk_id) = self.sessions.iter().find(|s| s.desk).map(|s| s.id) { self.swap_session(desk_id); self.sessions.retain(|s| s.id != gone) } }
                self.quit = true;
                self.exited = true;
            }
        }
        self.save_sessions();
    }

    /// tmux's named layout (layout-set.c) on a window: main-pane-* and other-pane-* as set,
    /// remembered for next-layout.
    pub fn arrange_tab(&mut self, index: usize, named: layout::Named) {
        let body = self.body();
        let Some(tab) = self.tabs.get(index) else { return };
        let tab_id = tab.id.clone();
        let get = |n: &str| self.options.get(n, &tab_id, None).unwrap_or_default();
        let (mw, mh, ow, oh) = (get("main-pane-width"), get("main-pane-height"), get("other-pane-width"), get("other-pane-height"));
        let status = self.pane_status(tab);
        let ids = tab.panes();
        let tab = &mut self.tabs[index];
        tab.root = layout::arrange(named, &ids, body.width, body.height, status, (&mw, &mh), (&ow, &oh));
        tab.zoomed = false;
        tab.layout_at = layout::Named::ALL.iter().position(|n| *n == named);
        self.fit_panes();
        self.layout_changed(index);
    }


    /// move-window -r: every window numbered in order from base-index.
    pub fn renumber_all(&mut self) {
        for (i, t) in self.tabs.iter().enumerate() { self.nums.insert(t.id.clone(), i + self.base_index); }
        self.fit_panes();
    }

    /// Give every window without an index the first free one; forget closed windows'.
    pub fn renumber(&mut self) {
        let ids: HashSet<String> = self.tabs.iter().map(|t| t.id.clone()).collect();
        self.nums.retain(|id, _| ids.contains(id));
        // renumber-windows on: no gaps, in order.
        if self.options.get("renumber-windows", "", None).as_deref() == Some("on") {
            for (i, t) in self.tabs.iter().enumerate() { self.nums.insert(t.id.clone(), i + self.base_index); }
            return;
        }
        for i in 0..self.tabs.len() {
            if self.nums.contains_key(&self.tabs[i].id) { continue }
            let n = self.free_num();
            self.nums.insert(self.tabs[i].id.clone(), n);
        }
    }

    fn free_num(&self) -> usize {
        let used: HashSet<usize> = self.nums.values().copied().collect();
        (self.base_index..).find(|n| !used.contains(n)).unwrap_or(self.base_index)
    }

    /// The window index tmux would show for the tab at `index`.
    pub fn win_num(&self, index: usize) -> usize {
        self.tabs.get(index).and_then(|t| self.nums.get(&t.id).copied()).unwrap_or(index + self.base_index)
    }

    pub fn tab_by_num(&self, n: usize) -> Option<usize> { (0..self.tabs.len()).find(|i| self.win_num(*i) == n) }

    /// server_link_window then server_unlink_window, as move-window does them: the window at
    /// [src] takes number [idx] (the first free one from base-index when none — its own number
    /// still taken while it is looked for), a window already there replaced with [kill] ("index
    /// in use: N" without; "same index: N" when it is this one), made current if [select] (or if
    /// the one replaced was current); a current window moved without it leaves for the last one.
    pub fn move_window(&mut self, src: usize, idx: Option<usize>, kill: bool, select: bool) -> Result<(), String> {
        self.renumber();
        let id = self.tabs[src].id.clone();
        let mut select = select;
        if let Some(n) = idx {
            if let Some(i) = self.tab_by_num(n) {
                if i == src { return Err(format!("same index: {n}")) }
                if !kill { return Err(format!("index in use: {n}")) }
                // -k: that window goes (its harnesses keep running); if it was current, the moved
                // one takes its place as current.
                let gone = self.tabs.remove(i);
                self.lastw.retain(|x| *x != gone.id);
                if i == self.active { select = true; self.active = self.tabs.iter().position(|t| t.id == id).unwrap_or(0) }
                else if i < self.active { self.active -= 1 }
                for p in gone.panes() { self.end_shell(p); self.drop_pane(p) }
                if gone.on_desk { self.desk_op(json!({ "op": "tab.close", "id": gone.id })) }
            }
        }
        let n = idx.unwrap_or_else(|| self.free_num());
        let old = self.nums.get(&id).copied().unwrap_or(n);
        let current = self.tabs[self.active].id.clone();
        // session_detach of the old place: the current window moved and not selected goes to the
        // last one, else the one before it by number, round to the highest.
        let leave = !select && current == id;
        self.nums.insert(id.clone(), n);
        let nums = self.nums.clone();
        self.tabs.sort_by_key(|t| nums.get(&t.id).copied().unwrap_or(usize::MAX));
        let at = self.tabs.iter().position(|t| t.id == id).unwrap_or(0);
        self.active = self.tabs.iter().position(|t| t.id == current).unwrap_or(at);
        if let Some(tab) = self.tabs.get(at).filter(|t| t.on_desk) { let op = json!({ "op": "tab.move", "id": tab.id, "index": at }); self.desk_op(op) }
        if select { self.select_tab(at) }
        else if leave {
            // session_last, else session_previous from the old number (the moved window, at its
            // new one, counts), round to the highest.
            let last = self.lastw.first().and_then(|x| self.tabs.iter().position(|t| &t.id == x)).filter(|p| *p != at);
            let before = (0..self.tabs.len()).filter(|p| self.win_num(*p) < old).max_by_key(|p| self.win_num(*p));
            let to = last.or(before).unwrap_or(self.tabs.len() - 1);
            self.select_tab(to);
            self.lastw.retain(|x| *x != id);
        }
        self.fit_panes();
        Ok(())
    }

    pub fn tab_mut(&mut self) -> &mut Tab { &mut self.tabs[self.active] }
    pub fn focused(&self) -> Option<u64> { self.tab().focus }

    /// Everything but the status line (tmux `status-position`, bottom by default).
    pub fn body(&self) -> Rect {
        let n = self.status_lines();
        Rect::new(0, if self.status_top { n } else { 0 }, self.size.0, self.size.1.saturating_sub(n))
    }

    /// tmux's status option: how many status lines (off, on, 2 … 5).
    pub fn status_lines(&self) -> u16 {
        match self.options.get("status", "", None).as_deref() { Some("off") => 0, Some("2") => 2, Some("3") => 3, Some("4") => 4, Some("5") => 5, _ => 1 }
    }

    /// A pane's own border line: tmux draws none for a lone pane, and with `pane-border-status top`
    /// a titled line above each pane when a window holds several.

    /// environ_update: each update-environment pattern's variables from hn's own environment
    /// into the session's, or the pattern cleared there when none match.
    pub fn update_environment(&mut self) {
        for pattern in self.options.array("update-environment") {
            let found: Vec<(String, String)> = std::env::vars().filter(|(k, _)| crate::cmd::fnmatch(&pattern, k)).collect();
            if found.is_empty() { self.session_env.insert(pattern, EnvVar { value: None, hidden: false }); }
            for (k, v) in found { self.session_env.insert(k, EnvVar { value: Some(v), hidden: false }); }
        }
    }

    /// buffer-limit: how many automatic paste buffers are kept.
    pub fn buffer_limit(&self) -> usize { self.options.get("buffer-limit", "", None).and_then(|v| v.parse().ok()).unwrap_or(50) }


    /// pane-base-index for a window: the number its first pane has.
    pub fn pane_base(&self, window: usize) -> usize {
        let id = self.tabs.get(window).map(|t| t.id.as_str()).unwrap_or("");
        self.options.get("pane-base-index", id, None).and_then(|v| v.parse().ok()).unwrap_or(0)
    }

    /// A *-style option as tmux's style_add reads it for a window (and a pane): the value in force
    /// there, a format in it expanded first (options_string_to_style), parsed over no colours —
    /// its attributes and background included.
    pub fn style_of(&self, name: &str, window: usize, pane: Option<u64>) -> Style {
        let id = self.tabs.get(window).map(|t| t.id.as_str()).unwrap_or("");
        let raw = self.options.get(name, id, pane).unwrap_or_default();
        let spec = if raw.contains("#{") { crate::format::expand(self, &raw, window, pane, false) } else { raw };
        crate::draw::style_over(&spec, Style::default())
    }

    /// The status line's colours (status_redraw): status-style, then status-fg and status-bg
    /// where they are not `default`; under NO_COLOR with tmux's own, reverse video.
    pub fn status_style(&self) -> Style {
        if self.plain_status() { return Style::default().add_modifier(Modifier::REVERSED) }
        let mut s = self.style_of("status-style", self.active, None);
        for (name, fg) in [("status-fg", true), ("status-bg", false)] {
            let c = self.options.get(name, "", None).and_then(|v| crate::tmuxconf::colour(&v)).filter(|c| *c != Color::Reset);
            if let Some(c) = c { s = if fg { s.fg(c) } else { s.bg(c) } }
        }
        s
    }

    /// message-style (tmux's yellow), for messages and prompts; reverse video under NO_COLOR.
    pub fn message_style(&self) -> Style {
        if self.plain_status() { return Style::default().add_modifier(Modifier::REVERSED) }
        self.style_of("message-style", self.active, None)
    }

    /// NO_COLOR, with tmux's own status and message colours: those carry no colour.
    pub fn plain_status(&self) -> bool {
        crate::theme::no_color() && ["status-style", "status-fg", "status-bg", "message-style"].iter().all(|n| self.options.get(n, "", None).as_ref() == crate::options::tmux_defaults().get(*n))
    }

    /// mode-keys as it stands (tmux's default: emacs, unless $VISUAL or $EDITOR is a vi).
    pub fn mode_keys_emacs(&self) -> bool {
        let tab = self.tabs.get(self.active).map(|t| t.id.clone()).unwrap_or_default();
        self.options.get("mode-keys", &tab, self.focused()).as_deref() != Some("vi")
    }

    /// A window's pane-border-status as it shows: hn's default (top) where it has several panes;
    /// once you set it yourself, as tmux has it — on a lone pane too, and bottom or off.
    pub fn pane_status(&self, tab: &Tab) -> layout::Status {
        // As tmux draws it: over a lone pane too.
        layout::Status::of(&self.options.get("pane-border-status", &tab.id, None).unwrap_or_default())
    }

    /// A pane's own cells within its tile: the status line taken off, above or below.
    pub fn content_of(&self, tab: &Tab, r: Rect) -> Rect {
        match self.pane_status(tab) {
            layout::Status::Top => Rect::new(r.x, r.y + 1, r.width, r.height.saturating_sub(1)),
            layout::Status::Bottom => Rect::new(r.x, r.y, r.width, r.height.saturating_sub(1)),
            layout::Status::Off => r,
        }
    }

    fn compute_rects(&self) -> Vec<(u64, Rect)> {
        let tab = self.tab();
        let mut out = Vec::new();
        let body = self.body();
        if let Some(root) = &tab.root {
            if tab.zoomed { if let Some(focus) = tab.focus { return vec![(focus, body)] } }
            root.rects(body, &mut out);
        }
        out
    }

    fn content_size(&self, pane_id: u64) -> Option<(u16, u16)> {
        let rects = self.compute_rects();
        if let Some((_, r)) = rects.iter().find(|(id, _)| *id == pane_id) { let c = self.content_of(self.tab(), *r); return Some((c.width, c.height)) }
        // A pane in a background tab: size it as if its tab were showing.
        for (index, tab) in self.tabs.iter().enumerate() {
            if index == self.active { continue }
            if let Some(root) = &tab.root {
                let mut out = Vec::new();
                root.rects(self.body(), &mut out);
                if let Some((_, r)) = out.iter().find(|(id, _)| *id == pane_id) { let c = self.content_of(tab, *r); return Some((c.width, c.height)) }
            }
        }
        None
    }

    /// Where a harness is open in any of this client's sessions: the session, its window (by its
    /// number) and the pane.
    pub fn find_pane_anywhere(&self, machine_id: &str, agent_id: &str) -> Option<(u32, usize, u64)> {
        if let Some((w, p)) = self.find_pane(machine_id, agent_id) { return Some((self.session_id, self.win_num(w), p)) }
        let shows = |id: &u64| self.panes.get(id).map(|p| p.machine_id == machine_id && p.agent_id == agent_id).unwrap_or(false);
        self.sessions.iter().find_map(|s| s.tabs.iter().find_map(|t| t.panes().into_iter().find(|p| shows(p)).map(|p| (s.id, s.nums.get(&t.id).copied().unwrap_or(0), p))))
    }

    pub fn find_pane(&self, machine_id: &str, agent_id: &str) -> Option<(usize, u64)> {
        for (index, tab) in self.tabs.iter().enumerate() {
            for id in tab.panes() {
                if let Some(p) = self.panes.get(&id) { if p.machine_id == machine_id && p.agent_id == agent_id { return Some((index, id)) } }
            }
        }
        None
    }

    pub fn focus_pane(&mut self, tab: usize, pane: u64) {
        if let Some(prev) = self.focused().and_then(|f| self.panes.get(&f)).map(|p| (p.machine_id.clone(), p.agent_id.clone())) {
            if self.panes.get(&pane).map(|p| (p.machine_id.clone(), p.agent_id.clone())) != Some(prev.clone()) { self.last_harness = Some(prev) }
        }
        let changed = tab != self.active;
        if changed { self.lastw_leave(tab); self.home_order.borrow_mut().clear() }
        self.active = tab;
        self.tabs[tab].alerts = 0;
        if changed { self.tabs[tab].touch(); self.alert(tab, ACTIVITY) }
        if self.tabs[tab].zoomed && self.tabs[tab].focus != Some(pane) { self.tabs[tab].zoomed = false }
        self.tabs[tab].set_active(pane);
        self.seen(pane);
        self.sync_titles();
        self.fit_panes();
        self.refresh_pane_info(pane);
    }

    /// A machine's first roster since hn started, read against when you last looked at each of
    /// its harnesses: one that has done something since (its transcript changed after), and is
    /// not working or asking now, is done and unread — what finished while hn was closed.
    pub fn catch_up(&mut self, machine_id: &str) {
        if !self.seen_rostered.insert(machine_id.to_string()) { return }
        let floor = self.seen_since;
        for agent in self.fleet.agents.values_mut().filter(|a| a.machine_id == machine_id && a.engine != "terminal") {
            let seen = self.seen_at.get(&(agent.machine_id.clone(), agent.id.clone())).copied().unwrap_or(floor);
            if agent.usage_at > seen && !agent.working && agent.question.is_none() && agent.status != "stopped" {
                agent.unread = true;
                if agent.since == 0 { agent.since = agent.usage_at }
            }
        }
    }

    /// seen.json's path.
    fn seen_path() -> std::path::PathBuf {
        std::path::PathBuf::from(std::env::var("HOME").unwrap_or_default()).join(".harness").join("tui").join("seen.json")
    }

    /// When you last looked at each harness, from the run before (the first run starts the clock).
    pub fn load_seen(&mut self) {
        let doc: Value = std::fs::read_to_string(Self::seen_path()).ok().and_then(|t| serde_json::from_str(&t).ok()).unwrap_or(Value::Null);
        self.seen_since = doc.get("since").and_then(Value::as_u64).unwrap_or_else(fleet::now_ms);
        for (k, v) in doc.get("seen").and_then(Value::as_object).cloned().unwrap_or_default() {
            if let (Some((m, a)), Some(t)) = (k.split_once(':'), v.as_u64()) { self.seen_at.insert((m.to_string(), a.to_string()), t); }
        }
        if doc.is_null() { self.seen_dirty = true }
    }

    pub fn save_seen(&mut self) {
        if !self.seen_dirty { return }
        self.seen_dirty = false;
        let seen: serde_json::Map<String, Value> = self.seen_at.iter().map(|((m, a), t)| (format!("{m}:{a}"), json!(t))).collect();
        let path = Self::seen_path();
        if let Some(dir) = path.parent() { let _ = std::fs::create_dir_all(dir); }
        let temp = path.with_extension("json.tmp");
        if std::fs::write(&temp, json!({ "since": self.seen_since, "seen": seen }).to_string()).is_ok() { let _ = std::fs::rename(temp, path); }
    }

    /// You have looked at this harness now.
    pub fn mark_seen_key(&mut self, key: (String, String)) {
        self.seen_at.insert(key, fleet::now_ms());
        self.seen_dirty = true;
    }

    pub fn seen(&mut self, pane: u64) {
        let Some(p) = self.panes.get(&pane) else { return };
        let key = (p.machine_id.clone(), p.agent_id.clone());
        self.mark_seen_key(key.clone());
        if let Some(agent) = self.fleet.agents.get_mut(&key) {
            // Looked at here (an error it ended in too): the dial takes its notification away.
            agent.errored = false;
            if std::mem::take(&mut agent.unread) { crate::dial::seen(self, &key.1) }
        }
    }

    pub fn visible_agents(&self) -> Vec<(String, String)> {
        self.rects.iter().filter_map(|(id, _)| self.panes.get(id)).map(|p| (p.machine_id.clone(), p.agent_id.clone())).collect()
    }

    pub fn new_pane(&mut self, machine_id: &str, agent_id: &str) -> u64 {
        let id = self.next_pane;
        self.next_pane += 1;
        let (cols, rows) = pane::stream_size(self.size.0, self.size.1.saturating_sub(2));
        self.panes.insert(id, Pane::new(id, machine_id, agent_id, cols, rows));
        id
    }

    /// Put a harness on screen. Already showing somewhere: go there instead.
    pub fn open_agent(&mut self, machine_id: &str, agent_id: &str, placement: Placement) {
        if let Placement::Fill(tab_id) = &placement {
            let id = self.new_pane(machine_id, agent_id);
            let (w, h) = (self.body().width, self.body().height);
            let here = self.tabs.iter().position(|t| &t.id == tab_id);
            let tab = match here { Some(i) => Some(&mut self.tabs[i]), None => self.sessions.iter_mut().flat_map(|s| s.tabs.iter_mut()).find(|t| &t.id == tab_id) };
            match tab {
                Some(t) if t.root.is_none() => { t.root = Some(Node::new(id, w, h)); t.focus = Some(id) }
                _ => { self.drop_pane(id); return }
            }
            if here == Some(self.active) { self.open_stream(id, true) }
            self.fit_panes();
            self.save_sessions();
            return;
        }
        if placement != Placement::Replace && placement != Placement::Window {
            // Open in another session of this client: that session, as tmux's chooser goes there.
            if self.find_pane(machine_id, agent_id).is_none() {
                if let Some((sid, _, _)) = self.find_pane_anywhere(machine_id, agent_id) { self.switch_session(sid) }
            }
            if let Some((tab, pane)) = self.find_pane(machine_id, agent_id) {
                // One harness, one pane: say where it went rather than splitting a second copy.
                if tab != self.active && matches!(placement, Placement::Split(_)) {
                    let name = self.fleet.agent(machine_id, agent_id).map(|a| a.name.clone()).unwrap_or_default();
                    self.say(format!("{name} is already in window {}", self.win_num(tab)), crate::theme::WARN);
                }
                self.focus_pane(tab, pane);
                return;
            }
        }
        let id = self.new_pane(machine_id, agent_id);
        if let Placement::At(at) = &placement {
            let Some(t) = self.tabs.iter().position(|x| x.id == at.tab) else { self.drop_pane(id); return };
            if !self.split_at(t, id, at) { self.drop_pane(id); self.error("no space for new pane"); return }
            let tab = &mut self.tabs[t];
            tab.add_pane(id, at.pane, at.before, at.full);
            // tmux takes a zoomed window out of zoom (-Z: zooms its active pane after); the new
            // pane is its active one unless -d.
            if !at.detached || tab.focus.is_none() { tab.set_active(id) }
            tab.zoomed = at.zoom && tab.panes().len() > 1;
            let tab_id = tab.id.clone();
            self.open_stream(id, true);
            self.fit_panes();
            self.desk_pane_added(&tab_id, machine_id, agent_id);
            self.layout_changed(t);
            return;
        }
        let empty = self.tab().root.is_none();
        match (placement, empty) {
            (Placement::Tab, false) | (Placement::Window, false) => {
                let name = self.fleet.agent(machine_id, agent_id).map(|a| a.name.clone()).unwrap_or_else(|| "tab".into());
                let mut tab = Tab::new(&name);
                tab.root = Some(Node::new(id, self.size.0, self.size.1.saturating_sub(1)));
                tab.focus = Some(id);
                // As new-window: the first free index, in its place in the order.
                self.renumber();
                { let id = self.tabs[self.active].id.clone(); self.lastw_push(id) }
                let n = self.free_num();
                self.nums.insert(tab.id.clone(), n);
                let at = self.tabs.iter().position(|t| self.nums.get(&t.id).map(|m| *m > n).unwrap_or(false)).unwrap_or(self.tabs.len());
                self.tabs.insert(at, tab);
                self.active = at;
            }
            (_, true) => {
                let body = self.body();
                let tab = self.tab_mut();
                tab.root = Some(Node::new(id, body.width, body.height));
                tab.focus = Some(id);
            }
            (Placement::Replace, false) => {
                let Some(focus) = self.focused() else { return };
                let old = focus;
                if let Some(p) = self.panes.get(&old) {
                    let op = json!({ "op": "pane.remove", "tabId": self.tab().id, "machineId": p.machine_id, "agentId": p.agent_id });
                    if self.tab().on_desk { self.desk_op(op) }
                }
                if let Some(root) = self.tab_mut().root.as_mut() { root.replace(old, id); }
                let tab = self.tab_mut();
                for p in tab.order.iter_mut().chain(tab.last.iter_mut()) { if *p == old { *p = id } }
                tab.focus = Some(id);
                self.drop_pane(old);
            }
            (Placement::At(_), _) | (Placement::Fill(_), _) => {}
            (Placement::Split(dir), false) | (Placement::Auto(Some(dir)), false) => { if !self.split_focused(id, dir) { self.drop_pane(id); self.error("no space for new pane"); return } let t = self.active; self.layout_changed(t) }
            (Placement::Auto(None), false) => {
                let dir = self.smart_dir();
                if !self.split_focused(id, dir) { self.drop_pane(id); self.error("no space for new pane"); return }
                let t = self.active;
                self.layout_changed(t);
            }
        }
        self.tab_mut().zoomed = false;
        self.name_tab_after_first();
        // The person asked for THIS harness: open it as the controller before the layout pass,
        // which would otherwise open it as a mere watcher of whoever has it elsewhere.
        self.open_stream(id, true);
        self.fit_panes();
        self.seen(id);
        let tab_id = self.tab().id.clone();
        self.desk_pane_added(&tab_id, machine_id, agent_id);
    }

    /// split-window's (and join-pane's) split: `id` gets a cell beside `at.pane` (-b before it,
    /// -f across the window) of `at.size`; false, and nothing changed, when there is no room.
    /// Whether split_at would find room (spawn_pane's check before anything is made): tried on a
    /// copy of the window's layout.
    pub fn can_split(&mut self, at: &At) -> bool {
        let Some(t) = self.tabs.iter().position(|x| x.id == at.tab) else { return false };
        let saved = (self.tabs[t].root.clone(), self.tabs[t].zoomed);
        let ok = self.split_at(t, u64::MAX - 1, at);
        let tab = &mut self.tabs[t];
        (tab.root, tab.zoomed) = saved;
        ok
    }

    fn split_at(&mut self, t: usize, id: u64, at: &At) -> bool {
        let body = self.body();
        // -l n%: of the target pane's width or height (-f: the window's), measured as tmux
        // measures it — before a zoomed window is unzoomed.
        let cur = if at.full {
            let (w, h) = self.tabs[t].root.as_ref().map(|r| r.size()).unwrap_or((body.width, body.height));
            if at.dir == Dir::Horizontal { w } else { h }
        } else {
            at.pane.and_then(|p| crate::format::content_rect(self, t, p)).map(|r| if at.dir == Dir::Horizontal { r.width } else { r.height }).unwrap_or(0)
        };
        let size = at.size.map(|(n, pct)| if pct { cur as u32 * n as u32 / 100 } else { n as u32 });
        self.fit_panes_of(t);
        let tab = &mut self.tabs[t];
        tab.zoomed = false;
        match tab.root.as_mut() {
            None => { tab.root = Some(Node::new(id, body.width, body.height)); true }
            Some(root) => root.split_with(at.pane, id, at.dir, size, at.before, at.full || at.pane.is_none()),
        }
    }

    /// A pane leaves its window but not the screen (join-pane, break-pane): its harness and
    /// stream go on, its id with it; a window left empty closes.
    fn unhook_pane(&mut self, id: u64) {
        let Some(index) = self.tabs.iter().position(|t| t.panes().contains(&id)) else { return };
        let tab = &mut self.tabs[index];
        tab.lose(id);
        tab.root = tab.root.take().and_then(|root| root.remove(id));
        tab.zoomed = false;
        let tab_id = tab.id.clone();
        if let Some(p) = self.panes.get(&id) { let op = json!({ "op": "pane.remove", "tabId": tab_id, "machineId": p.machine_id, "agentId": p.agent_id }); self.desk_op(op) }
        if self.tabs[index].root.is_none() && self.tabs.len() > 1 { self.close_tab(index) }
        else if self.tabs[index].root.is_none() && !self.tabs[index].named { self.tabs[index].name = "home".into() }
    }

    /// tmux's join-pane / move-pane: `src` splits `at.pane` where `at` says, keeping its id; in
    /// the list it goes after the target (before it with -b), -f or not. Not -d: its window
    /// becomes the current one with it active.
    pub fn join_pane(&mut self, src: u64, at: At) -> Result<(), String> {
        let Some(t) = self.tabs.iter().position(|x| x.id == at.tab) else { return Err("can't find window".into()) };
        let Some(dst) = at.pane else { return Err("can't find pane".into()) };
        if src == dst { return Err("source and target panes must be different".into()) }
        // The room is made first: no room, and nothing moves.
        const SLOT: u64 = u64::MAX;
        if !self.split_at(t, SLOT, &at) { return Err("create pane failed: pane too small".into()) }
        let point = self.tabs.iter().find_map(|x| x.points.get(&src).copied());
        let from = self.tabs.iter().position(|x| x.panes().contains(&src) && x.id != at.tab);
        let from_id = from.map(|w| self.tabs[w].id.clone());
        match from {
            Some(_) => self.unhook_pane(src),
            None => {
                // Within the window: its old cell closes, the list forgets it.
                let tab = &mut self.tabs[t];
                tab.lose(src);
                tab.root = tab.root.take().and_then(|root| root.remove(src));
            }
        }
        let Some(t) = self.tabs.iter().position(|x| x.id == at.tab) else { return Ok(()) };
        let tab = &mut self.tabs[t];
        if let Some(root) = tab.root.as_mut() { root.replace(SLOT, src); }
        tab.add_pane(src, Some(dst), at.before, false);
        if let Some(p) = point { tab.points.insert(src, p); }
        tab.zoomed = false;
        let (machine, agent) = self.panes.get(&src).map(|p| (p.machine_id.clone(), p.agent_id.clone())).unwrap_or_default();
        if !at.detached { self.tabs[t].set_active(src); self.focus_pane(t, src) }
        let tab_id = self.tabs[t].id.clone();
        self.desk_pane_added(&tab_id, &machine, &agent);
        self.sync_titles();
        self.fit_panes();
        // cmd-join-pane.c: the window it left (if it is still there), then this one.
        if let Some(w) = from_id.and_then(|id| self.tabs.iter().position(|x| x.id == id)) { self.layout_changed(w) }
        self.layout_changed(t);
        Ok(())
    }

    /// A window taken out of the session in front (it moves to another session), its harnesses
    /// still in its panes: its number freed, the current window kept; the desk told it closed.
    pub fn take_tab(&mut self, index: usize) -> Tab {
        let mut tab = self.tabs.remove(index);
        self.nums.remove(&tab.id);
        self.lastw.retain(|x| *x != tab.id);
        if index < self.active { self.active -= 1 }
        if self.tabs.is_empty() { self.tabs.push(Tab::new("home")) }
        self.active = self.active.min(self.tabs.len() - 1);
        if tab.on_desk && self.session_desk { self.desk_op(json!({ "op": "tab.close", "id": tab.id })) }
        tab.on_desk = false;
        tab
    }

    /// A window from another session, put in the one in front: at [index] numbered [num], else
    /// last with a number past every other (for move-window to give it its own); the desk's
    /// session tells the desk. Where it went.
    pub fn put_tab(&mut self, tab: Tab, at: Option<(usize, usize)>) -> usize {
        let (index, num) = at.unwrap_or((self.tabs.len(), usize::MAX / 2));
        let index = index.min(self.tabs.len());
        let id = tab.id.clone();
        let panes: Vec<(String, String)> = tab.panes().iter().filter_map(|p| self.panes.get(p).map(|x| (x.machine_id.clone(), x.agent_id.clone()))).collect();
        self.nums.insert(id.clone(), num);
        self.tabs.insert(index, tab);
        if index <= self.active && self.tabs.len() > 1 { self.active += 1 }
        // The placeholder of a session that had none (the current one then, or before it).
        if let Some(home) = self.tabs.iter().position(|t| t.root.is_none() && t.id != id) { self.tabs.remove(home); if home <= self.active && self.active > 0 { self.active -= 1 } }
        self.active = self.active.min(self.tabs.len() - 1);
        for (m, a) in panes { self.desk_pane_added(&id, &m, &a) }
        self.fit_panes();
        self.tabs.iter().position(|t| t.id == id).unwrap_or(0)
    }

    /// A pane taken out of its window in the session in front (it moves to another session), its
    /// harness still running: a window it leaves empty goes.
    pub fn take_pane(&mut self, pane: u64) {
        let Some(index) = self.tabs.iter().position(|t| t.panes().contains(&pane)) else { return };
        let tab = &mut self.tabs[index];
        tab.lose(pane);
        tab.root = tab.root.take().and_then(|root| root.remove(pane));
        tab.zoomed = false;
        let tab_id = tab.id.clone();
        if let Some(p) = self.panes.get(&pane) { let op = json!({ "op": "pane.remove", "tabId": tab_id, "machineId": p.machine_id, "agentId": p.agent_id }); self.desk_op(op) }
        if self.tabs[index].root.is_none() { self.take_tab(index); } else { self.layout_changed(index); self.fit_panes() }
    }

    /// A window of one pane (a pane from another session), named [name], put last in the
    /// session in front.
    pub fn tab_of_pane(&mut self, pane: u64, name: &str) -> usize {
        let mut tab = Tab::new(name);
        tab.root = Some(Node::new(pane, self.size.0, self.size.1.saturating_sub(1)));
        tab.order = vec![pane];
        tab.focus = Some(pane);
        self.put_tab(tab, None)
    }

    /// Whether the session in front has a window with a pane in it.
    pub fn has_windows(&self) -> bool { self.tabs.iter().any(|t| t.root.is_some()) }

    /// Whether this client has a session of its own: any but the desk's, and the one it started
    /// in only once it has a window (a headless client goes when it has none).
    pub fn holds_sessions(&self) -> bool {
        let real = |id: u32, desk: bool, windows: bool| !desk && (id != 0 || windows);
        real(self.session_id, self.session_desk, self.has_windows()) || self.sessions.iter().any(|s| real(s.id, s.desk, s.tabs.iter().any(|t| t.root.is_some())))
    }

    /// tmux's break-pane: the pane becomes a window of its own (keeping its id), at the first
    /// free index or `num`; -d: not gone to.
    pub fn break_pane(&mut self, src: u64, name: Option<String>, num: Option<usize>, detached: bool) -> Result<(), String> {
        let Some(from) = self.tabs.iter().position(|t| t.panes().contains(&src)) else { return Err("can't find pane".into()) };
        if self.tabs[from].panes().len() < 2 { return Err("can't break with only one pane".into()) }
        self.renumber();
        let n = match num { Some(n) => { if self.tab_by_num(n).is_some() { return Err(format!("index in use: {n}")) } n } None => self.free_num() };
        let back = self.tabs[self.active].id.clone();
        let point = self.tabs[from].points.get(&src).copied();
        self.unhook_pane(src);
        // layout_close_pane in the window it leaves.
        self.layout_changed(from);
        let label = name.clone().or_else(|| self.panes.get(&src).and_then(|p| self.fleet.agent(&p.machine_id, &p.agent_id)).map(|a| a.name.clone())).unwrap_or_else(|| "tab".into());
        let mut tab = Tab::new(&label);
        tab.named = name.is_some();
        tab.root = Some(Node::new(src, self.size.0, self.size.1.saturating_sub(1)));
        tab.order = vec![src];
        tab.focus = Some(src);
        if let Some(p) = point { tab.points.insert(src, p); }
        let tab_id = tab.id.clone();
        self.nums.insert(tab_id.clone(), n);
        let at = self.tabs.iter().position(|t| self.nums.get(&t.id).map(|m| *m > n).unwrap_or(false)).unwrap_or(self.tabs.len());
        self.tabs.insert(at, tab);
        if detached {
            if let Some(i) = self.tabs.iter().position(|t| t.id == back) { self.active = i }
            // window_create: the new window is activity, flagged as it is not the current one.
            self.alert(at, ACTIVITY);
        } else {
            let prev = self.tabs.iter().position(|t| t.id == back);
            if let Some(i) = prev { self.active = i }
            self.select_tab(at);
        }
        let (machine, agent) = self.panes.get(&src).map(|p| (p.machine_id.clone(), p.agent_id.clone())).unwrap_or_default();
        self.desk_pane_added(&tab_id, &machine, &agent);
        self.sync_titles();
        self.fit_panes();
        Ok(())
    }

    fn split_focused(&mut self, id: u64, dir: Dir) -> bool {
        let focus = self.focused();
        let body = self.body();
        let active = self.active;
        self.fit_panes_of(active);
        let tab = self.tab_mut();
        let placed = match (tab.root.as_mut(), focus) {
            (Some(root), Some(focus)) => root.split(focus, id, dir),
            _ => { tab.root = Some(Node::new(id, body.width, body.height)); true }
        };
        if placed { tab.add_pane(id, focus, false, false); tab.set_active(id) }
        placed
    }

    /// Wide tiles split left|right, tall ones top/bottom — the way a tiling window manager does.
    pub fn smart_dir(&self) -> Dir {
        let Some(focus) = self.focused() else { return Dir::Horizontal };
        let rect = self.rects.iter().find(|(id, _)| *id == focus).map(|(_, r)| *r).unwrap_or(self.body());
        if rect.width as f32 >= rect.height as f32 * 2.2 { Dir::Horizontal } else { Dir::Vertical }
    }

    fn name_tab_after_first(&mut self) {
        let tab = &self.tabs[self.active];
        if tab.named { return }
        let Some(first) = tab.panes().first().copied() else { return };
        let name = self.panes.get(&first).and_then(|p| self.fleet.agent(&p.machine_id, &p.agent_id)).map(|a| a.name.clone());
        if let Some(name) = name { self.tabs[self.active].name = name }
    }

    pub fn sync_titles(&mut self) {
        for index in 0..self.tabs.len() {
            if self.tabs[index].named { continue }
            // tmux's automatic-rename (unless it is off): an unnamed window is called after its
            // active pane — a shell by what runs in it (automatic-rename-format: `zsh`, `vim`,
            // `[tmux]` in copy mode), a harness by its name.
            let tab_id = self.tabs[index].id.clone();
            if self.options.get("automatic-rename", &tab_id, None).as_deref() == Some("off") { continue }
            let first = self.tabs[index].focus.or_else(|| self.tabs[index].panes().first().copied());
            let Some(id) = first else { continue };
            let Some(pane) = self.panes.get(&id) else { continue };
            let Some(agent) = self.fleet.agent(&pane.machine_id, &pane.agent_id) else { continue };
            let name = if agent.engine == "terminal" && pane.fg_command.is_some() {
                let fmt = self.options.get("automatic-rename-format", &tab_id, Some(id)).unwrap_or_default();
                crate::format::expand(self, &fmt, index, Some(id), false)
            } else { agent.name.clone() };
            if !name.is_empty() { self.tabs[index].name = name }
        }
    }

    fn drop_pane(&mut self, id: u64) {
        if self.marked == Some(id) { self.marked = None }
        self.pipes.remove(&id);
        if let Some(pane) = self.panes.remove(&id) {
            if let (Some(stream), Some(link)) = (pane.stream, self.links.get(&pane.machine_id).and_then(|s| s.link.clone())) {
                link.send("terminal_close", json!({ "streamId": stream.to_string() }));
            }
        }
    }

    /// A shell hn made (new-window, a split, the one it started with) goes when its pane is
    /// killed, as tmux kills the pane's shell; an agent keeps running.
    fn end_shell(&mut self, id: u64) {
        let Some(key) = self.panes.get(&id).map(|p| (p.machine_id.clone(), p.agent_id.clone())).filter(|k| self.shells.remove(k)) else { return };
        if let Some(link) = self.link(&key.0) {
            let agent_id = key.1;
            self.spawn(async move { link.rpc("agent_delete", json!({ "agentId": agent_id }), Duration::from_secs(30)).await }, |_, _| {});
        }
    }

    pub fn close_pane(&mut self, id: u64) {
        let Some(index) = self.tabs.iter().position(|t| t.panes().contains(&id)) else { return };
        let agent = self.panes.get(&id).map(|p| (p.machine_id.clone(), p.agent_id.clone()));
        self.end_shell(id);
        let tab = &mut self.tabs[index];
        tab.lose(id);
        tab.root = tab.root.take().and_then(|root| root.remove(id));
        tab.zoomed = false;
        let tab_id = tab.id.clone();
        self.drop_pane(id);
        if let Some((machine, agent)) = agent { self.desk_op(json!({ "op": "pane.remove", "tabId": tab_id, "machineId": machine, "agentId": agent })) }
        // A window whose last pane went goes too — the last one ending hn, as tmux ends.
        if self.tabs[index].root.is_none() { self.close_tab(index) }
        // layout_close_pane: the window's other panes take the room.
        else { self.layout_changed(index) }
        self.sync_titles();
        self.fit_panes();
    }

    pub fn close_tab(&mut self, index: usize) {
        if index >= self.tabs.len() { return }
        // session_detach: closing the current window goes to the last one (session_last), else
        // the one before it by number, round to the highest (session_previous).
        if index == self.active && self.tabs.len() > 1 {
            let last = self.lastw.first().and_then(|id| self.tabs.iter().position(|t| &t.id == id)).filter(|p| *p != index);
            let to = last.unwrap_or(if index > 0 { index - 1 } else { self.tabs.len() - 1 });
            self.select_tab(to);
        }
        let tab = self.tabs.remove(index);
        self.lastw.retain(|id| *id != tab.id);
        // A window of a session not in front (a command there): notify_changes does not see it.
        let unlinked = self.swap_back.is_some_and(|b| b != self.session_id).then(|| (self.session_id, self.session_name(), tab.wid, tab.name.clone()));
        let unlinked = |app: &mut App| if let Some((sid, name, wid, w)) = unlinked { crate::commands::notify_session(app, "window-unlinked", sid, &name, Some((wid, w))) };
        for id in tab.panes() { self.end_shell(id); self.drop_pane(id) }
        if tab.on_desk { self.desk_op(json!({ "op": "tab.close", "id": tab.id })) }
        // The last window gone: the session is over (tmux's `[exited]` when it was the last).
        if self.tabs.is_empty() {
            self.tabs.push(Tab::new("home"));
            self.active = 0;
            // session_destroy: session-closed, then its windows unlinked.
            self.notify_closed();
            unlinked(self);
            self.session_gone_quiet();
            self.fit_panes();
            return;
        }
        if index < self.active || self.active >= self.tabs.len() { self.active = self.active.saturating_sub(1).min(self.tabs.len() - 1) }
        unlinked(self);
        self.fit_panes();
    }

    /// The event hooks (notify.c) for what changed since they were last told: windows unlinked,
    /// linked and renamed, a layout changed, the active pane of a window, the current window,
    /// pane focus (the current window's active pane, while the terminal has focus and no menu is
    /// over it), a pane entering or leaving a mode, the session renamed. The first look only
    /// takes note.
    pub fn notify_changes(&mut self) {
        // tmux's CLIENT_FOCUSED: set when the client attaches; only focus-events brings the
        // terminal's focus reports that clear and set it again.
        let focus_events = self.options.get("focus-events", "", None).as_deref() == Some("on");
        let client = !focus_events || self.terminal_focused;
        let mut now = HooksSeen {
            ready: true,
            session_id: self.session_id,
            windows: self.tabs.iter().map(|t| (t.id.clone(), t.wid, t.name.clone(), t.focus, t.root.as_ref().map(|r| r.to_tmux()).unwrap_or_default())).collect(),
            current: self.tabs.get(self.active).map(|t| t.id.clone()),
            client,
            modes: self.panes.values().filter(|p| p.in_mode()).map(|p| p.id).collect(),
            focused: self.hooks_seen.focused.clone(),
        };
        let before = std::mem::replace(&mut self.hooks_seen, now.clone());
        // Another session in front: client-session-changed, and its windows are not new.
        if before.ready && before.session_id != now.session_id {
            crate::commands::notify(self, "client-session-changed", Some(self.active), None);
            return;
        }
        if !before.ready {
            // The client attached (server_client_set_session): the current pane takes focus.
            if let Some(p) = self.focused() { self.update_focus(p, &mut now.focused, false) }
            self.hooks_seen.focused = now.focused;
            return;
        }
        let at = |app: &App, id: &str| app.tabs.iter().position(|t| t.id == id);
        for (id, wid, name, focus, _) in before.windows.iter().filter(|w| !now.windows.iter().any(|n| n.0 == w.0)) {
            let _ = (id, focus);
            crate::commands::notify_gone(self, "window-unlinked", *wid, name);
        }
        for (id, ..) in now.windows.iter().filter(|w| !before.windows.iter().any(|b| b.0 == w.0)) {
            if let Some(w) = at(self, id) { crate::commands::notify(self, "window-linked", Some(w), None) }
        }
        for (id, _, name, focus, layout) in now.windows.iter() {
            let Some(old) = before.windows.iter().find(|b| &b.0 == id) else { continue };
            let Some(w) = at(self, id) else { continue };
            if &old.2 != name { crate::commands::notify(self, "window-renamed", Some(w), None) }
            let _ = layout;
            if &old.3 != focus && old.3.is_some() { crate::commands::notify(self, "window-pane-changed", Some(w), None) }
        }
        if before.current != now.current && before.current.is_some() { crate::commands::notify(self, "session-window-changed", Some(self.active), None) }
        // Pane focus (window_pane_update_focus), where tmux looks again: a window's active pane
        // that changed and a window that became current only with focus-events; a window whose
        // active pane went away (window_lost_pane), and the client's own focus, always.
        let mut focused = now.focused.clone();
        focused.retain(|p| self.panes.contains_key(p));
        let old_window_active = |id: &str| before.windows.iter().find(|w| w.0 == id).and_then(|w| w.3);
        if before.current != now.current && focus_events {
            if let Some(p) = before.current.as_deref().and_then(old_window_active) { self.update_focus(p, &mut focused, true) }
            if let Some(p) = self.focused() { self.update_focus(p, &mut focused, true) }
        }
        for (id, _, _, focus, _) in now.windows.iter() {
            let Some(old) = before.windows.iter().find(|b| &b.0 == id).and_then(|b| b.3) else { continue };
            let Some(new) = *focus else { continue };
            if old == new { continue }
            // window_lost_pane: the active pane left this window (closed, or moved to another).
            let lost = !self.tabs.iter().find(|t| &t.id == id).map(|t| t.panes().contains(&old)).unwrap_or(false);
            if lost {
                let then = before.current.as_deref().and_then(|c| self.tabs.iter().position(|t| t.id == c)).unwrap_or(self.active);
                self.update_focus_in(new, &mut focused, true, then)
            }
            else if focus_events { self.update_focus(old, &mut focused, true); self.update_focus(new, &mut focused, true) }
        }
        if before.client != now.client { if let Some(p) = self.focused() { self.update_focus(p, &mut focused, true) } }
        self.hooks_seen.focused = focused;
        let changed: Vec<u64> = now.modes.iter().filter(|p| !before.modes.contains(p)).chain(before.modes.iter().filter(|p| !now.modes.contains(p))).copied().filter(|p| self.panes.contains_key(p)).collect();
        for p in changed {
            let w = self.tabs.iter().position(|t| t.panes().contains(&p));
            crate::commands::notify(self, "pane-mode-changed", w, Some(p));
        }
    }

    /// notify_window("window-layout-changed"), where tmux calls it: each preset (layout-set.c),
    /// a layout string applied, select-layout's own after either, every resize
    /// (layout_resize_layout), zoom and unzoom, a pane split in (spawn_pane) or closed
    /// (layout_close_pane), swap-pane and join-pane in each window.
    pub fn layout_changed(&mut self, t: usize) { crate::commands::notify(self, "window-layout-changed", Some(t), None) }

    /// window_pane_update_focus: [pane] is focused when it is the current window's active pane,
    /// the client has focus and no menu or popup is over it; a pane that gains or loses that
    /// fires pane-focus-in or pane-focus-out ([notify]), its flag kept in [focused].
    fn update_focus(&mut self, pane: u64, focused: &mut Vec<u64>, notify: bool) { let current = self.active; self.update_focus_in(pane, focused, notify, current) }

    /// window_pane_update_focus with [current] the window current when tmux looks (a pane lost
    /// before break-pane goes to its new window is looked at while the old one still is).
    fn update_focus_in(&mut self, pane: u64, focused: &mut Vec<u64>, notify: bool, current: usize) {
        let Some(w) = self.tabs.iter().position(|t| t.panes().contains(&pane)) else { return };
        let overlay = matches!(self.modal, Some(crate::modal::Modal::Menu(_)) | Some(crate::modal::Modal::Popup { .. }));
        let focus_events = self.options.get("focus-events", "", None).as_deref() == Some("on");
        let client = !focus_events || self.terminal_focused;
        let is = w == current && self.tabs[w].focus == Some(pane) && client && !overlay;
        let had = focused.contains(&pane);
        // A program that asked for focus reports (\e[?1004h) is told, as tmux writes to the pane.
        let reports = self.panes.get(&pane).map(|p| p.mode().contains(alacritty_terminal::term::TermMode::FOCUS_IN_OUT)).unwrap_or(false);
        if !is && had {
            focused.retain(|p| *p != pane);
            if reports { self.send_input(pane, b"\x1b[O") }
            if notify { crate::commands::notify(self, "pane-focus-out", Some(w), Some(pane)) }
        } else if is && !had {
            focused.push(pane);
            if reports { self.send_input(pane, b"\x1b[I") }
            if notify { crate::commands::notify(self, "pane-focus-in", Some(w), Some(pane)) }
        }
    }

    /// cmd-pipe-pane.c's child: `sh -c` [command], its stdin what [pane] prints from now on
    /// ([output], -O), what it prints typed into the pane ([input], -I), its errors dropped; the
    /// pipe closes when it ends.
    pub fn open_pipe(&mut self, pane: u64, command: &str, input: bool, output: bool) {
        use std::process::Stdio;
        use tokio::io::{AsyncReadExt, AsyncWriteExt};
        let mut c = tokio::process::Command::new("/bin/sh");
        c.arg("-c").arg(command).envs(crate::ipc::job_env())
            .stdin(if output { Stdio::piped() } else { Stdio::null() })
            .stdout(if input { Stdio::piped() } else { Stdio::null() })
            .stderr(Stdio::null());
        let mut child = match c.spawn() { Ok(c) => c, Err(e) => return self.error(format!("fork error: {e}")) };
        self.pipe_seq += 1;
        let id = self.pipe_seq;
        let out = child.stdin.take().map(|mut stdin| {
            let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel::<Vec<u8>>();
            tokio::spawn(async move { while let Some(b) = rx.recv().await { if stdin.write_all(&b).await.is_err() { break } } });
            tx
        });
        if let Some(mut stdout) = child.stdout.take() {
            let sink = self.sink.clone();
            tokio::spawn(async move {
                let mut buf = vec![0u8; 4096];
                loop {
                    match stdout.read(&mut buf).await {
                        Ok(0) | Err(_) => break,
                        Ok(n) => { let bytes = buf[..n].to_vec(); let _ = sink.send(Event::Apply(Box::new(move |app: &mut App| crate::input::send_to_pane(app, pane, bytes)))); }
                    }
                }
            });
        }
        self.spawn(async move { let _ = child.wait().await; }, move |app, _| {
            if app.pipes.get(&pane).map(|p| p.id == id).unwrap_or(false) { app.pipes.remove(&pane); }
        });
        self.pipes.insert(pane, Pipe { out, id });
    }

    /// Whatever pane you are in (the terminal focused) is read: its harness's finished turn is
    /// no longer news — every way of getting there (a key, a click, a command, the dial).
    pub fn mark_seen(&mut self) {
        if !self.terminal_focused { return }
        if let Some(f) = self.focused() { self.seen(f) }
    }

    /// cfg_show_causes: a config file's errors into the current pane's view mode, once there is
    /// a pane to show them in.
    pub fn show_causes(&mut self) {
        if self.config_causes.is_empty() || self.capture.is_some() || self.focused().is_none() { return }
        let causes = std::mem::take(&mut self.config_causes);
        if !crate::copy::print(self, &causes, false) { self.config_causes = causes }
    }

    /// The last window (the top of tmux's lastw stack): C-b l's, the - flag's.
    pub fn last_tab(&self) -> Option<&String> { self.lastw.first() }

    /// winlink_stack_push: a window to the top of the stack, once.
    pub fn lastw_push(&mut self, id: String) {
        self.lastw.retain(|x| *x != id);
        self.lastw.insert(0, id);
    }

    /// session_set_current's stack: the window chosen comes off it, the current one goes on top.
    fn lastw_leave(&mut self, to: usize) {
        let (to, from) = (self.tabs[to].id.clone(), self.tabs[self.active].id.clone());
        self.lastw.retain(|x| *x != to);
        self.lastw_push(from);
    }

    /// new-window's window at index `n` (the first free one without), in its place in the order.
    pub fn new_tab_at(&mut self, n: Option<usize>) {
        self.renumber();
        { let id = self.tabs[self.active].id.clone(); self.lastw_push(id) }
        let tab = Tab::new("home");
        let n = n.unwrap_or_else(|| self.free_num());
        self.nums.insert(tab.id.clone(), n);
        let at = self.tabs.iter().position(|t| self.nums.get(&t.id).map(|m| *m > n).unwrap_or(false)).unwrap_or(self.tabs.len());
        self.tabs.insert(at, tab);
        self.active = at;
        self.home_cursor = 0;
        self.home_order.borrow_mut().clear();
        self.fit_panes();
    }

    /// winlink_shuffle_up: the windows from index `idx` up to the first free one move up one,
    /// so `idx` is free.
    pub fn shuffle_up(&mut self, idx: usize) {
        self.renumber();
        let used: HashSet<usize> = self.nums.values().copied().collect();
        let mut last = idx;
        while used.contains(&last) { last += 1 }
        for n in (idx..last).rev() {
            if let Some(id) = self.nums.iter().find(|(_, v)| **v == n).map(|(k, _)| k.clone()) { self.nums.insert(id, n + 1); }
        }
    }

    pub fn new_tab(&mut self) {
        // tmux's new-window: the first free index; the others keep their numbers.
        self.renumber();
        { let id = self.tabs[self.active].id.clone(); self.lastw_push(id) }
        let tab = Tab::new("home");
        let n = self.free_num();
        self.nums.insert(tab.id.clone(), n);
        let at = self.tabs.iter().position(|t| self.nums.get(&t.id).map(|m| *m > n).unwrap_or(false)).unwrap_or(self.tabs.len());
        self.tabs.insert(at, tab);
        self.active = at;
        self.home_cursor = 0;
        self.home_order.borrow_mut().clear();
        self.fit_panes();
    }

    /// tmux's alerts_queue + alerts_check_*: when the window's monitor-activity / monitor-bell /
    /// monitor-silence is on, a window that is not the current one is flagged (activity and
    /// silence once until it is visited, a bell every time), and — as bell-action / activity-action
    /// / silence-action say — the terminal's bell rings or (visual-*) a message says where.
    pub fn alert(&mut self, t: usize, flag: u8) {
        let Some(tab) = self.tabs.get(t) else { return };
        let id = tab.id.clone();
        let (monitor, action, visual, word) = match flag {
            BELL => ("monitor-bell", "bell-action", "visual-bell", "Bell"),
            ACTIVITY => ("monitor-activity", "activity-action", "visual-activity", "Activity"),
            _ => ("monitor-silence", "silence-action", "visual-silence", "Silence"),
        };
        let on = self.options.get(monitor, &id, None).map(|v| v != "off" && v != "0").unwrap_or(false);
        if !on { return }
        let current = t == self.active;
        if flag != BELL && self.tabs[t].alerts & flag != 0 { return }
        if !current { self.tabs[t].alerts |= flag }
        let applies = match self.options.get(action, "", None).as_deref() { Some("any") => true, Some("current") => current, Some("other") => !current, _ => false };
        if !applies { return }
        // notify_winlink: alert-bell, alert-activity, alert-silence.
        let hook = match flag { BELL => "alert-bell", ACTIVITY => "alert-activity", _ => "alert-silence" };
        crate::commands::notify(self, hook, Some(t), None);
        let visual = self.options.get(visual, "", None).unwrap_or_default();
        if visual == "off" || visual == "both" { crate::bell() }
        if visual == "off" { return }
        let msg = if current { format!("{word} in current window") } else { format!("{word} in window {}", self.win_num(t)) };
        self.say(msg, theme::WARN);
    }

    /// monitor-silence: a window quiet that many seconds (checked on the tick).
    /// The timer runs again when it fires (alerts_reset), so a window that stays quiet is said
    /// again each time — to the current window only, the others being flagged already.
    pub fn check_silence(&mut self) {
        for t in 0..self.tabs.len() {
            let n: u64 = self.options.get("monitor-silence", &self.tabs[t].id, None).and_then(|v| v.parse().ok()).unwrap_or(0);
            if n > 0 && self.tabs[t].last_output.elapsed() >= Duration::from_secs(n) {
                self.tabs[t].last_output = Instant::now();
                self.alert(t, SILENCE)
            }
        }
    }

    pub fn select_tab(&mut self, index: usize) {
        if index < self.tabs.len() {
            // session_set_current: the window's alerts are seen, and choosing it is activity.
            self.tabs[index].alerts = 0;
            let changed = index != self.active;
            if changed { self.lastw_leave(index); self.home_order.borrow_mut().clear() }
            self.active = index;
            if changed { self.tabs[index].touch(); self.alert(index, ACTIVITY) }
            if let Some(f) = self.tabs[index].focus { self.seen(f) }
            self.fit_panes();
        }
    }

    /// Move the active tab one place left (-1) or right (+1), on the desk too.
    pub fn move_tab(&mut self, by: i32) {
        let to = self.active as i32 + by;
        if to < 0 || to as usize >= self.tabs.len() { return }
        let to = to as usize;
        self.tabs.swap(self.active, to);
        self.active = to;
        let (id, on_desk) = (self.tabs[to].id.clone(), self.tabs[to].on_desk);
        if on_desk { self.desk_op(json!({ "op": "tab.move", "id": id, "index": to })) }
    }

    pub fn rename_tab(&mut self, name: &str) { let i = self.active; self.rename_tab_at(i, name) }

    /// rename-window -t: that window.
    pub fn rename_tab_at(&mut self, index: usize, name: &str) {
        let Some(tab) = self.tabs.get_mut(index) else { return };
        tab.name = name.to_string();
        tab.named = true;
        let (id, on_desk) = (tab.id.clone(), tab.on_desk);
        // tmux: a window named by hand is no longer renamed automatically.
        self.options.windows.entry(id.clone()).or_default().insert("automatic-rename".into(), "off".into());
        if on_desk { self.desk_op(json!({ "op": "tab.rename", "id": id, "name": name, "nameIsCustom": true })) }
    }

    // ── tmux pane moves ──────────────────────────────────────────────────────

    /// The panes of a window where tmux keeps them (zoom aside), in its list order.
    pub fn pane_geoms(&self, w: usize) -> Vec<(u64, layout::Geom)> {
        let Some(tab) = self.tabs.get(w) else { return Vec::new() };
        let body = self.body();
        let mut out = Vec::new();
        if let Some(root) = tab.root.as_ref() { root.rects(body, &mut out) }
        tab.panes().into_iter().filter_map(|id| out.iter().find(|(p, _)| *p == id).map(|(_, r)| {
            let c = self.content_of(tab, *r);
            (id, layout::Geom { x: (c.x - body.x) as u32, y: (c.y - body.y) as u32, w: c.width as u32, h: c.height as u32 })
        })).collect()
    }

    /// The current window's panes as drawn (a zoomed window's one pane filling it), where their
    /// contents are in the window: tmux's xoff/yoff/sx/sy for the mouse.
    pub fn visible_geoms(&self) -> Vec<(u64, layout::Geom)> {
        let body = self.body();
        let tab = self.tab();
        tab.panes().into_iter().filter_map(|id| self.rects.iter().find(|(p, _)| *p == id).map(|(_, r)| {
            let c = self.content_of(tab, *r);
            (id, layout::Geom { x: (c.x - body.x) as u32, y: (c.y.saturating_sub(body.y)) as u32, w: c.width as u32, h: c.height as u32 })
        })).collect()
    }

    /// tmux's copy mode is a pane's: keys go to it while the active pane is in it, and to the pane
    /// when it is not (whatever other pane is in copy mode).
    pub fn sync_copy_modal(&mut self) {
        if !matches!(self.modal, None | Some(Modal::Copy { .. })) { return }
        let pane = self.focused().filter(|f| self.panes.get(f).map(|p| p.copy_top()).unwrap_or(false));
        self.modal = pane.map(|pane| Modal::Copy { pane });
    }

    /// A pane's harness at a glance (theme::state_mark): None for a plain shell or no harness.
    pub fn pane_state(&self, pane: u64) -> Option<fleet::State> {
        let p = self.panes.get(&pane)?;
        let agent = self.fleet.agent(&p.machine_id, &p.agent_id)?;
        if agent.engine == "terminal" { return None }
        Some(self.fleet.state_of(agent))
    }

    /// A window's most urgent harness state (its panes'), for the window list.
    pub fn window_state(&self, w: usize) -> Option<fleet::State> {
        let tab = self.tabs.get(w)?;
        crate::theme::most_urgent(tab.panes().into_iter().filter_map(|p| self.pane_state(p)))
    }

    /// The current pane for a command: while a mouse key's commands run, the pane under the mouse
    /// (cmd_find_from_mouse), else the active pane of the current window.
    pub fn current(&self) -> Option<(usize, u64)> {
        if let Some(found) = self.mouse_ev.as_ref().filter(|m| m.valid).and_then(|m| crate::mouse::mouse_pane(self, m)) { return Some(found) }
        // A hook's commands: the pane (window) it is about.
        if let Some((tab, pane)) = self.hook_state.as_ref().and_then(|h| h.target.clone()) {
            if let Some(w) = self.tabs.iter().position(|t| t.id == tab) { return Some((w, pane)) }
        }
        self.focused().map(|f| (self.active, f))
    }

    /// resize-pane -M's drag: the borders at (lx, ly) follow the mouse to (x, y).
    pub fn drag_border(&mut self, w: usize, lx: u32, ly: u32, x: u32, y: u32) {
        self.fit_panes_of(w);
        let moved = self.tabs.get_mut(w).and_then(|t| t.root.as_mut()).map(|r| r.drag_border(lx, ly, x, y)).unwrap_or(false);
        if moved { self.fit_panes(); self.layout_changed(w) }
    }

    /// The pane that way from `from`, as tmux's select-pane -L/-R/-U/-D finds it.
    pub fn pane_toward(&self, w: usize, from: u64, toward: Toward) -> Option<u64> {
        let tab = self.tabs.get(w)?;
        let body = self.body();
        let size = tab.root.as_ref().map(|r| r.size()).unwrap_or((body.width, body.height));
        layout::find_toward(&self.pane_geoms(w), from, toward, (size.0 as u32, size.1 as u32), self.pane_status(tab), &|p| tab.points.get(&p).copied().unwrap_or(0))
    }

    /// select-pane -L/-R/-U/-D: the pane that way becomes the active one; a zoomed window is
    /// unzoomed (-Z: the new pane is zoomed instead).
    pub fn select_toward(&mut self, toward: layout::Toward, keep_zoom: bool) {
        let Some(focus) = self.focused() else { return };
        let w = self.active;
        let Some(next) = self.pane_toward(w, focus, toward) else { return };
        if next == focus { return }
        let zoomed = self.tabs[w].zoomed;
        self.focus_pane(w, next);
        self.tabs[w].zoomed = zoomed && keep_zoom;
        self.fit_panes();
    }

    pub fn select_pane_index(&mut self, index: usize) {
        if let Some(id) = self.tab().panes().get(index).copied() { let tab = self.active; self.focus_pane(tab, id) }
    }

    /// last-pane (select-pane -l): the pane active before this one — with no such pane in a
    /// window of two, the other one, as tmux has it; -Z keeps a zoomed window zoomed.
    pub fn select_last(&mut self, w: usize, keep_zoom: bool) {
        let Some(tab) = self.tabs.get(w) else { return };
        let ids = tab.panes();
        let other = || if ids.len() == 2 { ids.iter().copied().find(|p| Some(*p) != tab.focus) } else { None };
        let Some(last) = tab.last_focus().filter(|l| ids.contains(l)).or_else(other) else { self.error("no last pane"); return };
        let zoomed = tab.zoomed;
        if w == self.active { self.focus_pane(w, last) } else { self.tabs[w].set_active(last) }
        self.tabs[w].zoomed = zoomed && keep_zoom;
        self.fit_panes();
    }

    /// `resize-pane -L/-R/-U/-D n`: n cells, the way tmux counts them.
    /// resize-pane -L/-R/-U/-D: the pane's nearest border in that direction moves `cells`.
    pub fn resize_pane(&mut self, tab: usize, pane: u64, dir: Dir, cells: i32) {
        self.fit_panes_of(tab);
        let before = self.tabs.get(tab).and_then(|t| t.root.as_ref()).map(|r| r.to_tmux());
        if let Some(root) = self.tabs.get_mut(tab).and_then(|t| t.root.as_mut()) { root.resize_pane(pane, dir, cells, true); }
        self.fit_panes();
        if self.tabs.get(tab).and_then(|t| t.root.as_ref()).map(|r| r.to_tmux()) != before { self.layout_changed(tab) }
    }

    /// A window's cells at the client's size before they are moved.
    fn fit_panes_of(&mut self, tab: usize) -> bool {
        let body = self.body();
        let status = self.tabs.get(tab).map(|t| self.pane_status(t)).unwrap_or_default();
        match self.tabs.get_mut(tab).and_then(|t| t.root.as_mut()) {
            Some(root) => { root.status = status; if root.size() != (body.width, body.height) { root.resize(body.width, body.height) } true }
            None => false,
        }
    }

    /// resize-pane -x/-y: the pane made that many cells wide or lines tall (its title row, when
    /// the window shows them, on top).
    pub fn size_pane(&mut self, tab: usize, pane: u64, dir: Dir, cells: u16) {
        self.fit_panes_of(tab);
        // cmd-resize-pane.c: -y counts the status line of the pane that gives a row to it — the
        // top pane's with pane-border-status top, the bottom one's with bottom.
        let (status, g) = match self.tabs.get(tab) { Some(t) => (self.pane_status(t), self.pane_geoms(tab).into_iter().find(|(id, _)| *id == pane).map(|(_, g)| g)), None => return };
        let sy = self.body().height as u32;
        let own_row = match (status, g) { (layout::Status::Top, Some(g)) => g.y == 1, (layout::Status::Bottom, Some(g)) => g.y + g.h + 1 == sy, _ => false };
        let cells = if dir == Dir::Vertical && own_row { cells + 1 } else { cells };
        let before = self.tabs.get(tab).and_then(|t| t.root.as_ref()).map(|r| r.to_tmux());
        if let Some(root) = self.tabs.get_mut(tab).and_then(|t| t.root.as_mut()) { root.resize_pane_to(pane, dir, cells as u32); }
        self.fit_panes();
        // layout_resize_pane_to returns early (nothing notified) when the pane has no parent to
        // resize it in that way.
        if self.tabs.get(tab).and_then(|t| t.root.as_ref()).map(|r| r.to_tmux()) != before { self.layout_changed(tab) }
    }

    /// tmux's swap-pane in one window: the two trade cells and places in the list; the target
    /// (`dst`) is the active pane after, or with -d the active place stays where it was.
    /// Zoom goes unless -Z.
    pub fn swap_panes(&mut self, w: usize, src: u64, dst: u64, detached: bool, keep_zoom: bool) {
        let Some(tab) = self.tabs.get_mut(w) else { return };
        let mut order = tab.panes();
        let (Some(i), Some(j)) = (order.iter().position(|p| *p == src), order.iter().position(|p| *p == dst)) else { return };
        if src == dst { return }
        order.swap(i, j);
        tab.order = order;
        if let Some(root) = tab.root.as_mut() { root.swap(src, dst) }
        if !detached { tab.set_active(dst) }
        else if tab.focus == Some(src) { tab.set_active(dst) }
        else if tab.focus == Some(dst) { tab.set_active(src) }
        tab.zoomed &= keep_zoom;
        self.sync_titles();
        self.fit_panes();
        self.layout_changed(w);
    }

    /// swap-pane across two windows: each pane takes the other's cell and place in its list;
    /// each window's active pane is the one that came in (-d: only where the active one left).
    pub fn swap_across(&mut self, src: (usize, u64), dst: (usize, u64), detached: bool, keep_zoom: bool) {
        let ((sw, sp), (dw, dp)) = (src, dst);
        if sw == dw || sw >= self.tabs.len() || dw >= self.tabs.len() { return }
        let (spoint, dpoint) = (self.tabs[sw].points.remove(&sp), self.tabs[dw].points.remove(&dp));
        if let Some(p) = spoint { self.tabs[dw].points.insert(sp, p); }
        if let Some(p) = dpoint { self.tabs[sw].points.insert(dp, p); }
        for (w, from, to) in [(sw, sp, dp), (dw, dp, sp)] {
            let tab = &mut self.tabs[w];
            let mut order = tab.panes();
            for p in order.iter_mut() { if *p == from { *p = to } }
            tab.order = order;
            if let Some(root) = tab.root.as_mut() { root.replace(from, to); }
            tab.last.retain(|p| *p != from);
            if tab.focus == Some(from) { tab.focus = Some(to) } else if !detached { tab.set_active(to) }
            tab.zoomed &= keep_zoom;
        }
        // The desk: each harness leaves its window for the other's.
        let (st, dt) = (self.tabs[sw].id.clone(), self.tabs[dw].id.clone());
        for (tab, pane, gone) in [(&dt, sp, &st), (&st, dp, &dt)] {
            if let Some((m, a)) = self.panes.get(&pane).map(|x| (x.machine_id.clone(), x.agent_id.clone())) {
                self.desk_op(json!({ "op": "pane.remove", "tabId": gone, "machineId": m, "agentId": a }));
                self.desk_pane_added(tab, &m, &a);
            }
        }
        self.sync_titles();
        self.fit_panes();
        self.layout_changed(sw);
        self.layout_changed(dw);
    }

    /// `rotate-window` (C-o): the list turns (the first pane to the end; -D the last to the
    /// start) and each pane takes the cell of the one now before it; the active place stays.
    pub fn rotate(&mut self, w: usize, by: i64, keep_zoom: bool) {
        let Some(tab) = self.tabs.get_mut(w) else { return };
        let ids = tab.panes();
        let n = ids.len();
        if n < 2 { return }
        let turned: Vec<u64> = (0..n).map(|i| ids[(i as i64 + by).rem_euclid(n as i64) as usize]).collect();
        if let Some(root) = tab.root.as_mut() {
            root.relabel(&mut |old| ids.iter().position(|p| *p == old).map(|i| turned[i]).unwrap_or(old));
        }
        let at = tab.focus.and_then(|f| ids.iter().position(|p| *p == f));
        tab.order = turned.clone();
        if let Some(i) = at { tab.set_active(turned[i]) }
        tab.zoomed &= keep_zoom;
        self.sync_titles();
        self.fit_panes();
    }

    /// next-layout / previous-layout (layout_set_next/previous): tmux's seven named layouts in its
    /// order, on from the one last applied — a window that has had none starts at even-horizontal
    /// going forward, tiled going back.
    pub fn step_layout(&mut self, index: usize, next: bool) {
        let Some(tab) = self.tabs.get(index) else { return };
        let last = layout::Named::ALL.len() - 1;
        let at = match (tab.layout_at, next) {
            (None, true) => 0,
            (None, false) => last,
            (Some(at), true) => if at >= last { 0 } else { at + 1 },
            (Some(at), false) => if at == 0 { last } else { at - 1 },
        };
        self.arrange_tab(index, layout::Named::ALL[at]);
    }

    pub fn apply_preset(&mut self, preset: Preset) { let i = self.active; self.apply_preset_at(i, preset) }

    /// select-layout -t: that window's panes in that shape.
    pub fn apply_preset_at(&mut self, index: usize, preset: Preset) {
        self.arrange_tab(index, layout::Named::of(preset));
        let Some(tab) = self.tabs.get_mut(index) else { return };
        let ids = tab.panes();
        // The same shape on every window: the desk's layout keys presets by pane count.
        if tab.on_desk && !ids.is_empty() {
            if !tab.layout.is_object() { tab.layout = json!({}) }
            if !tab.layout.get("presets").map(Value::is_object).unwrap_or(false) { tab.layout["presets"] = json!({}) }
            tab.layout["presets"][ids.len().to_string()] = json!(preset_to_desk(preset, ids.len()));
            let op = json!({ "op": "tab.layout", "id": tab.id, "layout": tab.layout });
            self.desk_op(op);
        }
        self.fit_panes();
    }

    // ── the desk: tabs shared with every window on the account ─────────────────

    fn load_desk(&mut self) {
        self.desk_loaded = true;
        if self.desk_mode == DeskMode::Off { self.desk_answered = true; self.maybe_start_shell(); return }
        self.fetch_desk();
    }

    /// tmux starts in a shell: when hn opens with no window of its own to show (the desk had
    /// none, or there is no desk), window 0 is a shell on this computer, in the folder hn was
    /// started in — once, when the desk has answered and this computer's daemon is connected.
    /// Until then (or if it never connects: not signed in) the window shows what it can.
    pub fn maybe_start_shell(&mut self) {
        if self.shell_asked || !self.desk_answered || self.capture.is_some() { return }
        // A headless client makes only the sessions it is asked for.
        if self.headless { self.shell_asked = true; return }
        // `hn new -s work` (a session besides the desk's): made here, with its shell.
        if self.start_session.as_ref().map(|s| s.create && self.session_alias.as_deref() != s.name.as_deref()).unwrap_or(false) {
            if self.link(&self.fleet.local_id).is_none() { return }
            let start = self.start_session.take().unwrap_or_default();
            self.shell_asked = true;
            if let Err(e) = self.new_session(start.name.as_deref(), start.window.as_deref(), start.cwd, start.command, false) { self.error(e) }
            return;
        }
        if !(self.tabs.len() == 1 && self.tabs[0].root.is_none()) { self.shell_asked = true; return }
        if self.link(&self.fleet.local_id).is_none() { return }
        self.shell_asked = true;
        // The desk's first shell: where hn was started (-c: where it was asked to), running what
        // `hn new` asked for.
        let start = self.start_session.take().unwrap_or_default();
        let cwd = start.cwd.or_else(|| std::env::current_dir().ok().map(|d| d.display().to_string()));
        crate::input::new_shell_from(self, None, Placement::Auto(None), cwd, start.command);
    }

    fn fetch_desk(&mut self) {
        if self.desk_inflight > 0 { self.desk_stale = true; return }
        let port = self.port;
        self.spawn(async move { http_json(port, "GET", "/api/desk", None).await }, |app, desk| {
            if app.desk_inflight > 0 { app.desk_stale = true; return }
            if let Ok(desk) = desk { app.apply_desk(&desk) }
            if !app.desk_answered { app.desk_answered = true; app.maybe_start_shell() }
        });
    }

    /// Reconcile tabs to the desk: new tabs appear, closed ones go, panes follow. What a window
    /// keeps for itself (active tab, focus, zoom, sizes) is left alone.
    fn apply_desk(&mut self, desk: &Value) {
        // The desk is one session's windows: that session in front while they are reconciled.
        if !self.session_desk {
            let Some(id) = self.sessions.iter().find(|s| s.desk).map(|s| s.id) else { return };
            let back = self.session_id;
            self.swap_session(id);
            self.apply_desk(desk);
            self.swap_session(back);
            self.fit_panes();
            return;
        }
        let revision = desk.get("revision").and_then(Value::as_i64).unwrap_or(0);
        if revision <= self.desk_revision { return }
        self.desk_revision = revision;
        let Some(rows) = desk.get("tabs").and_then(Value::as_array) else { return };
        let first_load = self.tabs.iter().all(|t| !t.on_desk);
        let mut seen = Vec::new();
        for row in rows {
            let id = row.get("id").and_then(Value::as_str).unwrap_or("").to_string();
            let panes: Vec<(String, String)> = row.get("panes").and_then(Value::as_array).map(|a| a.iter().filter_map(|p| Some((p.get("machineId")?.as_str()?.to_string(), p.get("agentId")?.as_str()?.to_string()))).collect()).unwrap_or_default();
            if id.is_empty() || panes.is_empty() { continue }
            seen.push(id.clone());
            let name = row.get("name").and_then(Value::as_str).unwrap_or("tab").to_string();
            let named = row.get("nameIsCustom").and_then(Value::as_bool).unwrap_or(false);
            let preset = preset_from_desk(row.pointer(&format!("/layout/presets/{}", panes.len())).and_then(Value::as_str).unwrap_or(""), panes.len());
            let layout_doc = row.get("layout").cloned().unwrap_or(json!({}));
            match self.tabs.iter().position(|t| t.id == id) {
                Some(index) => {
                    let tab = &mut self.tabs[index];
                    if named || !tab.named { tab.name = name; tab.named = named }
                    tab.on_desk = true;
                    let relayout = tab.layout != layout_doc;
                    tab.layout = layout_doc;
                    if relayout && missing_is_empty(&tab.panes(), &panes, &self.panes) {
                        let ids = tab.panes();
                        let (w, h) = (self.size.0, self.size.1.saturating_sub(2));
                        tab.root = layout::arrange(layout::Named::of(preset), &ids, w, h, layout::Status::Top, DESK_MAIN, ("0", "0"));
                        continue;
                    }
                    let have: Vec<(u64, (String, String))> = tab.panes().into_iter().filter_map(|pid| self.panes.get(&pid).map(|p| (pid, (p.machine_id.clone(), p.agent_id.clone())))).collect();
                    let missing: Vec<&(String, String)> = panes.iter().filter(|want| !have.iter().any(|(_, k)| k == *want)).collect();
                    let extra: Vec<u64> = have.iter().filter(|(_, k)| !panes.contains(k)).map(|(pid, _)| *pid).collect();
                    if missing.is_empty() && extra.is_empty() { continue }
                    for pid in &extra {
                        let tab = &mut self.tabs[index];
                        tab.root = tab.root.take().and_then(|r| r.remove(*pid));
                        self.drop_pane(*pid);
                    }
                    let mut new_ids = Vec::new();
                    for (m, a) in missing { new_ids.push(self.new_pane(m, a)) }
                    let tab = &mut self.tabs[index];
                    let mut ids = tab.panes();
                    ids.extend(new_ids.iter().copied());
                    let (w, h) = (self.size.0, self.size.1.saturating_sub(2));
                    tab.root = layout::arrange(layout::Named::of(preset), &ids, w, h, layout::Status::Top, DESK_MAIN, ("0", "0"));
                    if tab.focus.map(|f| !ids.contains(&f)).unwrap_or(true) { tab.focus = ids.first().copied() }
                }
                None => {
                    let ids: Vec<u64> = panes.iter().map(|(m, a)| self.new_pane(m, a)).collect();
                    let mut tab = Tab::new(&name);
                    tab.id = id;
                    tab.named = named;
                    tab.on_desk = true;
                    tab.layout = layout_doc;
                    let (w, h) = (self.size.0, self.size.1.saturating_sub(2));
                    tab.root = layout::arrange(layout::Named::of(preset), &ids, w, h, layout::Status::Top, DESK_MAIN, ("0", "0"));
                    tab.focus = ids.first().copied();
                    let at = rows.iter().position(|r| r.get("id").and_then(Value::as_str) == Some(tab.id.as_str())).unwrap_or(self.tabs.len()).min(self.tabs.len());
                    self.tabs.insert(at, tab);
                    if at <= self.active && !first_load { self.active += 1 }
                }
            }
        }
        // Tabs the desk no longer has — closed on another computer.
        let gone: Vec<usize> = self.tabs.iter().enumerate().filter(|(_, t)| t.on_desk && !seen.contains(&t.id)).map(|(i, _)| i).collect();
        for index in gone.into_iter().rev() {
            let tab = self.tabs.remove(index);
            self.lastw.retain(|id| *id != tab.id);
            for id in tab.panes() { self.drop_pane(id) }
            if index < self.active || self.active >= self.tabs.len() { self.active = self.active.saturating_sub(1) }
        }
        // First load: the desk's tabs replace the empty home tab we started on.
        if first_load && self.tabs.len() > 1 {
            if let Some(home) = self.tabs.iter().position(|t| t.root.is_none() && !t.on_desk) { self.tabs.remove(home); }
            self.active = 0;
        }
        if self.tabs.is_empty() { self.tabs.push(Tab::new("home")) }
        self.active = self.active.min(self.tabs.len() - 1);
        self.sync_titles();
        self.fit_panes();
    }

    fn desk_pane_added(&mut self, tab_id: &str, machine_id: &str, agent_id: &str) {
        let Some(index) = self.tabs.iter().position(|t| t.id == tab_id) else { return };
        let mut ops = Vec::new();
        if !self.tabs[index].on_desk && self.desk_mode == DeskMode::Sync && self.session_desk {
            self.tabs[index].on_desk = true;
            let tab = &self.tabs[index];
            let mut op = json!({ "op": "tab.create", "id": tab.id, "name": tab.name, "index": index });
            if tab.named { op["nameIsCustom"] = json!(true) }
            ops.push(op);
        }
        let at = self.tabs[index].panes().len().saturating_sub(1);
        ops.push(json!({ "op": "pane.add", "tabId": tab_id, "machineId": machine_id, "agentId": agent_id, "index": at }));
        self.desk_ops(ops);
    }

    pub fn desk_op(&mut self, op: Value) { self.desk_ops(vec![op]) }

    /// Send ops as one write. The reply is the whole desk, other windows' changes included; it is
    /// reconciled only when none of this window's writes are still out — reconciling to a desk that
    /// has the tab but not yet its pane would close the tab this window just made.
    pub fn desk_ops(&mut self, ops: Vec<Value>) {
        if self.desk_mode != DeskMode::Sync || ops.is_empty() { return }
        let port = self.port;
        self.desk_inflight += 1;
        self.spawn(async move { http_json(port, "POST", "/api/desk/ops", Some(&json!({ "ops": ops }))).await }, |app, reply| {
            app.desk_inflight = app.desk_inflight.saturating_sub(1);
            if app.desk_inflight > 0 { app.desk_stale = true; return }
            match reply {
                Ok(desk) => app.apply_desk(&desk),
                Err(_) => app.fetch_desk(),
            }
            if std::mem::take(&mut app.desk_stale) { app.fetch_desk() }
        });
    }

    /// The outer terminal's title, as set-titles and set-titles-string say (hn's: the harnesses
    /// waiting on you and the one in front, so a terminal tab says what is in it); none with
    /// set-titles off, as tmux leaves the terminal's own.
    pub fn window_title(&self) -> Option<String> {
        if self.options.get("set-titles", "", None).as_deref() != Some("on") { return None }
        let fmt = self.options.get("set-titles-string", "", None).unwrap_or_default();
        Some(crate::format::expand(self, &fmt, self.active, self.focused(), true))
    }

    // ── the loop's slow tick ─────────────────────────────────────────────────

    /// What the daemons know of each harness beyond its row, asked a few at a time, the focused
    /// pane's first, then in the order they need you: its last recap (agent_recent — so what it did
    /// is there after hn starts again), and the pull request for its branch (git_pull_request, at
    /// most every five minutes; none for main or master).
    fn enrich(&mut self) {
        const AT_ONCE: u32 = 4;
        // The accounts' rate limits, from each machine that holds one (every five minutes; the
        // first a few seconds in).
        if self.started.elapsed() > Duration::from_secs(4) && self.usage_checked.map(|t| t.elapsed() > Duration::from_secs(300)).unwrap_or(true) {
            self.usage_checked = Some(Instant::now());
            let ids: Vec<String> = self.fleet.machines.iter().filter(|m| m.usable()).map(|m| m.id.clone()).collect();
            for id in ids {
                let Some(link) = self.link(&id) else { continue };
                self.spawn(async move { link.rpc("usage_read", json!({}), Duration::from_secs(30)).await }, move |app, reply| {
                    let Ok(reply) = reply else { return };
                    let readings: Vec<fleet::Usage> = reply.get("providers").and_then(Value::as_array).map(|p| p.iter().filter_map(fleet::usage_from).collect()).unwrap_or_default();
                    app.usage.insert(id, readings);
                });
            }
        }
        if self.enriching >= AT_ONCE { return }
        let now = Instant::now();
        let focused = self.focused().and_then(|f| self.panes.get(&f)).map(|p| (p.machine_id.clone(), p.agent_id.clone()));
        let rest: Vec<(String, String)> = self.fleet.ranked().into_iter().map(|a| a.key()).filter(|k| Some(k) != focused.as_ref()).collect();
        let order: Vec<(String, String)> = focused.into_iter().chain(rest).collect();
        for (machine, agent_id) in order {
            if self.enriching >= AT_ONCE { break }
            let Some(link) = self.link(&machine) else { continue };
            let Some(a) = self.fleet.agent(&machine, &agent_id) else { continue };
            let live = !matches!(a.status.as_str(), "stopped" | "offline");
            let recap = !a.recap_asked && a.did.is_none() && a.engine != "terminal";
            let pr = live && !a.branch.is_empty() && !matches!(a.branch.as_str(), "main" | "master" | "trunk" | "develop") && a.pr_checked.map(|t| now.duration_since(t) > Duration::from_secs(300)).unwrap_or(true);
            if recap {
                if let Some(a) = self.fleet.agents.get_mut(&(machine.clone(), agent_id.clone())) { a.recap_asked = true }
                self.enriching += 1;
                let (m, id, link) = (machine.clone(), agent_id.clone(), link.clone());
                self.spawn(async move { link.rpc("agent_recent", json!({ "agentId": id, "n": 1 }), Duration::from_secs(15)).await }, move |app, reply| {
                    app.enriching = app.enriching.saturating_sub(1);
                    let Ok(reply) = reply else { return };
                    let Some(a) = app.fleet.agents.get_mut(&(m.clone(), agent_id_of(&reply).unwrap_or_default())) else { return };
                    let recap = reply.pointer("/events/0").and_then(|e| e.get("recap").or_else(|| e.get("text")).and_then(Value::as_str)).and_then(fleet::first_line);
                    if a.did.is_none() { a.did = recap }
                    let full = reply.pointer("/events/0").and_then(|e| e.get("fullText").or_else(|| e.get("text")).and_then(Value::as_str)).unwrap_or("");
                    if a.last_text.is_empty() { a.last_text = full.trim().to_string() }
                    let ask = reply.pointer("/asks/0").and_then(|x| x.as_str().map(str::to_string).or_else(|| x.get("text").and_then(Value::as_str).map(str::to_string)));
                    if a.asked.is_none() { a.asked = ask.as_deref().and_then(fleet::first_line) }
                });
            }
            if pr && self.enriching < AT_ONCE {
                if let Some(a) = self.fleet.agents.get_mut(&(machine.clone(), agent_id.clone())) { a.pr_checked = Some(now) }
                self.enriching += 1;
                let (m, id) = (machine.clone(), agent_id.clone());
                self.spawn(async move { link.rpc("git_pull_request", json!({ "agentId": id }), Duration::from_secs(30)).await }, move |app, reply| {
                    app.enriching = app.enriching.saturating_sub(1);
                    let Ok(reply) = reply else { return };
                    let Some(a) = app.fleet.agents.get_mut(&(m, agent_id.clone())) else { return };
                    a.pr = match reply.get("status").and_then(Value::as_str) {
                        Some("found") => Some(fleet::Pr { number: reply.get("number").and_then(Value::as_u64).unwrap_or(0), state: reply.get("state").and_then(Value::as_str).unwrap_or("").to_string(), url: reply.get("url").and_then(Value::as_str).unwrap_or("").to_string() }),
                        Some("none") => None,
                        _ => a.pr.take(),
                    };
                });
            }
        }
    }

    pub fn on_tick(&mut self) {
        self.tick += 1;
        self.enrich();
        self.maybe_start_shell();
        self.release_waiting();
        crate::dial::tick(self);
        if self.tick % 4 == 0 { self.check_silence() }
        // What the panes on screen run (vim? a build?) moves as you work: asked every two seconds.
        // …and every other window's active pane, which names that window (automatic-rename).
        if self.tick % 8 == 4 {
            let mut ids = self.tab().panes();
            ids.extend(self.tabs.iter().filter_map(|t| t.focus).filter(|f| !ids.contains(f)).collect::<Vec<_>>());
            for p in ids { self.refresh_pane_info(p) }
        }
        // display-panes goes away after display-panes-time, as in tmux.
        if matches!(self.modal, Some(crate::modal::Modal::DisplayPanes { until }) if Instant::now() >= until) { self.modal = None }
        self.orphans.retain(|_, (at, _)| at.elapsed() < Duration::from_secs(10));
        for pane in self.panes.values_mut() { pane.settle_predictions() }
        let now = Instant::now();
        for agent in self.fleet.agents.values_mut() {
            if agent.working && agent.last_beat.map(|t| now.duration_since(t) > Duration::from_secs(90)).unwrap_or(true) { agent.working = false }
        }
        let due: Vec<String> = self.links.iter().filter(|(_, s)| s.link.is_none() && s.retry_at.map(|t| t <= now).unwrap_or(false)).map(|(id, _)| id.clone()).collect();
        for id in due {
            if let Some(state) = self.links.get_mut(&id) { state.retry_at = None }
            if id == self.fleet.local_id || self.fleet.machine(&id).map(Machine::online).unwrap_or(false) { self.connect(&id) }
        }
        if self.tick % 120 == 0 { self.refresh_machines() }
        if self.tick % 80 == 40 { self.fleet.save_cache() }
        if self.tick % 20 == 10 { self.save_seen() }
        if self.tick % 240 == 0 { let ids: Vec<String> = self.links.keys().cloned().collect(); for id in ids { self.relist(&id) } }
        if self.toast.as_ref().map(|t| now.duration_since(t.2) > Duration::from_secs(4)).unwrap_or(false) { self.toast = None }
        if let Some(Modal::Picker { picker, .. }) = &mut self.modal {
            if picker.flash.as_ref().map(|f| now.duration_since(f.1) > Duration::from_secs(4)).unwrap_or(false) { picker.flash = None }
        }
    }

}

/// The desktop's preset ids (desktop/lib/state/pane_preset.dart, enum names) → our shapes.
/// A desk tab's main pane, as the desktop app draws it: half the window (its presets' main tile is
/// .5 wide or tall), not tmux's main-pane-width of 80 cells, which a narrow terminal can't spare.
const DESK_MAIN: (&str, &str) = ("50%", "50%");

fn preset_from_desk(id: &str, count: usize) -> Preset {
    match id {
        "columns" | "cols2" | "cols3" | "cols4" | "cols5" | "balanced2" | "balanced3" | "balanced4" | "balanced5" => Preset::Columns,
        "splitLong" if count == 2 => Preset::Columns,
        "rows" => Preset::Rows,
        "mainAndStack" | "mainLeft" | "mainAndGrid" | "mainRight" | "middleMain" => Preset::MainStack,
        "oneOverTwo" | "mainOverGrid" | "twoOverOne" | "twoOverThree" => Preset::MainRow,
        _ => Preset::Grid,
    }
}

fn preset_to_desk(preset: Preset, count: usize) -> &'static str {
    match preset {
        Preset::Columns => match count { 2 => "columns", 3 => "cols3", 4 => "cols4", 5 => "cols5", _ => "columns" },
        Preset::Rows => "rows",
        Preset::MainStack => "mainAndStack",
        Preset::MainRow => "mainOverGrid",
        Preset::Grid => if count == 4 { "quad" } else { "auto" },
    }
}

/// Whether a tab already shows exactly the desk's panes (only the layout changed).
fn missing_is_empty(have: &[u64], want: &[(String, String)], panes: &HashMap<u64, Pane>) -> bool {
    have.len() == want.len() && have.iter().all(|id| panes.get(id).map(|p| want.contains(&(p.machine_id.clone(), p.agent_id.clone()))).unwrap_or(false))
}

/// split-window's: where the new pane goes — beside a pane of a window (-t), before it (-b), across
/// the whole window (-f), its size (-l: cells, or a percentage), and whether it is gone to (-d).
#[derive(Clone, PartialEq, Debug)]
pub struct At { pub tab: String, pub pane: Option<u64>, pub dir: Dir, pub before: bool, pub full: bool, pub size: Option<(u16, bool)>, pub detached: bool, pub zoom: bool }

#[derive(Clone, PartialEq, Debug)]
pub enum Placement {
    /// Into the focused tile's place when the tab is empty, else a smart split (or the one given).
    Auto(Option<Dir>),
    Split(Dir),
    Tab,
    /// A window of its own in the session in front, even when it is open in another session (a
    /// project's session gathers its harnesses: each shown in both).
    Window,
    Replace,
    At(At),
    /// Into the empty window with this id, in whichever session it is (a new session's first).
    Fill(String),
}

/// This client's terminal (tmux's client name): /dev/ttys003.
pub fn tty_name() -> String {
    static TTY: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    TTY.get_or_init(|| {
        let p = unsafe { libc::ttyname(0) };
        if p.is_null() { return String::new() }
        unsafe { std::ffi::CStr::from_ptr(p) }.to_string_lossy().into_owned()
    }).clone()
}

/// This computer's offset from UTC, in seconds (`date +%z`), read once.
pub fn utc_offset() -> i64 {
    static OFFSET: std::sync::OnceLock<i64> = std::sync::OnceLock::new();
    *OFFSET.get_or_init(|| {
        let out = std::process::Command::new("date").arg("+%z").output().ok().map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string()).unwrap_or_default();
        let sign = if out.starts_with('-') { -1 } else { 1 };
        let h: i64 = out.get(1..3).and_then(|x| x.parse().ok()).unwrap_or(0);
        let m: i64 = out.get(3..5).and_then(|x| x.parse().ok()).unwrap_or(0);
        sign * (h * 3600 + m * 60)
    })
}

/// A pane's pipe (pipe-pane): the command's stdin, fed what the pane prints (-O); which pipe it
/// is, so one that ended does not close its successor.
pub struct Pipe { out: Option<tokio::sync::mpsc::UnboundedSender<Vec<u8>>>, id: u64 }

/// The state the event hooks compare against: each window (its id, @number, name, active pane
/// and layout), the current window, the focused pane, the session's name, and which panes are
/// in a mode.
#[derive(Default, Clone)]
pub struct HooksSeen { ready: bool, session_id: u32, windows: Vec<(String, u64, String, Option<u64>, String)>, current: Option<String>, client: bool, modes: Vec<u64>, focused: Vec<u64> }

/// gethostname(3), as tmux's #{host} reads it (`mac.lan`, not `hostname -s`'s `mac`).
pub fn full_hostname() -> String {
    static HOST: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    HOST.get_or_init(|| {
        let mut buf = [0u8; 256];
        let ok = unsafe { libc::gethostname(buf.as_mut_ptr() as *mut libc::c_char, buf.len()) } == 0;
        if !ok { return String::new() }
        let end = buf.iter().position(|b| *b == 0).unwrap_or(buf.len());
        String::from_utf8_lossy(&buf[..end]).into_owned()
    }).clone()
}

pub fn hostname() -> String {
    static HOST: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    HOST.get_or_init(|| {
        let raw = std::process::Command::new("hostname").arg("-s").output().ok().map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string()).unwrap_or_default();
        if raw.is_empty() { "this computer".into() } else { raw }
    }).clone()
}
