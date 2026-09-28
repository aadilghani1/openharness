//! What the daemons put over the window, as tmux's display-popup floats over it: the hatch reveal
//! (the whole screen), the zoo (the paired daemon's portrait, the box back and the meters), a line's
//! detail in full, the first-day consent (what the daemon sees), the brief on return, and — while
//! the daemon key table is up — its keys, as the prefix's which-key shows the prefix table's.
//!
//! A filled daemon's plate is inked glyph by glyph (plates.rs) and, while motion is on and the
//! terminal is in front, runs its mood's loop, a frame every frameMs.

use std::time::{Duration, Instant};

use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};
use ratatui::buffer::Buffer;
use ratatui::layout::Rect;
use ratatui::style::{Color, Modifier, Style};

use super::card::{shelf_lines, Shelved};
use super::hatch::{self, Ink, Reveal};
use super::plates::{self, Mode, PORTRAIT};
use super::render;
use super::roster::roster;
use super::state::ZooState;
use super::zoo::{ZooDoc, Zoo};
use crate::app::App;

pub enum Overlay {
    Hatch(Box<Reveal>),
    Zoo,
    /// A line's detail (or a lesson), in full: `keyed` when its keys answer from here.
    Detail { id: String, title: String, text: String, top: usize, keyed: bool },
    /// The first-day consent: what the daemon sees.
    Consent { name: String },
}

/// A row of a view: text in an ink, or a shelf's sprite row (ten columns a daemon, each its colour).
#[derive(Clone, Debug)]
pub enum Row { Text(String, Ink), Shelf(String, Vec<Option<u8>>) }

impl Row {
    pub fn text(&self) -> &str { match self { Row::Text(t, _) | Row::Shelf(t, _) => t } }
}

fn t(s: impl Into<String>) -> Row { Row::Text(s.into(), Ink::Plain) }

/// The paired daemon's portrait over the zoo: its mood, and the frame of that mood's loop.
#[derive(Clone, Copy, Debug)]
pub struct Face<'a> { pub mood: &'a str, pub frame: usize, pub own: Option<&'a plates::Art>, pub uid: Option<&'a str> }

/// The zoo as rows: the paired daemon (its portrait, with a `face`), the box back, what you own, the
/// eggs and the meters — or, before any hatch, the nest and its habits. Shared by the popup and
/// `hn zoo`. A daemon of a drop on hold is never shown.
pub fn zoo_rows(state: &ZooState, doc: &ZooDoc, habits: &[String], today: &str, now_ms: i64, face: Option<Face>) -> Vec<Row> {
    let r = roster();
    let zoo: &Zoo = &doc.zoo;
    let mut out = Vec::new();
    let account = *state == ZooState::Account;
    if account && !zoo.daemons.is_empty() {
        if let Some((mine, d)) = face.and_then(|f| f.uid).and_then(|uid| zoo.find(uid)).and_then(|o| Some((o, r.shown(&o.id)?))).or_else(|| zoo.paired()) {
            if let Some(f) = face {
                let traits = (mine.seed != 0).then(|| mine.traits()).flatten();
                out.extend(hatch::art(d, traits.as_ref(), f.own, PORTRAIT, &mine.version(), f.mood, f.frame, mine.shiny, None).into_iter().map(|(s, ink)| Row::Text(s, ink)));
                out.push(t(""));
            }
            let levels = &r.rules.bond.levels;
            let next = levels.get(mine.bond as usize + 1).map(|n| format!("{}/{n} xp", mine.xp)).unwrap_or(format!("{} xp", mine.xp));
            let name = mine.title();
            let serial = if mine.name.is_some() { mine.serial.map(|s| format!(" · #{s:04}")).unwrap_or_default() } else { String::new() };
            let paired = if zoo.is_paired(mine) { "paired" } else { "selected" };
            out.push(Row::Text(format!("{name} {} · {}{} · {paired} · bond {} · {next}{serial}", mine.version(), if mine.shiny { "shiny " } else { "" }, d.rarity, mine.bond), Ink::Bold));
            for l in words(&format!("{} · {}", d.lineage(), d.lore), 64) { out.push(Row::Text(l, Ink::Faint)) }
            out.push(t(""));
        }
        let owned: Vec<Shelved> = r.daemons.iter().filter_map(|d| {
            let n = zoo.daemons.iter().filter(|o| o.id == d.id).count();
            (n > 0).then(|| Shelved { id: d.id.clone(), dupes: n.saturating_sub(1) as u32 })
        }).collect();
        let shelf = shelf_lines(r, &owned, None, now_ms);
        let set: Vec<&super::roster::Daemon> = r.daemons.iter().filter(|d| d.drop == r.drops[0].id).collect();
        for (i, line) in shelf.iter().enumerate() {
            if i >= 2 && (i - 2) % 3 == 0 {
                let first = (i - 2) / 3 * 5;
                let colours = set.iter().skip(first).take(5).map(|d| zoo.owned(&d.id).map(|o| d.colour(o.shiny))).collect();
                out.push(Row::Shelf(line.clone(), colours));
            } else { out.push(t(line.clone())) }
        }
        out.push(t(""));
        for d in &r.daemons {
            if r.shown(&d.id).is_none() { continue }
            let all: Vec<_> = zoo.daemons.iter().filter(|o| o.id == d.id).collect();
            if all.is_empty() { continue }
            out.push(Row::Text(format!("{} · {} individuals", d.id, all.len()), Ink::Bold));
            if let Some(cat) = &d.traits {
                let traits: Vec<_> = all.iter().filter_map(|o| o.traits()).collect();
                let colours: Vec<_> = cat.colours.iter().filter(|c| traits.iter().any(|t| t.colour == c.name)).map(|c| c.name.clone()).collect();
                let marks: Vec<_> = cat.marks.iter().filter(|(m, _)| m.is_some() && traits.iter().any(|t| &t.marks == m)).map(|(m, _)| m.clone().unwrap_or_else(|| "none".into())).collect();
                let extras: Vec<_> = cat.extras.iter().filter(|e| e.name.is_some() && traits.iter().any(|t| t.extra == e.name)).map(|e| e.name.clone().unwrap_or_else(|| "none".into())).collect();
                for (label, seen, total) in [("colours", colours, cat.colours.len()), ("markings", marks, cat.marks.iter().filter(|(m, _)| m.is_some()).count()), ("extras", extras, cat.extras.iter().filter(|e| e.name.is_some()).count())] {
                    for line in words(&format!("  {label}: {}/{} · {}", seen.len(), total, seen.join(", ")), 64) { out.push(Row::Text(line, Ink::Faint)) }
                }
            }
            for o in all {
                let selected = face.and_then(|f| f.uid) == Some(o.uid());
                let paired = if zoo.is_paired(o) { " · paired" } else { "" };
                let traits = o.traits();
                let sprite = render::individual_sprite(r, d, traits.as_ref(), r.version_index(&o.version()), "idle", render::Opts::still());
                out.push(Row::Text(format!("{} {sprite:<8} {} {} · bond {} · {} xp{}{paired}", if selected { ">" } else { " " }, o.title(), o.version(), o.bond, o.xp, if o.shiny { " · shiny" } else { "" }), if selected { Ink::Bold } else { Ink::Colour(d.colour(o.shiny)) }));
                if o.seed != 0 { if let Some((flags, rarity)) = o.flags() {
                    for line in words(&format!("  {flags} · {}", super::card::one_in_text(rarity)), 64) { out.push(t(line)) }
                } }
            }
            out.push(t(""));
        }
        out.push(t(""));
    } else {
        // Before the first hatch: the nest (or the egg), and the habits that make it.
        let first = &r.rules.first_egg;
        let progress = render::habit_progress(r, habits, "first");
        let stage = render::egg_stage(progress.0, progress.1, false);
        let known: Vec<&String> = habits.iter().filter(|h| first.habits.iter().any(|x| &x.key == *h)).collect();
        let turn = first.require.iter().all(|k| habits.contains(k));
        let counted = if turn { known.len().min(first.need) } else { known.len().min(first.need.saturating_sub(1)) };
        let head = if account && !zoo.eggs.is_empty() { format!("the first egg is ready   {}", render::egg_line(r, &zoo.eggs[0].kind, "p4", None, "")) }
            else { format!("the nest   {}   {counted} of {} toward the first egg", render::egg_line(r, "first", stage, None, ""), first.need) };
        out.push(Row::Text(head, Ink::Bold));
        out.push(t(format!("  {}, and any {} more:", first.habits.iter().find(|h| first.require.contains(&h.key)).map(|h| h.label.to_lowercase()).unwrap_or_default(), first.need.saturating_sub(first.require.len()))));
        for h in &first.habits {
            let done = habits.contains(&h.key);
            let needed = if first.require.contains(&h.key) { "  (needed)" } else { "" };
            out.push(Row::Text(format!("  [{}] {}{needed}", if done { "x" } else { " " }, h.label), if done { Ink::Plain } else { Ink::Faint }));
        }
        out.push(t(""));
        if *state == ZooState::SignedOut { out.push(Row::Text("sign in to hatch: harness login".into(), Ink::Bold)) }
    }
    if account {
        let eggs = &zoo.eggs;
        if eggs.is_empty() { out.push(Row::Text("no egg waiting".into(), Ink::Faint)) } else {
            let mut kinds: Vec<(String, usize)> = Vec::new();
            for e in eggs { match kinds.iter_mut().find(|(k, _)| *k == e.kind) { Some(k) => k.1 += 1, None => kinds.push((e.kind.clone(), 1)) } }
            let looks = kinds.iter().map(|(k, n)| format!("{} x{n}", render::egg_line(r, k, "p4", None, ""))).collect::<Vec<_>>().join("  ");
            out.push(Row::Text(format!("eggs: {looks} waiting — h hatches"), Ink::Bold));
        }
        if !zoo.daemons.is_empty() || zoo.first_egg {
            let every = r.rules.earn.turn.every;
            let today_n = zoo.progress.days.get(today).copied().unwrap_or(0);
            out.push(t(format!("next egg: {}/{every} turns · today {today_n}/{} (the day's cap)", zoo.progress.turns % every, r.rules.earn.turn.daily_cap)));
        }
        if zoo.first_egg && !zoo.setup_egg {
            out.push(t(format!("habits: {}/{} toward the setup egg", zoo.habits.len(), r.rules.setup_egg.need)));
        }
    }
    // Waiting and earning eggs, each at its own cracking stage. Repeated
    // ready eggs share one plate and keep their count in the heading above.
    let mut drawn = std::collections::HashSet::new();
    for e in super::zoo::eggs_shown(zoo, account, habits, today) {
        if !drawn.insert((e.kind.clone(), e.stage())) { continue }
        out.push(t(format!("{} egg · {}", e.kind, e.words())));
        if let Some(f) = plates::egg_frame(&e.kind, PORTRAIT, e.stage(), face.map(|f| f.frame).unwrap_or(0)) {
            out.extend(plates::paint_egg(&e.kind, f, plates::Light { name: "plain", dim: false }, 3).into_iter().map(|(row, ink)| Row::Text(row, Ink::Paint(ink))));
        }
    }
    out
}

/// What the daemon sees (daemons/README.md): the first-day consent, before anything is watched.
pub fn consent_rows(name: &str) -> Vec<Row> {
    vec![
        Row::Text(format!("What {name} sees"), Ink::Bold), t(""),
        t("It reads, on each of your machines, only that machine's coding agents:"),
        t("  when each agent's turns start and end;"),
        t("  a question an agent waits on, and the dialog on its pane;"),
        t("  the short recap of each finished turn;"),
        t("  your next prompt after a turn, to notice a lesson."),
        t("It never reads a terminal, an Orchestrator's sub-agents, or itself."), t(""),
        t("It writes a journal on that machine (0600, keys and secrets taken out),"),
        t("and lessons in ~/.harness/lessons only on your yes. The backend holds"),
        t("which daemon is paired, the dial, eggs and counts: never your words."), t(""),
        t("At watch, where it starts, it only tells you. It never deletes, restarts,"),
        t("forks or bypasses anything, types into a terminal, approves a push,"),
        t("force, rm -r, sudo, deploy, publish, drop or merge, or answers a question"),
        t("the agent asks you."), t(""),
        Row::Text(format!("y  let {name} watch     n  not now     Esc  ask me later"), Ink::Bold),
    ]
}

fn ink_style(ink: Ink, plain: bool) -> Style {
    let c = |c: Color| if plain { Style::default() } else { Style::default().fg(c) };
    match ink {
        Ink::Plain => Style::default(),
        Ink::Faint => Style::default().add_modifier(Modifier::DIM),
        Ink::Bold => Style::default().add_modifier(Modifier::BOLD),
        Ink::Colour(x) => c(Color::Indexed(x)),
        // The grue brings its own pitch black wherever it is drawn.
        Ink::Dark(x) => if plain { Style::default() } else { Style::default().fg(Color::Indexed(x)).bg(Color::Black) },
        Ink::Cyan => c(Color::Cyan).add_modifier(Modifier::BOLD),
        Ink::Yellow => c(Color::Yellow).add_modifier(Modifier::BOLD),
        // Inked glyph by glyph (put_rows).
        Ink::Plate(_) | Ink::Paint(_) => Style::default(),
    }
}

/// A box over the window, tmux's popup's single lines, its title over the top border.
fn frame_box(buf: &mut Buffer, area: Rect, title: &str, fill: Style) -> Rect {
    for y in area.y..area.y + area.height { for x in area.x..area.x + area.width { if let Some(c) = buf.cell_mut((x, y)) { c.reset(); c.set_symbol(" "); c.set_style(fill); } } }
    if area.width < 4 || area.height < 3 { return area }
    let (x1, y1) = (area.x + area.width - 1, area.y + area.height - 1);
    for x in area.x + 1..x1 { buf.set_string(x, area.y, "─", fill); buf.set_string(x, y1, "─", fill) }
    for y in area.y + 1..y1 { buf.set_string(area.x, y, "│", fill); buf.set_string(x1, y, "│", fill) }
    buf.set_string(area.x, area.y, "┌", fill); buf.set_string(x1, area.y, "┐", fill);
    buf.set_string(area.x, y1, "└", fill); buf.set_string(x1, y1, "┘", fill);
    if !title.is_empty() { let t: String = title.chars().take(area.width.saturating_sub(4) as usize).collect(); buf.set_string(area.x + 2, area.y, &t, fill.add_modifier(Modifier::BOLD)) }
    Rect::new(area.x + 2, area.y + 1, area.width.saturating_sub(4), area.height.saturating_sub(2))
}

fn centred(area: Rect, w: u16, h: u16) -> Rect {
    let (w, h) = (w.min(area.width), h.min(area.height));
    Rect::new(area.x + (area.width - w) / 2, area.y + (area.height - h) / 2, w, h)
}

fn put_rows(buf: &mut Buffer, inner: Rect, rows: &[Row], top: usize, base: Style, mode: Mode, centre: bool) {
    let plain = mode == Mode::Plain;
    let w = rows.iter().map(|r| r.text().len()).max().unwrap_or(0) as u16;
    let x0 = if centre && w < inner.width { inner.x + (inner.width - w) / 2 } else { inner.x };
    for (i, row) in rows.iter().skip(top).take(inner.height as usize).enumerate() {
        let y = inner.y + i as u16;
        match row {
            // A plate's row: each glyph its ink (a space, or a card's border, the row's own style).
            Row::Text(s, Ink::Plate(p)) => {
                for (i, ch) in s.chars().enumerate().take(inner.width as usize) {
                    let style = plates::style(*p, ch, mode).map(|g| base.patch(g)).unwrap_or(base);
                    buf.set_string(x0 + i as u16, y, ch.to_string(), style);
                }
            }
            Row::Text(s, Ink::Paint(p)) => {
                for (i, ch) in s.chars().enumerate().take(inner.width as usize) {
                    let style = p.style(i, ch, mode).map(|g| base.patch(g)).unwrap_or(base);
                    buf.set_string(x0 + i as u16, y, ch.to_string(), style);
                }
            }
            Row::Text(s, ink) => { buf.set_stringn(x0, y, s, inner.width as usize, base.patch(ink_style(ink.clone(), plain))); }
            Row::Shelf(s, colours) => {
                for (c, chunk) in s.as_bytes().chunks(10).enumerate() {
                    let x = x0 + (c * 10) as u16;
                    if x >= inner.x + inner.width { break }
                    let ink = colours.get(c).copied().flatten().map(Ink::Colour).unwrap_or(Ink::Faint);
                    buf.set_stringn(x, y, String::from_utf8_lossy(chunk), (inner.x + inner.width - x) as usize, base.patch(ink_style(ink, plain)));
                }
            }
        }
    }
}

/// Wrap words to a width.
fn words(text: &str, width: usize) -> Vec<String> {
    let mut out = Vec::new();
    let mut line = String::new();
    for w in text.split_whitespace() {
        if !line.is_empty() && line.len() + 1 + w.len() > width { out.push(std::mem::take(&mut line)) }
        if !line.is_empty() { line.push(' ') }
        line.push_str(w);
    }
    if !line.is_empty() { out.push(line) }
    out
}

/// Wrap text to a width (hard-cutting a word longer than the line), keeping blank lines.
pub fn wrap(text: &str, width: usize) -> Vec<String> {
    let width = width.max(8);
    let mut out = Vec::new();
    for raw in text.lines() {
        let chars: Vec<char> = raw.chars().map(|c| if c == '\t' { ' ' } else { c }).collect();
        if chars.is_empty() { out.push(String::new()); continue }
        for chunk in chars.chunks(width) { out.push(chunk.iter().collect()) }
    }
    out
}

/// Draw what is over the window; true when a popup has the screen (no cursor).
pub fn draw(buf: &mut Buffer, app: &mut App) -> bool {
    let area = *buf.area();
    if area.width < 10 || area.height < 5 { return false }
    let mode = Mode::now();
    let plain = mode == Mode::Plain;
    let body = app.body();
    // The brief on return, above the status line, while it lasts.
    brief(buf, app, body, mode);
    let mut took = false;
    match app.daemons.overlay.take() {
        None => {}
        Some(Overlay::Hatch(mut rv)) => {
            let now = Instant::now();
            // A plate at the reveal size when all of the reveal fits in the box, else the portrait size.
            let room = Rect::new(area.x + 2, area.y + 1, area.width.saturating_sub(4), area.height.saturating_sub(2));
            rv.size = hatch::fit(&rv, room.width as usize, room.height as usize);
            if let Some(o) = rv.outcome.as_ref().and_then(|o| app.daemons.zoo.zoo.find(if o.uid.is_empty() { &o.daemon } else { &o.uid })).cloned() {
                for size in [rv.size, PORTRAIT] {
                    if let Some(art) = super::art::get(app, &o, size, &o.version(), "idle") { rv.offer(size, art, now) }
                }
            }
            let f = hatch::frame(&rv, now);
            let fill = if f.black && !plain { Style::default().bg(Color::Black).fg(Color::Gray) } else { Style::default() };
            let inner = frame_box(buf, area, " hatch ", fill);
            let rows: Vec<Row> = f.rows.iter().map(|(s, ink)| Row::Text(s.clone(), ink.clone())).collect();
            // A fixed place (the reveal's tallest moment, or the card's height; its width): rows are
            // added below, and the art never moves.
            let tallest = hatch::extent(&rv, rv.size).1.max(26) as u16;
            let (w, h) = (hatch::width(rv.size) as u16, rows.len() as u16);
            let top = inner.height.saturating_sub(h.max(tallest)) / 2;
            let region = Rect::new(inner.x + inner.width.saturating_sub(w) / 2, inner.y + top, w.min(inner.width), h.min(inner.height - top));
            if rv.done(now) && rv.naming() {
                let at = rows.iter().position(|r| r.text().trim_start().starts_with("name it:")).unwrap_or(rows.len());
                let foot = &rows[at..];
                let footer_height = (foot.len() as u16).min(inner.height);
                let height = inner.height.saturating_sub(footer_height);
                rv.card_top = rv.card_top.min(at.saturating_sub(height as usize));
                put_rows(buf, Rect::new(region.x, inner.y, region.width, height), &rows[..at], rv.card_top, fill, mode, false);
                put_rows(buf, Rect::new(region.x, inner.y + height, region.width, footer_height), foot, 0, fill, mode, false);
            } else {
                put_rows(buf, region, &rows, 0, fill, mode, false);
            }
            if let Some(ms) = hatch::next_in(&rv, now) { animate(app, ms) }
            app.daemons.overlay = Some(Overlay::Hatch(rv));
            took = true;
        }
        Some(Overlay::Zoo) => {
            let clock = super::zoo::now_ms().max(0) as u64;
            let moving = super::state::motion(app) && app.terminal_focused;
            let count = app.daemons.zoo.zoo.shown().count();
            app.daemons.zoo_selected = app.daemons.zoo_selected.min(count.saturating_sub(1));
            let selected = app.daemons.zoo.zoo.shown().nth(app.daemons.zoo_selected).map(|(o, _)| o.clone());
            let mood = if selected.as_ref().map(|o| app.daemons.zoo.zoo.pair_uid() == Some(o.uid())).unwrap_or(false) { super::state::mood(app) } else { "idle" };
            let own = selected.as_ref().and_then(|o| super::art::get(app, o, PORTRAIT, &o.version(), mood));
            let loop_len = own.as_ref().map(|a| a.frames.len()).unwrap_or_else(|| selected.as_ref().map(|o| plates::frames(&o.id, PORTRAIT, &o.version(), mood).len()).unwrap_or(0));
            let frame_ms = own.as_ref().map(|a| a.frame_ms).unwrap_or(plates::plates().frame_ms).max(1);
            let face = Face { mood, frame: if moving && loop_len > 0 { (clock / frame_ms) as usize % loop_len } else { 0 }, own: own.as_deref(), uid: selected.as_ref().map(|o| o.uid()) };
            let d = &app.daemons;
            let rows = zoo_rows(&d.zoo_state, &d.zoo, &d.habits(), &super::zoo::local_today(), super::zoo::now_ms(), Some(face));
            let w = rows.iter().map(|r| r.text().len()).max().unwrap_or(40) as u16 + 6;
            let rect = centred(body, w.max(56), (rows.len() as u16).saturating_add(3));
            let inner = frame_box(buf, rect, " zoo ", Style::default());
            let room = inner.height.saturating_sub(3) as usize;
            let top = app.daemons.zoo_top.min(rows.len().saturating_sub(room));
            app.daemons.zoo_top = top;
            put_rows(buf, Rect::new(inner.x, inner.y, inner.width, room as u16), &rows, top, Style::default(), mode, false);
            let foot = ["j/k select · Enter pair · h hatch · c card", "PgUp/PgDn scroll · Esc close"];
            for (i, text) in foot.iter().take(inner.height as usize).enumerate() {
                buf.set_stringn(inner.x, inner.y + inner.height.saturating_sub(2) + i as u16, text, inner.width as usize, Style::default().add_modifier(Modifier::DIM));
            }
            if moving { animate(app, Duration::from_millis(frame_ms)) }
            app.daemons.overlay = Some(Overlay::Zoo);
            took = true;
        }
        Some(Overlay::Detail { id, title, text, top, keyed }) => {
            let w = (body.width.saturating_sub(4)).min(100);
            let lines = wrap(&text, w.saturating_sub(4) as usize);
            let foot = if keyed { keys_named(app, &id) } else { "Esc close".into() };
            let h = (lines.len() as u16 + 4).min(body.height.saturating_sub(1)).max(5);
            let rect = centred(body, w, h);
            let inner = frame_box(buf, rect, &format!(" {title} "), Style::default());
            let room = inner.height.saturating_sub(2) as usize;
            let top = top.min(lines.len().saturating_sub(room));
            let rows: Vec<Row> = lines.iter().map(|l| t(l.clone())).collect();
            put_rows(buf, Rect::new(inner.x, inner.y, inner.width, room as u16), &rows, top, Style::default(), mode, false);
            let more = if top + room < lines.len() { format!("  ({} more — j/k)", lines.len() - top - room) } else { String::new() };
            buf.set_stringn(inner.x, inner.y + inner.height - 1, format!("{foot}{more}"), inner.width as usize, Style::default().add_modifier(Modifier::DIM));
            // All of it has been on screen: now a key on it may count.
            if top + room >= lines.len() && keyed { super::brain::detail_seen(app, &id) }
            app.daemons.overlay = Some(Overlay::Detail { id, title, text, top, keyed });
            took = true;
        }
        Some(Overlay::Consent { name }) => {
            let rows = consent_rows(&name);
            let w = rows.iter().map(|r| r.text().len()).max().unwrap_or(40) as u16 + 6;
            let inner = frame_box(buf, centred(body, w, rows.len() as u16 + 2), " consent ", Style::default());
            put_rows(buf, inner, &rows, 0, Style::default(), mode, false);
            app.daemons.overlay = Some(Overlay::Consent { name });
            took = true;
        }
    }
    // The daemon key table is up: its keys, as which-key shows the prefix's — and it was a look.
    let up = app.key_table.as_deref() == Some("daemon");
    if up && !app.daemons.table_up { super::hooks::table_opened(app) }
    app.daemons.table_up = up;
    if !took && up { table(buf, app, body) }
    took
}

/// Draw again in `after` (a plate's next frame, the reveal's next moment) — one timer at a time, so
/// frames drawn for other reasons never start a second.
fn animate(app: &mut App, after: Duration) {
    let now = Instant::now();
    if app.daemons.frame_due.map(|t| t > now).unwrap_or(false) { return }
    app.daemons.frame_due = Some(now + after);
    super::brain::wake(app, after.as_millis() as u64);
}

/// The keys a line's detail answers with, named: `y Yes · n No · g open · Esc close`.
fn keys_named(app: &App, id: &str) -> String {
    let b = &app.daemons.brain;
    let line = b.line.as_ref().filter(|l| l.id == id).or_else(|| b.brief.as_ref().and_then(|br| br.items.iter().find(|l| l.id == id)));
    let Some(line) = line else { return "Esc close".into() };
    let mut keys: Vec<String> = line.actions.iter().map(|a| format!("{} {}", a.key, if a.label.is_empty() { &a.choice } else { &a.label })).collect();
    if line.confirm.is_some() { keys = vec!["y yes".into(), "n keep it as it is".into()] }
    let armed = if line.armed() { "" } else { "  (keys arm in a moment)" };
    format!("{} · Esc close{armed}", keys.join(" · "))
}

fn brief(buf: &mut Buffer, app: &mut App, body: Rect, mode: Mode) {
    let Some(b) = app.daemons.brain.brief.as_ref() else { return };
    if Instant::now() >= b.until { app.daemons.brain.brief = None; return }
    if app.daemons.overlay.is_some() || app.modal.is_some() { return }
    let mut rows = vec![Row::Text(b.line.clone(), Ink::Bold)];
    for item in &b.items { rows.push(Row::Text(format!("{}{}", item.keys(), item.words()), if item.keyed() { Ink::Bold } else { Ink::Plain })) }
    let prefix = app.keymap.key_for_name("switch-client -T daemon").unwrap_or_else(|| "C-b Z".into());
    rows.push(Row::Text(format!("{prefix} y/n/g answers the first · Esc closes"), Ink::Faint));
    let w = (rows.iter().map(|r| r.text().len()).max().unwrap_or(20) as u16 + 4).min(body.width);
    let h = (rows.len() as u16 + 2).min(body.height);
    let rect = Rect::new(body.x + body.width - w, body.y + body.height - h, w, h);
    let inner = frame_box(buf, rect, &format!(" {} ", app.daemons.name()), Style::default());
    put_rows(buf, inner, &rows, 0, Style::default(), mode, false);
    let ids: Vec<String> = app.daemons.brain.brief.as_ref().map(|b| b.items.iter().map(|l| l.id.clone()).collect()).unwrap_or_default();
    for id in ids { super::brain::drawn(app, &id) }
}

/// The daemon key table's keys, while it is up.
fn table(buf: &mut Buffer, app: &App, body: Rect) {
    let Some(list) = app.keymap.named.get("daemon") else { return };
    let items: Vec<(String, String)> = list.iter().map(|b| (crate::keys::name(&b.chord), if b.note.is_empty() { b.command.clone() } else { b.note.clone() })).collect();
    let kw = items.iter().map(|(k, _)| k.len()).max().unwrap_or(1);
    let w = ((kw + items.iter().map(|(_, n)| n.len()).max().unwrap_or(20) + 5) as u16).min(body.width);
    let h = (items.len() as u16 + 2).min(body.height);
    let rect = Rect::new(body.x, body.y + body.height - h, w, h);
    let title = format!(" {} ", app.daemons.name());
    let inner = frame_box(buf, rect, &title, Style::default());
    for (i, (k, n)) in items.iter().enumerate().take(inner.height as usize) {
        let y = inner.y + i as u16;
        buf.set_string(inner.x, y, format!("{k:>kw$}"), Style::default().fg(crate::theme::ACCENT).add_modifier(Modifier::BOLD));
        buf.set_stringn(inner.x + kw as u16 + 1, y, n, inner.width.saturating_sub(kw as u16 + 1) as usize, Style::default());
    }
}

/// A key while a popup is open; true when it was the popup's.
pub fn key(app: &mut App, key: &KeyEvent) -> bool {
    let Some(overlay) = app.daemons.overlay.as_mut() else { return false };
    let ch = match key.code { KeyCode::Char(c) if !key.modifiers.intersects(KeyModifiers::CONTROL | KeyModifiers::ALT) => Some(c), _ => None };
    let esc = key.code == KeyCode::Esc || (key.code == KeyCode::Char('c') && key.modifiers.contains(KeyModifiers::CONTROL));
    match overlay {
        Overlay::Hatch(rv) => {
            let now = Instant::now();
            if esc { close_hatch(app, false); return true }
            if rv.done(now) {
                if rv.naming() {
                    if rv.saving { return true }
                    match key.code {
                        KeyCode::PageDown => rv.card_top += 5,
                        KeyCode::PageUp => rv.card_top = rv.card_top.saturating_sub(5),
                        KeyCode::Enter => {
                            let uid = rv.outcome.as_ref().map(|o| o.uid.clone()).unwrap_or_default();
                            let name = rv.name.trim().to_string();
                            let next = rv.consent_next;
                            if name.is_empty() || uid.is_empty() { close_hatch(app, next) }
                            else { rv.saving = true; rv.name_error = None; super::hooks::name_hatch(app, uid, name) }
                        }
                        KeyCode::Backspace => { rv.name.pop(); }
                        _ => if let Some(c) = ch { hatch::type_name(rv, c) },
                    }
                    return true
                }
                let next = rv.consent_next; close_hatch(app, next); return true
            }
            if rv.skippable && rv.outcome.is_some() { rv.skipped = true }
            true
        }
        Overlay::Zoo => {
            match key.code {
                KeyCode::Down | KeyCode::Char('j') => { app.daemons.zoo_selected = (app.daemons.zoo_selected + 1).min(app.daemons.zoo.zoo.shown().count().saturating_sub(1)); app.daemons.zoo_top = 0; }
                KeyCode::Up | KeyCode::Char('k') => { app.daemons.zoo_selected = app.daemons.zoo_selected.saturating_sub(1); app.daemons.zoo_top = 0; }
                KeyCode::PageDown | KeyCode::Char(' ') => app.daemons.zoo_top += 10,
                KeyCode::PageUp => app.daemons.zoo_top = app.daemons.zoo_top.saturating_sub(10),
                KeyCode::Enter => { super::hooks::pair_selected(app) }
                KeyCode::Char('h') => { app.daemons.overlay = None; super::hooks::hatch(app, None) }
                KeyCode::Char('c') => {
                    let uid = app.daemons.zoo.zoo.shown().nth(app.daemons.zoo_selected).map(|(o, _)| o.uid().to_string());
                    super::hooks::copy_individual_card(app, uid.as_deref());
                }
                _ if esc || matches!(ch, Some('q' | 'z')) => app.daemons.overlay = None,
                _ => {}
            }
            true
        }
        Overlay::Detail { top, keyed, .. } => {
            let keyed = *keyed;
            match key.code {
                KeyCode::Down | KeyCode::Char('j') | KeyCode::Enter => *top += 1,
                KeyCode::Up | KeyCode::Char('k') => *top = top.saturating_sub(1),
                KeyCode::PageDown | KeyCode::Char(' ') => *top += 10,
                KeyCode::PageUp => *top = top.saturating_sub(10),
                _ if esc || ch == Some('q') => app.daemons.overlay = None,
                _ => if let Some(c @ ('y' | 'n' | 's' | 'g')) = ch { if keyed { super::brain::key(app, c) } }
            }
            true
        }
        Overlay::Consent { .. } => {
            match ch {
                Some('y') => { app.daemons.overlay = None; super::hooks::consent(app, true) }
                Some('n') => { app.daemons.overlay = None; super::hooks::consent(app, false) }
                _ if esc => app.daemons.overlay = None,
                _ => {}
            }
            true
        }
    }
}

/// The reveal closes: the card stays in the zoo, and the daemon takes the status line — after the
/// consent, the first time.
pub fn close_hatch(app: &mut App, consent: bool) {
    app.daemons.overlay = None;
    app.daemons.blink("slow");
    if consent && app.daemons.zoo.zoo.consent.is_none() && app.daemons.zoo.zoo.paired().is_some() {
        app.daemons.overlay = Some(Overlay::Consent { name: app.daemons.name() });
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn the_zoo_as_rows() {
        let doc: ZooDoc = serde_json::from_value(json!({ "revision": 2, "zoo": { "daemons": [{ "id": "tim", "bond": 1, "xp": 60, "version": "0.1", "serial": 42 }, { "uid": "yak-one", "id": "yak", "version": "1.0", "shiny": true }, { "uid": "yak-two", "id": "yak", "version": "0.1" }, { "id": "vim", "version": "2.0" }],
            "eggs": [{ "id": "e", "kind": "turn" }, { "id": "f", "kind": "turn" }], "pair": "tim", "habits": ["turn", "split", "find"], "firstEgg": true, "progress": { "turns": 52, "days": { "2026-09-26": 4 } } } })).unwrap();
        let now = super::super::card::day_number("2026-09-27").unwrap() * 86_400_000;
        let rows = zoo_rows(&ZooState::Account, &doc, &[], "2026-09-26", now, None);
        let text: Vec<&str> = rows.iter().map(Row::text).collect();
        assert_eq!(text[0], "tim #0042 0.1 · common · paired · bond 1 · 60/150 xp");
        assert!(text.contains(&"zoo: drop 1 init  2/9"));
        assert!(text.iter().any(|l| l.starts_with("~(o o)~   [ ? ]")), "{text:?}");
        assert!(text.iter().any(|l| l.contains("yak x2")));
        assert!(text.iter().any(|l| l.contains("yak 1.0 · bond 0 · 0 xp · shiny")), "{text:?}");
        // vim's drop is on hold: a record of it is never shown.
        assert!(!text.iter().any(|l| l.contains("vim ") && !l.contains("Named the way vim")), "{text:?}");
        assert!(text.contains(&"eggs: \\_(oo)_/ x2 waiting — h hatches"));
        assert!(text.contains(&"next egg: 12/40 turns · today 4/20 (the day's cap)"));
        assert!(text.contains(&"habits: 3/6 toward the setup egg"));
        // With a face: tim's portrait plate over it all, in its mood and frame, down its gradient.
        let faced = zoo_rows(&ZooState::Account, &doc, &[], "2026-09-26", now, Some(Face { mood: "work", frame: 2, own: None, uid: None }));
        let plate = plates::rows("tim", PORTRAIT, "0.1", "work", 2);
        let tim = roster().daemon("tim").unwrap();
        for (i, row) in plate.iter().enumerate() {
            assert!(matches!(&faced[i], Row::Text(t, Ink::Plate(p)) if t == row && *p == plates::PlateInk::of(tim, false, i, plate.len())), "{:?}", faced[i]);
        }
        assert_eq!(faced[plate.len()].text(), "");
        assert_eq!(faced[plate.len() + 1].text(), text[0]);
        // Signed out: the nest, its habits, and how to hatch.
        let nest = zoo_rows(&ZooState::SignedOut, &ZooDoc::default(), &["split".into(), "find".into()], "2026-09-26", 0, Some(Face { mood: "idle", frame: 0, own: None, uid: None }));
        let text: Vec<&str> = nest.iter().map(Row::text).collect();
        assert_eq!(text[0], "the nest   \\_(*')_/   2 of 3 toward the first egg");
        assert!(text.contains(&"  [ ] Finish a turn in a harness  (needed)") && text.contains(&"  [x] Run two harnesses side by side"));
        assert!(text.contains(&"sign in to hatch: harness login"));
    }

    #[test]
    fn a_plate_row_is_inked_glyph_by_glyph() {
        let tim = roster().daemon("tim").unwrap();
        let ink = Ink::Plate(plates::PlateInk::of(tim, false, 0, 2));
        let mut buf = Buffer::empty(Rect::new(0, 0, 12, 1));
        put_rows(&mut buf, Rect::new(0, 0, 12, 1), &[Row::Text("|.#@ |".into(), ink.clone())], 0, Style::default(), Mode::Xterm, false);
        let cell = |x: u16| buf.cell((x, 0)).unwrap().clone();
        // The border and the space keep the row's style; ink takes the plate's.
        assert_eq!((cell(0).symbol(), cell(0).fg), ("|", Color::Reset));
        // At 256 colours: the row's nearest xterm colour (tim's top, 213), dim below 0.6, bold above 1.
        assert_eq!((cell(2).symbol(), cell(2).fg, cell(2).modifier), ("#", Color::Indexed(213), Modifier::empty()));
        assert_eq!((cell(1).fg, cell(1).modifier), (Color::Indexed(213), Modifier::DIM));
        assert_eq!((cell(3).fg, cell(3).modifier), (Color::Indexed(213), Modifier::BOLD));
        assert_eq!((cell(4).symbol(), cell(4).fg), (" ", Color::Reset));
        // NO_COLOR: the plain text.
        let mut plain = Buffer::empty(Rect::new(0, 0, 12, 1));
        put_rows(&mut plain, Rect::new(0, 0, 12, 1), &[Row::Text("|.#@ |".into(), ink.clone())], 0, Style::default(), Mode::Plain, false);
        assert!((0..6).all(|x| plain.cell((x, 0)).unwrap().fg == Color::Reset && plain.cell((x, 0)).unwrap().modifier.is_empty()));
        assert_eq!((0..6).map(|x| plain.cell((x, 0)).unwrap().symbol().to_string()).collect::<String>(), "|.#@ |");
    }

    #[test]
    fn detail_wraps_without_losing_a_word() {
        let w = wrap("git push --force origin main\n\nsecond", 10);
        assert_eq!(w, vec!["git push -", "-force ori", "gin main", "", "second"]);
    }
}
