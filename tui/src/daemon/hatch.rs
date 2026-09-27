//! Hatching, in the terminal (daemons/README.md "Hatching"; desktop/design/daemons.md "The reveal").
//!
//! The egg wobbles until harnessd answers `zoo.hatch`, then tells the rarity at the crack — a rare's
//! shell glows cyan, a legendary's pop throws yellow `*'.` sparks, a secret's stage goes pitch black
//! first — pops, and the hatchling's 0.1 portrait appears as `#` in the faint colour for 1200 ms,
//! fills with its colour — a filled daemon's plate in its gradient, its idle loop running a frame
//! every frameMs; line art blinks —; its name types in as a banner (banner.json), then the rarity
//! stamp, `fork() returned 0.`, its first words, and the card. A duplicate has no reveal of a new
//! name: it says it merged (`another tux. +150 xp.`), and a level-up morphs the portrait to the new
//! version. Reduce Motion (`set -g @daemon-motion off`) goes straight to the card.
//!
//! A plate shows at its `reveal` size (56 columns) when the whole reveal fits the terminal, else at
//! its `portrait` size (28): `fit` decides, from the reveal's tallest moment, so nothing moves.
//!
//! `frame` is a pure function of the reveal and the time, so the tests can read any moment of it.

use std::time::{Duration, Instant};

use super::card::{card_art, card_lines, CardOpts};
use super::plates::{self, PlateInk, PORTRAIT, REVEAL};
use super::render::{self, Opts};
use super::roster::{roster, Daemon};

/// Two wobbles at least, then until harnessd answers.
const WOBBLE: u64 = 120;
const MIN_WOBBLE: u64 = 960;

#[derive(Clone, Debug, Default)]
pub struct Outcome {
    pub daemon: String,
    pub shiny: bool,
    pub serial: Option<u64>,
    pub duplicate: bool,
    pub xp: u64,
    /// A duplicate that grew it: (bond, version) — and the version it had.
    pub grew: Option<(u32, String)>,
    pub old_version: String,
    pub hatched: Option<String>,
    pub nickname: Option<String>,
    pub total_xp: u64,
    /// Now shiny because this duplicate was.
    pub became_shiny: bool,
    /// How many of it you have now (the original and the duplicates merged into it).
    pub count: u32,
}

#[derive(Clone, Debug)]
pub struct Reveal {
    pub egg_kind: String,
    pub started: Instant,
    pub answered: Option<Instant>,
    pub outcome: Option<Outcome>,
    pub error: Option<String>,
    pub motion: bool,
    /// Any key skips to the card (from the fourth hatch on).
    pub skippable: bool,
    pub skipped: bool,
    /// After the card: what the daemon sees, until the person has answered it once.
    pub consent_next: bool,
    /// The size a plate shows at: `reveal` when the terminal has room for all of it, else `portrait`.
    pub size: &'static str,
}

/// How a row is drawn: its ink. A plate's row is inked glyph by glyph (plates.rs).
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Ink { Plain, Faint, Bold, Colour(u8), Dark(u8), Cyan, Yellow, Plate(PlateInk) }

#[derive(Clone, Debug, Default)]
pub struct Frame {
    pub rows: Vec<(String, Ink)>,
    /// The stage is pitch black (a secret).
    pub black: bool,
    /// The card is up.
    #[cfg_attr(not(test), allow(dead_code))]
    pub done: bool,
}

impl Reveal {
    pub fn new(egg_id: &str, egg_kind: &str, motion: bool, skippable: bool, consent_next: bool) -> Reveal {
        let _ = egg_id;
        Reveal { egg_kind: egg_kind.into(), started: Instant::now(), answered: None, outcome: None, error: None, motion, skippable, skipped: false, consent_next, size: PORTRAIT }
    }

    /// When the wobble ends (ms from the start): past two wobbles and the answer, on a wobble's end.
    fn wobble_end(&self) -> Option<u64> {
        let answered = self.answered?.saturating_duration_since(self.started).as_millis() as u64;
        let at = answered.max(MIN_WOBBLE);
        Some(at.div_ceil(WOBBLE * 4) * WOBBLE * 4)
    }

    /// The reveal's length (ms from the start), once answered.
    pub fn length(&self) -> Option<u64> {
        let w = self.wobble_end()?;
        let o = self.outcome.as_ref()?;
        Some(w + if o.duplicate { if o.grew.is_some() { 2600 } else { 1700 } } else { 4200 })
    }

    pub fn done(&self, now: Instant) -> bool {
        if self.error.is_some() { return true }
        if self.outcome.is_some() && (self.skipped || !self.motion) { return true }
        self.length().map(|l| now.saturating_duration_since(self.started).as_millis() as u64 >= l).unwrap_or(false)
    }
}

fn rarity(id: &str) -> String { roster().daemon(id).map(|d| d.rarity.clone()).unwrap_or_default() }

/// The egg, `dx` columns over (-1, 0, 1), cracked `crack` times (0, 1, 2). Every row is as wide as
/// the egg and its wobble, so centring it never undoes the wobble.
fn egg(dx: i32, crack: u8) -> Vec<String> {
    let mut rows: Vec<String> = roster().rules.egg.clone();
    if crack >= 1 { rows[2] = "     |  /\\  |".into() }
    if crack >= 2 { rows[2] = "     |/\\/\\/\\|".into(); rows[3] = "     |\\    /|".into() }
    let wide = rows.iter().map(String::len).max().unwrap_or(0) + 2;
    rows.into_iter().map(|r| format!("{:<wide$}", format!("{}{r}", " ".repeat((1 + dx).max(0) as usize)))).collect()
}

/// The top gone: the shell's lower half, and its lid flying off up and to the right.
fn popped() -> Vec<String> {
    vec![
        "            .--.".into(),
        "           /    \\".into(),
        "          |/\\/\\/\\|".into(),
        "".into(),
        "     |\\/\\/\\/|".into(),
        "      \\    /".into(),
        "   \\___'--'___/".into(),
    ]
}

fn sparks() -> Vec<String> { vec!["   *  '  .   *   .  '  *".into(), "  .   *    '    .   *".into()] }

/// Every drawn cell, as `#`.
fn hashed(rows: &[String]) -> Vec<String> { rows.iter().map(|r| super::card::silhouette(r)).collect() }

/// A daemon's portrait as rows in its ink: a plate at `size` (the mood's loop, frame `frame`) in its
/// gradient, or line art in its colour (`lid` while it blinks).
pub fn art(d: &Daemon, size: &str, version: &str, mood: &str, frame: usize, shiny: bool, lid: Option<&str>) -> Vec<(String, Ink)> {
    if d.plate {
        return PlateInk::rows(d, shiny, plates::rows(&d.id, size, version, mood, frame)).into_iter().map(|(r, ink)| (r, Ink::Plate(ink))).collect();
    }
    let colour = d.colour(shiny);
    render::portrait(roster(), d, version, mood, Opts { t: 0, lid, motion: false }).into_iter().map(|r| (r, Ink::Colour(colour))).collect()
}

/// Rows of text, without their ink.
fn texts(rows: &[(String, Ink)]) -> Vec<String> { rows.iter().map(|(r, _)| r.clone()).collect() }

/// A duplicate's level-up: of the cells that differ, a quarter more each frame, in ordered-dither
/// order, from the old version's portrait to the new one's.
pub fn morph(old: &[String], new: &[String], step: u8) -> Vec<String> {
    const BAYER: [[u8; 4]; 4] = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]];
    let h = old.len().max(new.len());
    let w = old.iter().chain(new.iter()).map(String::len).max().unwrap_or(0);
    (0..h).map(|y| {
        let a: Vec<char> = format!("{:<w$}", old.get(y).map(String::as_str).unwrap_or("")).chars().collect();
        let b: Vec<char> = format!("{:<w$}", new.get(y).map(String::as_str).unwrap_or("")).chars().collect();
        (0..w).map(|x| if BAYER[y % 4][x % 4] < step * 4 { b[x] } else { a[x] }).collect::<String>().trim_end().to_string()
    }).collect()
}

/// How wide the reveal is: the card, and a margin.
pub const WIDTH: usize = 44;

/// How wide the reveal is at a plate size: the card's width, or a reveal plate's and a margin.
pub fn width(size: &str) -> usize {
    if size == REVEAL { WIDTH.max(roster().rules.plate.cols.get(REVEAL).copied().unwrap_or(56) + 2) } else { WIDTH }
}

/// Two rows of one block: the same ink, or rows of one plate.
fn one_block(a: Ink, b: Ink) -> bool {
    match (a, b) { (Ink::Plate(x), Ink::Plate(y)) => x.same_plate(&y), _ => a == b }
}

/// Each block (a run of rows in one ink, between blank rows) centred in the reveal's width, and a
/// line longer than it wrapped: the art keeps its shape and nothing jumps as rows are added.
fn centre(rows: Vec<(String, Ink)>, width: usize) -> Vec<(String, Ink)> {
    let mut wrapped: Vec<(String, Ink)> = Vec::new();
    for (r, ink) in rows {
        if r.len() <= width - 2 { wrapped.push((r, ink)); continue }
        let mut line = String::new();
        for w in r.split(' ') {
            if !line.is_empty() && line.len() + 1 + w.len() > width - 2 { wrapped.push((std::mem::take(&mut line), ink)) }
            if !line.is_empty() { line.push(' ') }
            line.push_str(w);
        }
        if !line.is_empty() { wrapped.push((line, ink)) }
    }
    let mut out = Vec::with_capacity(wrapped.len());
    let mut i = 0;
    while i < wrapped.len() {
        let ink = wrapped[i].1;
        let mut j = i;
        while j < wrapped.len() && one_block(wrapped[j].1, ink) && !wrapped[j].0.is_empty() { j += 1 }
        if j == i { out.push(wrapped[i].clone()); i += 1; continue }
        let w = wrapped[i..j].iter().map(|(r, _)| r.len()).max().unwrap_or(0);
        let pad = " ".repeat(width.saturating_sub(w) / 2);
        for (r, ink) in &wrapped[i..j] { out.push((format!("{pad}{r}"), *ink)) }
        i = j;
    }
    out
}

/// What the reveal shows at `now`, laid out in its width.
pub fn frame(rv: &Reveal, now: Instant) -> Frame {
    let f = raw(rv, now);
    Frame { rows: centre(f.rows, width(rv.size)), ..f }
}

/// How much room the reveal takes at a plate size, once harnessd has answered: the widest and the
/// tallest it gets (the last moment before the card, and the card), so it is laid out once.
pub fn extent(rv: &Reveal, size: &'static str) -> (usize, usize) {
    let mut probe = rv.clone();
    probe.size = size;
    probe.motion = true;
    probe.skipped = false;
    let Some(len) = probe.length() else { return (width(size), 0) };
    let (mut w, mut h) = (width(size), 0);
    for ms in [len.saturating_sub(1), len] {
        let f = frame(&probe, probe.started + Duration::from_millis(ms));
        h = h.max(f.rows.len());
        w = w.max(f.rows.iter().map(|(r, _)| r.len()).max().unwrap_or(0));
    }
    (w, h)
}

/// The size a plate shows at in `width` x `height`: `reveal` when all of the reveal fits, else
/// `portrait`. Line art has one size.
pub fn fit(rv: &Reveal, width: usize, height: usize) -> &'static str {
    let filled = rv.outcome.as_ref().and_then(|o| roster().daemon(&o.daemon)).map(|d| d.plate).unwrap_or(false);
    if !filled { return PORTRAIT }
    let (w, h) = extent(rv, REVEAL);
    if w <= width && h <= height { REVEAL } else { PORTRAIT }
}

fn raw(rv: &Reveal, now: Instant) -> Frame {
    let t = now.saturating_duration_since(rv.started).as_millis() as u64;
    let rows = |v: Vec<String>, ink: Ink| v.into_iter().map(|r| (r, ink)).collect::<Vec<_>>();
    if let Some(e) = &rv.error {
        return Frame { rows: vec![(egg(0, 0).join("\n"), Ink::Plain), (String::new(), Ink::Plain), (format!("the egg did not hatch: {e}"), Ink::Bold)], black: false, done: true }.split();
    }
    let (Some(o), Some(w)) = (rv.outcome.as_ref(), rv.wobble_end()) else {
        // Wobbling until harnessd answers.
        let dx = [0, -1, 0, 1][((t / WOBBLE) % 4) as usize];
        let mut r = rows(egg(dx, 0), Ink::Plain);
        r.push((String::new(), Ink::Plain));
        r.push(("hatching...".into(), Ink::Faint));
        return Frame { rows: r, black: false, done: false };
    };
    let r = roster();
    let d = r.daemon(&o.daemon);
    let rar = rarity(&o.daemon);
    let secret = rar == "secret";
    if rv.done(now) { return card_frame(rv, o, secret) }
    if t < w {
        let dx = [0, -1, 0, 1][((t / WOBBLE) % 4) as usize];
        return Frame { rows: rows(egg(dx, 0), Ink::Plain), black: false, done: false };
    }
    let s = t - w;
    // A secret's stage goes pitch black before the crack.
    let black = secret;
    let shell = if rar == "rare" { Ink::Cyan } else { Ink::Plain };
    if s < 200 { return Frame { rows: rows(egg(0, 1), shell), black, done: false } }
    if s < 400 { return Frame { rows: rows(egg(0, 2), shell), black, done: false } }
    if s < 700 {
        let mut out = Vec::new();
        if rar == "legendary" { out.extend(rows(sparks(), Ink::Yellow)) }
        out.extend(rows(popped(), shell));
        if rar == "legendary" { out.extend(rows(sparks().into_iter().rev().collect(), Ink::Yellow)) }
        return Frame { rows: out, black, done: false };
    }
    let Some(d) = d else { return card_frame(rv, o, secret) };
    let name = o.nickname.clone().unwrap_or(d.id.clone());
    // A plate's idle loop runs from the moment it is in colour (Reduce Motion: frame 0).
    let looped = |since: u64| if rv.motion { plates::frame_at(s.saturating_sub(since), 8) } else { 0 };
    if o.duplicate {
        // Yours, as it was, then what the duplicate did to it.
        let old = art(d, rv.size, &o.old_version, "idle", looped(700), o.shiny, None);
        let mut out = Vec::new();
        let grew_at = 1700;
        let shown = match &o.grew {
            Some((_, v)) if s >= grew_at + 200 => {
                let new = art(d, rv.size, v, "idle", looped(700), o.shiny, None);
                let step = ((s - grew_at - 200) / 160 + 1).min(4) as u8;
                if step >= 4 { new } else { remorph(d, o.shiny, &old, &new, step) }
            }
            _ => old,
        };
        out.extend(shown);
        out.push((String::new(), Ink::Plain));
        out.push((format!("{} x{} · +{} xp", d.id, o.count.max(2), o.xp), Ink::Bold));
        out.push((format!("another {}. +{} xp.", d.id, o.xp), Ink::Plain));
        if o.became_shiny { out.push(("yours is shiny now.".into(), Ink::Plain)) }
        if let Some((bond, v)) = &o.grew { if s >= grew_at { out.push((format!("{name} grew: bond {bond} · {v}"), Ink::Bold)) } }
        return Frame { rows: out, black, done: false };
    }
    let mut out = Vec::new();
    let young = r.rules.versions[0].clone();
    if s < 1900 {
        // The silhouette, faint, for 1200 ms.
        out.extend(rows(hashed(&texts(&art(d, rv.size, &young, "idle", 0, o.shiny, None))), Ink::Faint));
        return Frame { rows: out, black, done: false };
    }
    // In colour: a plate runs its idle loop; line art blinks.
    let lid = (2100..2220).contains(&s).then_some("-");
    out.extend(art(d, rv.size, &young, "idle", looped(1900), o.shiny, lid));
    if s >= 2220 {
        out.push((String::new(), Ink::Plain));
        let banner = render::banner(super::roster::banner(), &d.id);
        let wide = banner.iter().map(String::len).max().unwrap_or(0);
        let shown = ((s - 2220) as usize * wide / 600).min(wide);
        out.extend(banner.into_iter().map(|b| (b.chars().take(shown).collect(), Ink::Bold)));
    }
    if s >= 2820 { out.push((String::new(), Ink::Plain)); out.push((stamp(o), Ink::Bold)) }
    if s >= 3100 { out.push(("fork() returned 0.".into(), Ink::Plain)) }
    if s >= 3400 { out.push((format!("\"{}\"", d.first), Ink::Plain)) }
    Frame { rows: out, black, done: false }
}

/// The morph between two portraits in their ink: a plate's rows keep their width, each version
/// centred over the other, so the art does not slide.
fn remorph(d: &Daemon, shiny: bool, old: &[(String, Ink)], new: &[(String, Ink)], step: u8) -> Vec<(String, Ink)> {
    let (mut old, mut new) = (texts(old), texts(new));
    if !d.plate { return morph(&old, &new, step).into_iter().map(|r| (r, Ink::Colour(d.colour(shiny)))).collect() }
    let w = old.iter().chain(new.iter()).map(String::len).max().unwrap_or(0);
    for rows in [&mut old, &mut new] {
        let pad = " ".repeat(w.saturating_sub(rows.iter().map(String::len).max().unwrap_or(0)) / 2);
        for r in rows.iter_mut() { *r = format!("{pad}{r}") }
    }
    let rows = morph(&old, &new, step).into_iter().map(|r| format!("{r:<w$}")).collect();
    PlateInk::rows(d, shiny, rows).into_iter().map(|(r, ink)| (r, Ink::Plate(ink))).collect()
}

/// `[ LEGENDARY ]`, `[ SHINY RARE ]`.
pub fn stamp(o: &Outcome) -> String { format!("[ {}{} ]", if o.shiny { "SHINY " } else { "" }, rarity(&o.daemon).to_uppercase()) }

/// The end of it: the card (a duplicate's merge held, its new version when it grew).
fn card_frame(rv: &Reveal, o: &Outcome, secret: bool) -> Frame {
    let r = roster();
    let Some(d) = r.daemon(&o.daemon) else { return Frame { rows: vec![(format!("hatched {}", o.daemon), Ink::Bold)], black: false, done: true } };
    let mut out: Vec<(String, Ink)> = Vec::new();
    if o.duplicate {
        let v = o.grew.as_ref().map(|(_, v)| v.clone()).unwrap_or(o.old_version.clone());
        out.extend(art(d, rv.size, &v, "idle", 0, o.shiny, None));
        out.push((String::new(), Ink::Plain));
        out.push((format!("another {}. +{} xp.", d.id, o.xp), Ink::Bold));
        if o.became_shiny { out.push(("yours is shiny now.".into(), Ink::Plain)) }
        match &o.grew {
            Some((bond, v)) => out.push((format!("{} {v}: bond {bond}, {} xp.", d.id, o.total_xp), Ink::Plain)),
            None => out.push((format!("{}: {} xp.", d.id, o.total_xp), Ink::Plain)),
        }
    } else {
        out.push((stamp(o), Ink::Bold));
        out.push(("fork() returned 0.".into(), Ink::Plain));
        out.push((String::new(), Ink::Plain));
        let card = card_lines(r, d, &CardOpts { version: None, shiny: o.shiny, serial: o.serial.map(|s| s.to_string()), nickname: o.nickname.clone(), hatched: o.hatched.clone(), egg: Some(rv.egg_kind.clone()) });
        // The card's portrait rows in the daemon's ink: a plate down its gradient, line art in its colour.
        let rows = card_art(r, d, &r.rules.versions[0]).len();
        let ink = |i: usize| if d.plate { Ink::Plate(PlateInk::of(d, o.shiny, i, rows)) } else { Ink::Colour(d.colour(o.shiny)) };
        for (i, l) in card.into_iter().enumerate() { out.push((l, if (3..3 + rows).contains(&i) { ink(i - 3) } else { Ink::Plain })) }
    }
    out.push((String::new(), Ink::Plain));
    out.push((if rv.consent_next { "any key: next · Esc: later".into() } else { "any key: close".into() }, Ink::Faint));
    Frame { rows: out, black: secret, done: true }
}

impl Frame {
    /// Rows given with newlines inside them, split.
    fn split(self) -> Frame {
        let rows = self.rows.into_iter().flat_map(|(r, ink)| r.split('\n').map(|l| (l.to_string(), ink)).collect::<Vec<_>>()).collect();
        Frame { rows, ..self }
    }
}

/// The next frame is due (the reveal is animating).
pub fn next_in(rv: &Reveal, now: Instant) -> Option<Duration> { (!rv.done(now)).then_some(Duration::from_millis(40)) }

#[cfg(test)]
mod tests {
    use super::*;
    use crate::daemon::card::silhouette;

    fn at(rv: &Reveal, ms: u64) -> Frame { frame(rv, rv.started + Duration::from_millis(ms)) }
    fn text(f: &Frame) -> String { f.rows.iter().map(|(r, _)| r.as_str()).collect::<Vec<_>>().join("\n") }

    fn answered(daemon: &str, duplicate: bool) -> Reveal {
        let mut rv = Reveal::new("e1", "first", true, false, true);
        rv.answered = Some(rv.started + Duration::from_millis(300));
        rv.outcome = Some(Outcome { daemon: daemon.into(), serial: Some(42), duplicate, xp: if duplicate { 150 } else { 0 }, old_version: "0.1".into(), hatched: Some("2026-09-26".into()), total_xp: 210, ..Default::default() });
        rv
    }

    /// A plate's rows as the reveal lays them out: centred in its width.
    fn laid(rows: &[String], size: &str) -> Vec<String> {
        let pad = " ".repeat((width(size) - rows[0].len()) / 2);
        rows.iter().map(|r| format!("{pad}{r}")).collect()
    }

    #[test]
    fn a_reveal_from_the_wobble_to_the_card() {
        let mut rv = Reveal::new("e1", "first", true, false, true);
        // Before the answer: the egg, wobbling.
        let still = text(&at(&rv, 0));
        let left = text(&at(&rv, 130));
        assert!(still.contains(".--.") && still.contains("hatching..."));
        assert_eq!(left.lines().next().unwrap().find('.').unwrap() + 1, still.lines().next().unwrap().find('.').unwrap(), "a wobble moves it a column:\n{still}\n{left}");
        rv = answered("tim", false);
        let w = 960;
        assert!(text(&at(&rv, w + 100)).contains("|  /\\  |"), "the crack");
        assert!(text(&at(&rv, w + 500)).contains("|\\/\\/\\/|"), "the pop");
        // tim's 0.1 plate as a silhouette, faint: every glyph a `#`.
        let young = plates::rows("tim", PORTRAIT, "0.1", "idle", 0);
        let sil = at(&rv, w + 1000);
        let hashed: Vec<String> = young.iter().map(|r| silhouette(r)).collect();
        assert_eq!(sil.rows.iter().map(|(r, _)| r.clone()).collect::<Vec<_>>(), laid(&hashed, PORTRAIT));
        assert!(sil.rows.iter().all(|(_, ink)| *ink == Ink::Faint));
        // Then in colour: the plate, down tim's gradient, its idle loop a frame every 170 ms.
        let tim = roster().daemon("tim").unwrap();
        let lit = at(&rv, w + 2000);
        for (i, row) in laid(&young, PORTRAIT).into_iter().enumerate() { assert_eq!(lit.rows[i], (row, Ink::Plate(PlateInk::of(tim, false, i, young.len())))) }
        let next = laid(&plates::rows("tim", PORTRAIT, "0.1", "idle", 1), PORTRAIT);
        assert_eq!(at(&rv, w + 1900 + 170).rows[..young.len()].iter().map(|(r, _)| r.clone()).collect::<Vec<_>>(), next);
        assert_ne!(next, laid(&young, PORTRAIT), "the loop moves");
        assert!(text(&at(&rv, w + 2900)).contains("[ COMMON ]"));
        assert!(text(&at(&rv, w + 3200)).contains("fork() returned 0."));
        assert!(text(&at(&rv, w + 3500)).contains("\"oh hi. i'm tim."));
        // The card, its portrait plate in tim's ink.
        let card = at(&rv, w + 4300);
        assert!(card.done && text(&card).contains("| #01/09  DROP 1: INIT            COMMON |") && text(&card).contains("tim 0.1  #0042"), "{}", text(&card));
        assert!(text(&card).contains("hatched 2026-09-26, first egg"));
        let inked: Vec<&(String, Ink)> = card.rows.iter().filter(|(_, ink)| matches!(ink, Ink::Plate(_))).collect();
        assert_eq!(inked.len(), young.len());
        for (row, (line, _)) in young.iter().zip(inked) { assert!(line.contains(row.as_str()), "{row:?} in {line:?}") }
    }

    #[test]
    fn a_plate_at_the_reveal_size_when_it_fits() {
        let mut rv = answered("tim", false);
        // Room for all of it (a 120 x 32 terminal's popup): the reveal plate, 56 columns wide.
        assert_eq!(fit(&rv, 116, 30), REVEAL);
        let (w, h) = extent(&rv, REVEAL);
        assert!(w <= 116 && h <= 30 && w == width(REVEAL), "{w} x {h}");
        // Too narrow or too short: the portrait plate.
        assert_eq!(fit(&rv, 50, 30), PORTRAIT);
        assert_eq!(fit(&rv, 116, h - 1), PORTRAIT);
        rv.size = REVEAL;
        let big = plates::rows("tim", REVEAL, "0.1", "idle", 0);
        assert!(big.len() > plates::rows("tim", PORTRAIT, "0.1", "idle", 0).len());
        let lit = at(&rv, 960 + 2000);
        assert_eq!(lit.rows[..big.len()].iter().map(|(r, _)| r.clone()).collect::<Vec<_>>(), laid(&big, REVEAL));
        // No row moves as the rest arrives: the reveal is never taller than its extent.
        for ms in (0..5200).step_by(100) { assert!(at(&rv, ms).rows.len() <= h, "{ms}") }
        // The card keeps its portrait plate; before the answer there is nothing to fit.
        assert!(text(&at(&rv, 960 + 4300)).contains(plates::rows("tim", PORTRAIT, "0.1", "idle", 0)[1].as_str()));
        assert_eq!(fit(&Reveal::new("e1", "first", true, false, true), 116, 30), PORTRAIT);
    }

    #[test]
    fn rarity_tells_and_a_secret_in_the_dark() {
        let w = 960;
        let rare = answered("yak", false);
        assert_eq!(at(&rare, w + 100).rows[0].1, Ink::Cyan);
        let legendary = answered("tux", false);
        assert!(at(&legendary, w + 500).rows.iter().any(|(r, ink)| *ink == Ink::Yellow && r.contains('*')));
        let secret = answered("beastie", false);
        assert!(at(&secret, w + 100).black && at(&secret, w + 5000).black);
        assert!(!at(&secret, 500).black, "black only once it answers");
        // A shiny one wears its gold gradient.
        let mut gold = answered("tux", false);
        gold.outcome.as_mut().unwrap().shiny = true;
        assert!(at(&gold, w + 2000).rows.iter().any(|(_, ink)| matches!(ink, Ink::Plate(p) if p.shiny)));
        assert!(text(&at(&gold, w + 2900)).contains("[ SHINY LEGENDARY ]"));
    }

    #[test]
    fn a_duplicate_merges_and_grows() {
        let w = 960;
        let mut rv = answered("tim", true);
        rv.outcome.as_mut().unwrap().grew = Some((2, "1.0".into()));
        assert!(text(&at(&rv, w + 800)).contains("another tim. +150 xp."));
        assert!(!text(&at(&rv, w + 800)).contains("fork()"), "no new name for a duplicate");
        assert!(text(&at(&rv, w + 1800)).contains("tim grew: bond 2 · 1.0"));
        let held = at(&rv, w + 2700);
        let grown = plates::rows("tim", PORTRAIT, "1.0", "idle", 0);
        assert!(held.done && grown.iter().all(|row| text(&held).contains(row.as_str())), "the new version: {}", text(&held));
        // Three frames between, a quarter more of the differing cells each, every row one width.
        let old = plates::rows("tim", PORTRAIT, "0.1", "idle", 0);
        let m0 = morph(&old, &grown, 0);
        assert_eq!(m0[..old.len()], old.iter().map(|l| l.trim_end().to_string()).collect::<Vec<_>>()[..]);
        assert!(m0[old.len()..].iter().all(String::is_empty));
        assert_eq!(morph(&old, &grown, 4), grown.iter().map(|l| l.trim_end().to_string()).collect::<Vec<_>>());
        assert!(morph(&old, &grown, 2) != morph(&old, &grown, 1));
        let between = at(&rv, w + 1700 + 200 + 170);
        let plate: Vec<&(String, Ink)> = between.rows.iter().filter(|(_, ink)| matches!(ink, Ink::Plate(_))).collect();
        assert_eq!(plate.len(), grown.len());
        assert!(plate.iter().all(|(r, _)| r.len() == plate[0].0.len()), "the morph keeps its width");
    }

    #[test]
    fn reduce_motion_goes_straight_to_the_card() {
        let mut rv = answered("tim", false);
        rv.motion = false;
        assert!(at(&rv, 350).done);
        // Line art (a daemon of a later drop) still blinks, in its colour.
        let mut line = answered("tmux", false);
        line.size = REVEAL;
        assert_eq!(fit(&line, 200, 60), PORTRAIT, "line art has one size");
        assert!(text(&at(&line, 960 + 2000)).contains("|   o   o   |") && text(&at(&line, 960 + 2150)).contains("|   -   -   |"));
        assert!(matches!(at(&line, 960 + 2000).rows[0].1, Ink::Colour(_)));
    }
}
