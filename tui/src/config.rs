//! `~/.config/harness/tui.toml` — the person's own keys, a few switches, and the look of hn.
//!
//! ```toml
//! prefix = "ctrl+a"              # instead of ctrl+space
//! prefix2 = "C-b"                # a second one (⌘ keys reach only some terminals)
//! desk = "read"                  # sync | read | off   (as HARNESS_TUI_DESK)
//! predict = "off"                # auto | always | off (as HARNESS_TUI_PREDICT)
//! notify = false                 # OS notifications through the terminal
//!
//! [keys]
//! "alt+h" = "none"               # give ⌥h back to the pane (vim, readline…)
//! "alt+x" = "close-pane"
//! "super+k" = "palette"
//!
//! [look]
//! preset = "classic"            # classic|panes|tmux|vim|lazyvim — a named bundle
//! focus = "line"                # line|surface — a highlighted border vs the "blurred" surface
//! border_lines = "single"      # single|double|heavy|simple|number
//! border_indicators = "colour" # off|colour|arrows|both
//! border_status = "off"        # off|top|bottom (each pane's title row)
//! layout_orientation = "auto"  # auto|vertical|horizontal (default split direction)
//! layout_preset = "auto"       # auto|even-horizontal|even-vertical|main-horizontal|main-vertical|tiled
//! # optional color overrides (#rrggbb or a tmux colour name)
//! # active_border = "#7aa2f7"
//! # border = "#3b4261"
//! # accent = "#7aa2f7"
//! ```
//!
//! Every `[look]` field is optional: an unset one falls back to the preset (or hn's default).
//! The file is a startup default — `hn set -g` afterward still wins.
//!
//! A key names modifiers (`ctrl` `alt` `shift` `super`, joined by `+`) and one key: a character,
//! or `enter` `tab` `esc` `space` `backspace` `left` `right` `up` `down` `pageup` `pagedown`
//! `home` `end` `f1`…`f12`. A command is anything ⌥P's `>` lists by id (see `harness tui --keys`),
//! or `none` to leave the chord to the pane. Environment variables win over the file.

use std::path::PathBuf;

use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Chord { pub code: KeyCode, pub mods: KeyModifiers }

impl Chord {
    /// One spelling per key: letters lower-case with SHIFT as a modifier; a shifted symbol (`{`,
    /// `?`) is its own character, without SHIFT.
    pub fn normal(code: KeyCode, mods: KeyModifiers) -> Chord {
        let mods = mods.intersection(KeyModifiers::CONTROL | KeyModifiers::ALT | KeyModifiers::SHIFT | KeyModifiers::SUPER);
        match code {
            KeyCode::Char(c) if mods.contains(KeyModifiers::CONTROL) => Chord { code: KeyCode::Char(if mods.contains(KeyModifiers::SHIFT) { c } else { c.to_ascii_lowercase() }), mods },
            KeyCode::Char(c) if c.is_alphabetic() && c.is_uppercase() => Chord { code: KeyCode::Char(c.to_ascii_lowercase()), mods: mods | KeyModifiers::SHIFT },
            // A mouse key (tmux's MouseDown1Pane…) keeps S- as tmux's does.
            KeyCode::Char(c) if !c.is_alphabetic() && !crate::keys::is_mouse(&code) => Chord { code: KeyCode::Char(c), mods: mods - KeyModifiers::SHIFT },
            other => Chord { code: other, mods },
        }
    }

    /// A key from the terminal, as tmux names what it sent: 0x1c–0x1f (crossterm's C-4 … C-7)
    /// are C-\ C-] C-^ C-_, and BTab has no S- (crossterm's reads S-BTab).
    pub fn of(key: &KeyEvent) -> Chord {
        let code = match key.code {
            KeyCode::Char(c @ '4'..='7') if key.modifiers.contains(KeyModifiers::CONTROL) => KeyCode::Char(['\\', ']', '^', '_'][(c as u8 - b'4') as usize]),
            code => code,
        };
        let mods = if code == KeyCode::BackTab { key.modifiers - KeyModifiers::SHIFT } else { key.modifiers };
        Chord::normal(code, mods)
    }

    pub fn parse(text: &str) -> Result<Chord, String> {
        let text = text.trim().to_lowercase();
        let parts: Vec<&str> = if text.ends_with("++") { let mut p: Vec<&str> = text[..text.len() - 2].split('+').collect(); p.push("+"); p } else { text.split('+').collect() };
        let (key, mods) = parts.split_last().ok_or_else(|| format!("empty key {text:?}"))?;
        let mut m = KeyModifiers::NONE;
        for part in mods {
            m |= match *part {
                "ctrl" | "control" | "c" => KeyModifiers::CONTROL,
                "alt" | "opt" | "option" | "meta" | "m" => KeyModifiers::ALT,
                "shift" | "s" => KeyModifiers::SHIFT,
                "super" | "cmd" | "command" | "d" => KeyModifiers::SUPER,
                other => return Err(format!("unknown modifier {other:?} in {text:?}")),
            };
        }
        let code = match *key {
            "enter" | "return" => KeyCode::Enter,
            "tab" => KeyCode::Tab,
            "esc" | "escape" => KeyCode::Esc,
            "space" => KeyCode::Char(' '),
            "backspace" => KeyCode::Backspace,
            "left" => KeyCode::Left, "right" => KeyCode::Right, "up" => KeyCode::Up, "down" => KeyCode::Down,
            "pageup" => KeyCode::PageUp, "pagedown" => KeyCode::PageDown, "home" => KeyCode::Home, "end" => KeyCode::End,
            k if k.len() > 1 && k.starts_with('f') && k[1..].parse::<u8>().is_ok() => KeyCode::F(k[1..].parse().unwrap()),
            k if k.chars().count() == 1 => KeyCode::Char(k.chars().next().unwrap()),
            other => return Err(format!("unknown key {other:?} in {text:?}")),
        };
        Ok(Chord::normal(code, m))
    }
}

/// The one place the look/theme of hn is configured — a named preset plus per-knob overrides.
/// Every field is optional: unset fields fall back to the preset (or hn's default look).
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Look {
    /// The named look: `classic` (default) | `panes` | `tmux` | `vim` | `lazyvim`.
    pub preset: Option<String>,
    /// Pane focus: `line` (active pane's border is highlighted) | `surface` ("blur": the active
    /// pane's surface pops and the rest are dimmed, no border line).
    pub focus: Option<String>,
    /// `pane-border-lines`: single | double | heavy | simple | number.
    pub border_lines: Option<String>,
    /// `pane-border-indicators`: off | colour | arrows | both.
    pub border_indicators: Option<String>,
    /// `pane-border-status` (each pane's title row): off | top | bottom.
    pub border_status: Option<String>,
    /// Default split direction for a new harness/pane: auto | vertical | horizontal.
    pub layout_orientation: Option<String>,
    /// The layout arranged when a tab has several panes: auto | even-horizontal | even-vertical
    /// | main-horizontal | main-vertical | tiled.
    pub layout_preset: Option<String>,
    /// Optional color overrides (`#rrggbb` or a tmux colour name).
    pub active_border: Option<String>,
    pub border: Option<String>,
    pub accent: Option<String>,
    /// A bundled terminal theme picked from `hn theme` (one of hn's bundled theme names). hn
    /// draws its palette from the terminal, so the theme's colours show up there; hn only records
    /// the choice here (and tints its chrome with the theme's signature colour) so it survives a
    /// restart. `None` = keep the terminal's own theme.
    pub theme: Option<String>,
    // ── status bar ──
    /// Where the status bar goes: `bottom` (default) | `top` (tmux's status line, status-position)
    /// | `left` | `right` (a bar down the side: the windows with their panes, the machines with theirs).
    pub status_bar: Option<String>,
    /// How panes are set apart: `box` (default: each pane its own frame) | `line` (tmux's shared lines).
    pub border_style: Option<String>,
    /// The bar's width down a side, in columns (18-36; 26 unless dragged).
    pub status_bar_width: Option<String>,
    /// `on`: the panes you are not in, a little quieter (`off` unless chosen).
    pub dim: Option<String>,
}

pub struct Config {
    pub prefix: Chord,
    /// Whether the file named a prefix (else tmux's, or ~/.tmux.conf's, stands).
    pub prefix_set: bool,
    /// A second prefix (tmux's prefix2), where the file names one: `prefix = "D-b"` (⌘B, which
    /// only some terminals pass on) with `prefix2 = "C-b"` works in every terminal.
    pub prefix2: Option<Chord>,
    pub keys: Vec<(Chord, Option<String>)>,
    /// The `[look]` table, if any.
    pub look: Option<Look>,
    pub problems: Vec<String>,
}

impl Look {
    /// The bundle each named look sets beyond its `@hn-look` value. Focus (line|surface) is the
    /// piece that changes the most — how panes are drawn (a highlighted border vs a "blurred"
    /// surface) — so it is what the presets differ by. Colors are left to the theme or [look].
    pub fn look_preset(preset: &str) -> Vec<(&'static str, &'static str)> {
        match preset {
            "panes" | "lazyvim" => vec![("@hn-focus", "surface")],
            _ => vec![],
        }
    }

    /// The `(option, value)` pairs this `[look]` table sets at boot: the preset's defaults first,
    /// then whichever knobs the file named, which override them.
    pub fn assignments(&self) -> Vec<(String, String)> {
        let preset = self.preset.as_deref().unwrap_or("classic");
        // `@hn-look` tells structure which bundle is on; `@hn-focus` (from the preset or an
        // explicit `focus`) tells how panes are drawn. Both are options, so `hn show` sees them.
        let mut out: Vec<(String, String)> = vec![("@hn-look".into(), preset.to_string())];
        // A preset's `@hn-focus` is its default; an explicit `focus` knob overrides it, so do not
        // emit the preset's when the file named one (the later assignment would win anyway).
        for (n, v) in Self::look_preset(preset) {
            if n == "@hn-focus" && self.focus.is_some() { continue }
            out.push((n.into(), v.into()))
        }
        if let Some(f) = &self.focus { out.push(("@hn-focus".into(), f.clone())) }
        if let Some(b) = &self.border_lines { out.push(("pane-border-lines".into(), b.clone())) }
        if let Some(b) = &self.border_indicators { out.push(("pane-border-indicators".into(), b.clone())) }
        if let Some(b) = &self.border_status { out.push(("pane-border-status".into(), b.clone())) }
        if let Some(o) = &self.layout_orientation { out.push(("@hn-layout".into(), o.clone())) }
        if let Some(o) = &self.layout_preset { out.push(("@hn-layout-preset".into(), o.clone())) }
        if let Some(c) = &self.active_border { out.push(("pane-active-border-style".into(), format!("fg={c}"))) }
        if let Some(c) = &self.border { out.push(("pane-border-style".into(), format!("fg={c}"))) }
        // The accent: an explicit `accent` wins; otherwise a chosen terminal theme supplies its
        // signature color (so the picker's choice tints chrome at boot too, not only live).
        if let Some(c) = &self.accent { out.push(("@hn-accent".into(), c.clone())) }
        else if let Some(g) = &self.theme {
            if let Some(a) = crate::theme::theme_accent_hex(g) { out.push(("@hn-accent".into(), a)) }
        }
        if let Some(g) = &self.theme { out.push(("@hn-theme".into(), g.clone())) }
        // ── status bar ──
        // (At the top or the bottom it is tmux's own status line, so status-position says where.)
        if let Some(b) = &self.status_bar {
            out.push(("@hn-status-bar".into(), b.clone()));
            if matches!(b.as_str(), "top" | "bottom") { out.push(("status-position".into(), b.clone())) }
        }
        if let Some(b) = &self.border_style { out.push(("@hn-border".into(), b.clone())) }
        if let Some(w) = &self.status_bar_width { out.push(("@hn-status-bar-width".into(), w.clone())) }
        if let Some(d) = &self.dim { out.push(("@hn-dim".into(), d.clone())) }
        out
    }
}

impl Default for Config {
    fn default() -> Self {
        Config { prefix: Chord::normal(KeyCode::Char('b'), KeyModifiers::CONTROL), prefix_set: false, prefix2: None, keys: Vec::new(), look: None, problems: Vec::new() }
    }
}

pub fn path() -> PathBuf {
    // (Tests never read or write the real config: theirs is their own.)
    #[cfg(test)]
    return std::env::temp_dir().join(format!("hn-test-{}", std::process::id())).join("harness").join("tui.toml");
    #[allow(unreachable_code)]
    let base = std::env::var("XDG_CONFIG_HOME").ok().filter(|s| !s.is_empty()).map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(std::env::var("HOME").unwrap_or_default()).join(".config"));
    base.join("harness").join("tui.toml")
}

/// Read the file and fold its switches into the environment (the environment wins).
pub fn load() -> Config {
    let mut config = Config::default();
    let Ok(text) = std::fs::read_to_string(path()) else { return config };
    let value: toml::Value = match text.parse() {
        Ok(v) => v,
        Err(error) => { config.problems.push(format!("tui.toml: {}", error.to_string().lines().next().unwrap_or(""))); return config }
    };
    // SAFETY: called from `main` before the async runtime (or any other thread) exists.
    let setenv = |name: &str, value: &str| { if std::env::var(name).is_err() { unsafe { std::env::set_var(name, value) } } };
    if let Some(p) = value.get("prefix").and_then(|v| v.as_str()) {
        match crate::keys::parse(p) { Ok(c) => { config.prefix = c; config.prefix_set = true } Err(e) => config.problems.push(format!("tui.toml prefix: {e}")) }
    }
    if let Some(p) = value.get("prefix2").and_then(|v| v.as_str()) {
        match crate::keys::parse(p) { Ok(c) => config.prefix2 = Some(c), Err(e) => config.problems.push(format!("tui.toml prefix2: {e}")) }
    }
    if let Some(d) = value.get("desk").and_then(|v| v.as_str()) { setenv("HARNESS_TUI_DESK", d) }
    if let Some(p) = value.get("predict").and_then(|v| v.as_str()) { setenv("HARNESS_TUI_PREDICT", p) }
    if let Some(false) = value.get("notify").and_then(|v| v.as_bool()) { setenv("HARNESS_TUI_NOTIFY", "off") }
    if let Some(keys) = value.get("keys").and_then(|v| v.as_table()) {
        for (chord, command) in keys {
            let Some(command) = command.as_str() else { config.problems.push(format!("tui.toml keys.{chord}: expected a command name")); continue };
            match crate::keys::parse(chord) {
                Ok(c) => config.keys.push((c, if command == "none" { None } else { Some(command.to_string()) })),
                Err(e) => config.problems.push(format!("tui.toml keys: {e}")),
            }
        }
    }
    if let Some(look) = value.get("look").and_then(|v| v.as_table()) { config.look = Some(look_of(look, &mut config.problems)) }
    config
}

/// The `[look]` table as read, a knob that is not a string said in [problems].
fn look_of(look: &toml::Table, problems: &mut Vec<String>) -> Look {
    let mut l = Look::default();
    let mut field = |t: &toml::Table, key: &str, slot: &mut Option<String>| {
        if let Some(v) = t.get(key) {
            if let Some(s) = v.as_str() { *slot = Some(s.to_string()) }
            else { problems.push(format!("tui.toml look.{key}: expected a string")) }
        }
    };
    field(look, "preset", &mut l.preset);
    field(look, "focus", &mut l.focus);
    field(look, "border_lines", &mut l.border_lines);
    field(look, "border_indicators", &mut l.border_indicators);
    field(look, "border_status", &mut l.border_status);
    field(look, "layout_orientation", &mut l.layout_orientation);
    field(look, "layout_preset", &mut l.layout_preset);
    field(look, "active_border", &mut l.active_border);
    field(look, "border", &mut l.border);
    field(look, "accent", &mut l.accent);
    field(look, "theme", &mut l.theme);
    // ── status bar ──
    field(look, "status_bar", &mut l.status_bar);
    field(look, "border_style", &mut l.border_style);
    field(look, "status_bar_width", &mut l.status_bar_width);
    field(look, "dim", &mut l.dim);
    // (An older file's `tabs` is left alone: the tabs over the panes are gone, the bar lists the windows.)
    l
}

/// Write the `[look]` table back to the file, replacing an existing `[look]` section in place and
/// leaving the rest of the file (and its comments) untouched. Used by the `hn theme` picker so the
/// file stays the single place the look is described.
pub fn write_look(look: &Look) -> std::io::Result<()> {
    let p = path();
    let existing = std::fs::read_to_string(&p).unwrap_or_default();
    // (A first setting on a machine with no config yet: its folder too.)
    if let Some(dir) = p.parent() { std::fs::create_dir_all(dir)? }
    std::fs::write(p, replace_look_section(&existing, &format_look(look)))?;
    Ok(())
}

fn is_section_header(line: &str) -> bool { line.starts_with('[') && line.trim_end().ends_with(']') }

fn format_look(look: &Look) -> String {
    let mut s = String::from("[look]\n");
    let push = |slot: &Option<String>, key: &str, s: &mut String| {
        if let Some(v) = slot { s.push_str(&format!("{key} = \"{}\"\n", v.replace('\\', "\\\\").replace('"', "\\\""))) }
    };
    push(&look.preset, "preset", &mut s);
    push(&look.focus, "focus", &mut s);
    push(&look.border_lines, "border_lines", &mut s);
    push(&look.border_indicators, "border_indicators", &mut s);
    push(&look.border_status, "border_status", &mut s);
    push(&look.layout_orientation, "layout_orientation", &mut s);
    push(&look.layout_preset, "layout_preset", &mut s);
    push(&look.theme, "theme", &mut s);
    // ── status bar ──
    push(&look.status_bar, "status_bar", &mut s);
    push(&look.border_style, "border_style", &mut s);
    push(&look.status_bar_width, "status_bar_width", &mut s);
    push(&look.dim, "dim", &mut s);
    s
}

fn replace_look_section(text: &str, block: &str) -> String {
    let lines: Vec<&str> = text.lines().collect();
    let header_at = lines.iter().position(|l| is_section_header(l) && l.trim() == "[look]");
    let Some(header_at) = header_at else {
        // No [look] yet: append a fresh section, separated from whatever preceded it.
        let mut out = text.to_string();
        if !out.is_empty() {
            if !out.ends_with('\n') { out.push('\n') }
            out.push('\n');
        }
        out.push_str(block);
        if !out.ends_with('\n') { out.push('\n') }
        return out;
    };
    // Replace from the header through the line before the next section header (or end).
    let next_header = lines[header_at + 1..].iter().position(|l| is_section_header(l)).map(|i| header_at + 1 + i).unwrap_or(lines.len());
    let mut out: Vec<&str> = lines[..header_at].to_vec();
    let tail = lines[next_header..].to_vec();
    // Rebuild: head lines, the new block as its own lines, then the tail.
    let block_lines: Vec<&str> = block.lines().collect();
    out.extend(block_lines.iter().copied());
    out.extend(tail.iter().copied());
    let mut joined = out.join("\n");
    joined.push('\n');
    joined
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_and_normalises() {
        assert_eq!(Chord::parse("alt+shift+p").unwrap(), Chord::normal(KeyCode::Char('P'), KeyModifiers::ALT));
        assert_eq!(Chord::parse("ctrl+space").unwrap(), Chord::normal(KeyCode::Char(' '), KeyModifiers::CONTROL));
        assert_eq!(Chord::parse("alt+{").unwrap(), Chord::normal(KeyCode::Char('{'), KeyModifiers::ALT | KeyModifiers::SHIFT));
        assert_eq!(Chord::parse("super+enter").unwrap().code, KeyCode::Enter);
        assert_eq!(Chord::parse("alt++").unwrap().code, KeyCode::Char('+'));
        assert!(Chord::parse("hyper+x").is_err());
    }

    #[test]
    fn look_preset_sets_surface_for_the_blur_bundles() {
        assert_eq!(Look::look_preset("lazyvim"), vec![("@hn-focus", "surface")]);
        assert_eq!(Look::look_preset("panes"), vec![("@hn-focus", "surface")]);
        assert!(Look::look_preset("vim").is_empty());
        assert!(Look::look_preset("classic").is_empty());
        assert!(Look::look_preset("tmux").is_empty());
    }

    #[test]
    fn look_assignments_follow_preset_then_overrides() {
        // Defaults from the preset, with an explicit `focus` replacing the preset's surface.
        let look = Look {
            preset: Some("lazyvim".into()), focus: Some("line".into()),
            border_lines: Some("heavy".into()), layout_orientation: Some("vertical".into()),
            active_border: Some("#7aa2f7".into()), ..Default::default()
        };
        let a = look.assignments();
        let get = |name: &str| a.iter().find(|(n, _)| n == name).map(|(_, v)| v.clone());
        assert_eq!(get("@hn-look").as_deref(), Some("lazyvim"));
        // The explicit `focus` replaces the preset's, not added after it.
        assert_eq!(get("@hn-focus").as_deref(), Some("line"));
        assert_eq!(get("pane-border-lines").as_deref(), Some("heavy"));
        assert_eq!(get("@hn-layout").as_deref(), Some("vertical"));
        assert_eq!(get("pane-active-border-style").as_deref(), Some("fg=#7aa2f7"));
        // The surface preset, without an override, keeps its default focus.
        let plain = Look { preset: Some("panes".into()), ..Default::default() };
        let b = plain.assignments();
        let get_b = |name: &str| b.iter().find(|(n, _)| n == name).map(|(_, v)| v.clone());
        assert_eq!(get_b("@hn-focus").as_deref(), Some("surface"));
    }

    #[test]
    fn theme_is_recorded_and_replayed() {
        // Choosing a terminal theme writes it to the config; at boot `@hn-theme` is replayed so
        // the picker marks it, and its signature colour becomes the accent unless one is named.
        let look = Look { preset: Some("panes".into()), theme: Some("Atom One Dark".into()), ..Default::default() };
        let a = look.assignments();
        assert_eq!(a.iter().find(|(n, _)| n == "@hn-theme").map(|(_, v)| v.as_str()), Some("Atom One Dark"));
        assert!(a.iter().any(|(n, _)| n == "@hn-accent"));
        // The [look] block carries it, escaping quotes/backslashes.
        let block = format_look(&look);
        assert!(block.contains("theme = \"Atom One Dark\"\n"));
        // An explicit `accent` wins over the theme's own.
        let explicit = Look { theme: Some("Atom One Dark".into()), accent: Some("#abcdef".into()), ..Default::default() };
        let b = explicit.assignments();
        assert_eq!(b.iter().find(|(n, _)| n == "@hn-accent").map(|(_, v)| v.as_str()), Some("#abcdef"));
    }

    #[test]
    fn keys_from_the_terminal_as_tmux_names_them() {
        let key = |code, mods| crate::keys::name(&Chord::of(&KeyEvent::new(code, mods)));
        // 0x1c–0x1f, which crossterm reads as C-4 … C-7.
        assert_eq!(key(KeyCode::Char('4'), KeyModifiers::CONTROL), "C-\\");
        assert_eq!(key(KeyCode::Char('5'), KeyModifiers::CONTROL), "C-]");
        assert_eq!(key(KeyCode::Char('6'), KeyModifiers::CONTROL), "C-^");
        assert_eq!(key(KeyCode::Char('7'), KeyModifiers::CONTROL), "C-_");
        assert_eq!(key(KeyCode::BackTab, KeyModifiers::SHIFT), "BTab");
        assert_eq!(Chord::of(&KeyEvent::new(KeyCode::BackTab, KeyModifiers::SHIFT)), crate::keys::parse("BTab").unwrap());
        assert_eq!(Chord::of(&KeyEvent::new(KeyCode::Char('4'), KeyModifiers::CONTROL)), crate::keys::parse("C-\\").unwrap());
        assert_eq!(key(KeyCode::Char('4'), KeyModifiers::ALT), "M-4");
    }

    #[test]
    fn replace_look_section_rewrites_in_place_and_preserves_rest() {
        // Replaces an existing [look] block, keeping the lines before and after (and comments).
        let original = "prefix = \"ctrl+a\"\n# my comment\n[look]\npreset = \"classic\"\nfocus = \"line\"\n[keys]\n\"alt+h\" = \"none\"\n";
        let block = "[look]\npreset = \"panes\"\nfocus = \"surface\"\nborder_lines = \"single\"\n";
        let replaced = replace_look_section(original, block);
        assert!(replaced.starts_with("prefix = \"ctrl+a\"\n# my comment\n"));
        assert!(replaced.contains("[look]\npreset = \"panes\"\nfocus = \"surface\"\nborder_lines = \"single\"\n"));
        assert!(!replaced.contains("preset = \"classic\""));
        assert!(replaced.ends_with("[keys]\n\"alt+h\" = \"none\"\n"));

        // Appends a fresh [look] section when the file has none.
        let none = "prefix = \"ctrl+a\"\n";
        let appended = replace_look_section(none, block);
        assert!(appended.ends_with("prefix = \"ctrl+a\"\n\n[look]\npreset = \"panes\"\nfocus = \"surface\"\nborder_lines = \"single\"\n"));
    }

    // ── status bar ──

    #[test]
    fn the_status_bar_and_border_style_go_through_tui_toml_and_back() {
        let look = Look { status_bar: Some("left".into()), border_style: Some("line".into()), ..Default::default() };
        let text = format_look(&look);
        assert!(text.contains("status_bar = \"left\"\nborder_style = \"line\"\n"), "{text}");
        let value: toml::Value = text.parse().unwrap();
        let mut problems = Vec::new();
        assert_eq!(look_of(value.get("look").and_then(|v| v.as_table()).unwrap(), &mut problems), look);
        assert!(problems.is_empty());
        // An older file's `tabs` line reads as nothing, and says no problem.
        let old: toml::Value = format!("{text}tabs = \"off\"\n").parse().unwrap();
        assert_eq!(look_of(old.get("look").and_then(|v| v.as_table()).unwrap(), &mut problems), look);
        assert!(problems.is_empty());
        // Each is an option at boot; at the top or bottom the bar is tmux's status line, placed so.
        let a = look.assignments();
        let get = |a: &[(String, String)], n: &str| a.iter().find(|(k, _)| k == n).map(|(_, v)| v.clone());
        assert_eq!(get(&a, "@hn-status-bar").as_deref(), Some("left"));
        assert_eq!(get(&a, "@hn-border").as_deref(), Some("line"));
        assert_eq!(get(&a, "status-position"), None);
        let top = Look { status_bar: Some("top".into()), ..Default::default() }.assignments();
        assert_eq!(get(&top, "status-position").as_deref(), Some("top"));
    }
}
