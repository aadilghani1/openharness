//! The terminal hn draws on: ratatui's crossterm backend, with colours written as tmux writes
//! them — the eight colours and their bright forms as SGR 30–37, 90–97 (40–47, 100–107 behind),
//! and so `colour0`–`colour15` too (terminfo's setaf/setab do that for the first sixteen),
//! `colourN` past them as 38;5;N, RGB as 38;2;R;G;B — where crossterm writes every colour as
//! 38;5;N, which an eight-colour terminal (the Linux console) does not read. Everything else is
//! crossterm's.

use std::io::{self, Write};

use ratatui::backend::{Backend, ClearType, CrosstermBackend, WindowSize};
use ratatui::buffer::Cell;
use ratatui::layout::{Position, Size};
use ratatui::style::{Color, Modifier};

/// [shadow]: every cell as last written, row by row — so a row whose width the terminal may
/// count otherwise can be written again whole.
pub struct TmuxBackend<W: Write> {
    inner: CrosstermBackend<W>,
    shadow: Vec<Vec<Cell>>,
    /// A frame's changes are one synchronized update (?2026), closed at its flush.
    syncing: bool,
    /// The cursor as last written: a frame that changes nothing writes nothing (an idle hn is
    /// silent, as tmux is — a terminal's or an outer tmux's activity mark stays clear).
    cursor_at: Option<Position>,
    cursor_shown: Option<bool>,
}

/// A cluster whose width terminals may count otherwise than hn does: several code points (a
/// base and its marks, ZWJ emoji, a keycap, VS16), or a script whose vowels some count as
/// spacing and some as combining (Thai, Lao, Tibetan, Myanmar, Khmer).
fn risky(symbol: &str) -> bool {
    let mut n = 0;
    for c in symbol.chars() {
        n += 1;
        if n > 1 { return true }
        let u = c as u32;
        if (0x0E00..=0x0FFF).contains(&u) || (0x1000..=0x109F).contains(&u) || (0x1780..=0x17FF).contains(&u) { return true }
    }
    false
}

/// What the terminal was last told: colours, attributes, the underline's style, the open link.
struct Pen { fg: Color, bg: Color, ul: Color, modifier: Modifier, style: u8, link: Option<std::sync::Arc<str>> }

impl Pen {
    fn new() -> Pen { Pen { fg: Color::Reset, bg: Color::Reset, ul: Color::Reset, modifier: Modifier::empty(), style: 0, link: None } }

    /// A cell's attributes (as tmux's tty_attributes writes them) and its symbol.
    fn put(&mut self, w: &mut impl Write, cell: &Cell, extra: Option<&Extra>, usstyle: bool, links: bool) -> io::Result<()> {
        if cell.modifier != self.modifier {
            // tmux's tty_attributes: an attribute taken away resets everything, then what is
            // wanted is set again.
            if !(self.modifier - cell.modifier).is_empty() {
                w.write_all(b"\x1b[0m")?;
                (self.fg, self.bg, self.ul, self.modifier, self.style) = (Color::Reset, Color::Reset, Color::Reset, Modifier::empty(), 0);
            }
            for (flag, code) in ATTRS { if cell.modifier.contains(flag) && !self.modifier.contains(flag) { write!(w, "\x1b[{code}m")?; if code == 4 { self.style = 1 } } }
            self.modifier = cell.modifier;
        }
        // tty_attributes' Smulx: a curly (double, dotted, dashed) underline where the
        // terminal reads one, else a plain one.
        let want = if !cell.modifier.contains(Modifier::UNDERLINED) { 0 } else if usstyle { extra.map(|e| e.underline).filter(|u| *u >= 2).unwrap_or(1) } else { 1 };
        if want != self.style && want > 0 { if want == 1 { w.write_all(b"\x1b[4:1m")? } else { write!(w, "\x1b[4:{want}m")? } self.style = want }
        if cell.fg != self.fg { write!(w, "\x1b[{}m", sgr(cell.fg, 30))?; self.fg = cell.fg; }
        if cell.bg != self.bg { write!(w, "\x1b[{}m", sgr(cell.bg, 40))?; self.bg = cell.bg; }
        if usstyle && cell.underline_color != self.ul { write!(w, "\x1b[{}m", sgr_underline(cell.underline_color))?; self.ul = cell.underline_color; }
        // A link (OSC 8) opened where it starts and closed where it ends.
        let want_link = if links { extra.and_then(|e| e.link.clone()) } else { None };
        if want_link != self.link {
            match &want_link { Some(uri) => write!(w, "\x1b]8;;{uri}\x1b\\")?, None => w.write_all(b"\x1b]8;;\x1b\\")? }
            self.link = want_link;
        }
        w.write_all(cell.symbol().as_bytes())
    }

    /// Everything back to the terminal's defaults (and so known).
    fn reset(&mut self, w: &mut impl Write) -> io::Result<()> {
        if self.link.is_some() { w.write_all(b"\x1b]8;;\x1b\\")? }
        *self = Pen::new();
        w.write_all(b"\x1b[0m")
    }
}

/// What a pane's cell carries that ratatui's cell cannot: its underline's style (2 double, 3
/// curly, 4 dotted, 5 dashed — tmux's 4:N) and its link (OSC 8). Kept by position for the frame
/// being drawn (ui's pane_body), and written with the cell when the outer terminal reads them.
#[derive(Clone, PartialEq, Default, Debug)]
pub struct Extra { pub underline: u8, pub link: Option<std::sync::Arc<str>> }

struct Frame { extras: std::collections::HashMap<(u16, u16), Extra>, usstyle: bool, links: bool }
static FRAME: std::sync::Mutex<Option<Frame>> = std::sync::Mutex::new(None);

/// A frame begins: no cell's extras yet, and what the outer terminal reads — styled and coloured
/// underlines (tmux's usstyle feature), links (hyperlinks).
pub fn begin_frame(usstyle: bool, links: bool) {
    if let Ok(mut f) = FRAME.lock() { *f = Some(Frame { extras: Default::default(), usstyle, links }) }
}

pub fn set_extra(x: u16, y: u16, extra: Extra) {
    if let Ok(mut f) = FRAME.lock() { if let Some(f) = f.as_mut() { f.extras.insert((x, y), extra); } }
}

/// Whether the outer terminal reads styled underlines with their colour (usstyle) and links
/// (hyperlinks): terminal-features for this TERM (as tmux's), else the terminals known to.
pub fn outer_features(features: &[String]) -> (bool, bool) {
    static KNOWN: std::sync::OnceLock<(String, bool)> = std::sync::OnceLock::new();
    let (term, known) = KNOWN.get_or_init(|| {
        let term = std::env::var("TERM").unwrap_or_default();
        let program = std::env::var("TERM_PROGRAM").unwrap_or_default();
        let known = matches!(program.as_str(), "iTerm.app" | "WezTerm" | "ghostty" | "vscode" | "tmux")
            || ["xterm-kitty", "xterm-ghostty", "wezterm", "alacritty", "foot", "tmux", "contour", "rio"].iter().any(|t| term.starts_with(t));
        (term, known)
    });
    let (mut us, mut links) = (*known, *known);
    for f in features {
        let (pattern, rest) = f.split_once(':').unwrap_or((f.as_str(), ""));
        if !crate::cmd::fnmatch(pattern, term) { continue }
        for x in rest.split(':') { match x { "usstyle" => us = true, "hyperlinks" => links = true, _ => {} } }
    }
    (us, links)
}

impl<W: Write> TmuxBackend<W> {
    pub fn new(writer: W) -> Self { Self { inner: CrosstermBackend::new(writer), shadow: Vec::new(), syncing: false, cursor_at: None, cursor_shown: None } }

    fn row_risky(&self, y: u16) -> bool { self.shadow.get(y as usize).map(|r| r.iter().any(|c| risky(c.symbol()))).unwrap_or(false) }

    fn remember(&mut self, x: u16, y: u16, cell: &Cell) {
        let (x, y) = (x as usize, y as usize);
        if self.shadow.len() <= y { self.shadow.resize(y + 1, Vec::new()) }
        // (A wide cluster covers the cells after it: ratatui blanks them and sends none.)
        let wide = unicode_width::UnicodeWidthStr::width(cell.symbol()).max(1);
        let row = &mut self.shadow[y];
        if row.len() < x + wide { row.resize(x + wide, Cell::default()) }
        row[x] = cell.clone();
        for c in &mut row[x + 1..x + wide] { *c = Cell::default() }
    }
}

/// What has been written to the terminal, in bytes (#{client_written}).
pub static WRITTEN: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);

/// The terminal's writer, its bytes counted.
pub struct Counted<W: Write>(pub W);

impl<W: Write> Write for Counted<W> {
    fn write(&mut self, buf: &[u8]) -> io::Result<usize> {
        let n = self.0.write(buf)?;
        WRITTEN.fetch_add(n as u64, std::sync::atomic::Ordering::Relaxed);
        Ok(n)
    }
    fn flush(&mut self) -> io::Result<()> { self.0.flush() }
}

impl<W: Write> Write for TmuxBackend<W> {
    fn write(&mut self, buf: &[u8]) -> io::Result<usize> { self.inner.write(buf) }
    fn flush(&mut self) -> io::Result<()> { Write::flush(&mut self.inner) }
}

/// A colour's SGR parameters as tmux's tty_colours_fg / _bg write them ([base] 30, 40 or 58).
fn sgr(c: Color, base: u16) -> String {
    let named = |n: u16| (n + base).to_string();
    let bright = |n: u16| (n + base + 60).to_string();
    match c {
        Color::Reset => (base + 9).to_string(),
        Color::Black => named(0), Color::Red => named(1), Color::Green => named(2), Color::Yellow => named(3),
        Color::Blue => named(4), Color::Magenta => named(5), Color::Cyan => named(6), Color::Gray => named(7),
        Color::DarkGray => bright(0), Color::LightRed => bright(1), Color::LightGreen => bright(2), Color::LightYellow => bright(3),
        Color::LightBlue => bright(4), Color::LightMagenta => bright(5), Color::LightCyan => bright(6), Color::White => bright(7),
        // setaf's `%p1%{8}%<%t3%p1%d%e%p1%{16}%<%t9%p1%{8}%-%d%e38;5;%p1%d`.
        Color::Indexed(n) if n < 8 && base != 58 => named(n as u16),
        Color::Indexed(n) if n < 16 && base != 58 => bright(n as u16 - 8),
        Color::Indexed(n) => format!("{};5;{n}", base + 8),
        Color::Rgb(r, g, b) => format!("{};2;{r};{g};{b}", base + 8),
    }
}

/// The underline colour: 58;5;N or 58;2;R;G;B (a named one as its index), 59 for none.
fn sgr_underline(c: Color) -> String {
    match c {
        Color::Reset => "59".into(),
        Color::Indexed(n) => format!("58;5;{n}"),
        Color::Rgb(r, g, b) => format!("58;2;{r};{g};{b}"),
        named => {
            let order = [Color::Black, Color::Red, Color::Green, Color::Yellow, Color::Blue, Color::Magenta, Color::Cyan, Color::Gray,
                Color::DarkGray, Color::LightRed, Color::LightGreen, Color::LightYellow, Color::LightBlue, Color::LightMagenta, Color::LightCyan, Color::White];
            format!("58;5;{}", order.iter().position(|o| *o == named).unwrap_or(0))
        }
    }
}

const ATTRS: [(Modifier, u8); 9] = [
    (Modifier::BOLD, 1), (Modifier::DIM, 2), (Modifier::ITALIC, 3), (Modifier::UNDERLINED, 4), (Modifier::SLOW_BLINK, 5),
    (Modifier::RAPID_BLINK, 6), (Modifier::REVERSED, 7), (Modifier::HIDDEN, 8), (Modifier::CROSSED_OUT, 9),
];

impl<W: Write> Backend for TmuxBackend<W> {
    type Error = io::Error;

    fn draw<'a, I>(&mut self, content: I) -> io::Result<()>
    where
        I: Iterator<Item = (u16, u16, &'a Cell)>,
    {
        let cells: Vec<(u16, u16, Cell)> = content.map(|(x, y, c)| (x, y, c.clone())).collect();
        // Nothing changed: nothing written.
        if cells.is_empty() { return Ok(()) }
        if !self.syncing { self.inner.write_all(b"\x1b[?2026h")?; self.syncing = true }
        // (The cells move the terminal's cursor: where it is must be said again after them.)
        self.cursor_at = None;
        // A row that holds (or held) a cluster the terminal may count otherwise is written again
        // whole from its first column, as fzf writes a line: a cell-by-cell update there would
        // leave a stale character where the two counts part (a Thai vowel beside a keycap).
        let touched: std::collections::BTreeSet<u16> = cells.iter().map(|c| c.1).collect();
        let was: std::collections::HashSet<u16> = touched.iter().copied().filter(|y| self.row_risky(*y)).collect();
        for (x, y, c) in &cells { self.remember(*x, *y, c) }
        let whole: std::collections::BTreeSet<u16> = touched.into_iter().filter(|y| was.contains(y) || self.row_risky(*y)).collect();
        let frame = FRAME.lock().ok();
        let frame = frame.as_ref().and_then(|f| f.as_ref());
        let (usstyle, links) = frame.map(|f| (f.usstyle, f.links)).unwrap_or((false, false));
        let extra_at = |x: u16, y: u16| frame.and_then(|f| f.extras.get(&(x, y)));
        // CrosstermBackend writes through to its writer.
        let w = &mut self.inner;
        let mut pen = Pen::new();
        let mut last: Option<(u16, u16)> = None;
        for (x, y, cell) in cells.iter().filter(|c| !whole.contains(&c.1)) {
            // The cursor moves only where the cells do not follow on.
            if !matches!(last, Some((lx, ly)) if *x == lx + 1 && *y == ly) { write!(w, "\x1b[{};{}H", y + 1, x + 1)?; }
            last = Some((*x, *y));
            pen.put(w, cell, extra_at(*x, *y), usstyle, links)?;
        }
        for y in whole {
            let Some(row) = self.shadow.get(y as usize) else { continue };
            write!(w, "\x1b[{};1H", y + 1)?;
            pen.reset(w)?;
            w.write_all(b"\x1b[2K")?;
            let (mut skip, mut placed) = (0usize, true);
            for (x, cell) in row.iter().enumerate() {
                if skip > 0 { skip -= 1; continue }
                // After a cluster the terminal may have counted otherwise, the next cell goes
                // where hn counts it.
                if !placed { write!(w, "\x1b[{};{}H", y + 1, x + 1)?; }
                pen.put(w, cell, extra_at(x as u16, y), usstyle, links)?;
                skip = unicode_width::UnicodeWidthStr::width(cell.symbol()).saturating_sub(1);
                placed = !risky(cell.symbol());
            }
        }
        if pen.link.is_some() { w.write_all(b"\x1b]8;;\x1b\\")? }
        w.write_all(b"\x1b[39m\x1b[49m\x1b[59m\x1b[0m")
    }

    fn hide_cursor(&mut self) -> io::Result<()> { if self.cursor_shown == Some(false) { return Ok(()) } self.cursor_shown = Some(false); self.inner.hide_cursor() }
    fn show_cursor(&mut self) -> io::Result<()> { if self.cursor_shown == Some(true) { return Ok(()) } self.cursor_shown = Some(true); self.inner.show_cursor() }
    // (Never asked of the terminal — \e[6n and a wait for its answer: hn draws the whole screen,
    // and a terminal slow to answer, or one that never does, must not stop it starting.)
    fn get_cursor_position(&mut self) -> io::Result<Position> { Ok(Position::ORIGIN) }
    fn set_cursor_position<P: Into<Position>>(&mut self, position: P) -> io::Result<()> {
        let p = position.into();
        if self.cursor_at == Some(p) { return Ok(()) }
        self.cursor_at = Some(p);
        self.inner.set_cursor_position(p)
    }
    fn clear(&mut self) -> io::Result<()> { self.shadow.clear(); self.cursor_at = None; self.cursor_shown = None; self.inner.clear() }
    fn clear_region(&mut self, clear_type: ClearType) -> io::Result<()> { if matches!(clear_type, ClearType::All) { self.shadow.clear() } self.inner.clear_region(clear_type) }
    fn append_lines(&mut self, n: u16) -> io::Result<()> { self.inner.append_lines(n) }
    fn size(&self) -> io::Result<Size> { self.inner.size() }
    fn window_size(&mut self) -> io::Result<WindowSize> { self.inner.window_size() }
    fn flush(&mut self) -> io::Result<()> {
        if std::mem::take(&mut self.syncing) { self.inner.write_all(b"\x1b[?2026l")? }
        Backend::flush(&mut self.inner)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn colours_as_tmux_writes_them() {
        assert_eq!(sgr(Color::Red, 30), "31");
        assert_eq!(sgr(Color::Green, 40), "42");
        assert_eq!(sgr(Color::LightBlue, 30), "94");
        assert_eq!(sgr(Color::White, 40), "107");
        assert_eq!(sgr(Color::Reset, 40), "49");
        // The first sixteen of the 256 as terminfo's setaf/setab write them (\e[38;5;1m → 31).
        assert_eq!(sgr(Color::Indexed(1), 30), "31");
        assert_eq!(sgr(Color::Indexed(9), 30), "91");
        assert_eq!(sgr(Color::Indexed(4), 40), "44");
        assert_eq!(sgr(Color::Indexed(12), 40), "104");
        assert_eq!(sgr(Color::Indexed(16), 30), "38;5;16");
        assert_eq!(sgr(Color::Rgb(1, 2, 3), 40), "48;2;1;2;3");
    }
}
