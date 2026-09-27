//! A port of daemons/tools/render.mjs, the reference renderer: sprites, portraits, the status
//! cell, the banner face and the nest. Every function draws exactly what its JS twin draws — the
//! tests below check every frame in daemons/frames.json byte for byte. Keep the two in step.
//!
//! Placeholders in sprites and portraits:
//!   {e}          an eye: the mood's eye, or the lid while blinking (never in noBlinkMoods)
//!   {<part>}     a moving part (d.parts): its `rest` glyph, or a frame of `work` every `ms` while working
//!   {<moodPart>} a mood-driven part (d.moodParts): its value for the mood, else its idle value

use super::roster::{Banner, Daemon, Roster};

/// How a frame is drawn: `t` in milliseconds, the lid while blinking, and whether parts move.
#[derive(Clone, Copy, Debug)]
pub struct Opts<'a> { pub t: u64, pub lid: Option<&'a str>, pub motion: bool }

impl Default for Opts<'_> {
    fn default() -> Self { Opts { t: 0, lid: None, motion: true } }
}

impl<'a> Opts<'a> {
    pub fn still() -> Opts<'a> { Opts { t: 0, lid: None, motion: false } }
    #[cfg(test)]
    pub fn at(t: u64) -> Opts<'a> { Opts { t, ..Default::default() } }
}

pub fn eye_for<'r>(roster: &'r Roster, d: &'r Daemon, mood: &str) -> &'r str {
    if let Some(e) = d.eyes.as_ref().and_then(|e| e.get(mood)) { return e }
    roster.rules.eyes.get(mood).map(String::as_str).unwrap_or("o")
}

fn fill(tpl: &str, roster: &Roster, d: &Daemon, mood: &str, o: Opts) -> String {
    // `lid && …`: an empty lid is no blink, as in JS.
    let blinking = o.lid.map(|l| !l.is_empty()).unwrap_or(false) && !roster.rules.no_blink_moods.iter().any(|m| m == mood);
    let eye: String = if blinking { d.lid.clone().unwrap_or_else(|| o.lid.unwrap_or("").to_string()) } else { eye_for(roster, d, mood).to_string() };
    let moving = o.motion && mood == "work";
    let mut out = String::with_capacity(tpl.len() + 8);
    let bytes = tpl.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'{' {
            let mut j = i + 1;
            while j < bytes.len() && bytes[j].is_ascii_alphabetic() { j += 1 }
            if j > i + 1 && j < bytes.len() && bytes[j] == b'}' {
                let key = &tpl[i + 1..j];
                let value: Option<String> = if key == "e" { Some(eye.clone()) }
                    else if let Some(mp) = d.mood_parts.get(key) { mp.get(mood).or_else(|| mp.get("idle")).cloned() }
                    else if let Some(part) = d.parts.get(key) {
                        Some(if moving { part.work[((o.t / part.ms.max(1)) as usize) % part.work.len()].clone() } else { part.rest.clone() })
                    } else { None };
                match value { Some(v) => out.push_str(&v), None => out.push_str(&tpl[i..=j]) }
                i = j + 1;
                continue;
            }
        }
        // Printable ASCII only (the art rules), so a byte is a character.
        out.push(bytes[i] as char);
        i += 1;
    }
    out
}

/// One line for the status bar. `vi` is 0, 1 or 2 (0.1, 1.0, 2.0).
pub fn sprite(roster: &Roster, d: &Daemon, vi: usize, mood: &str, o: Opts) -> String {
    let rules = &roster.rules;
    let last = rules.versions.len() - 1;
    let moving = o.motion && (mood == "work" || mood == "back");
    let mut tpl: &str = d.sprites.get(&rules.versions[vi]).map(String::as_str).unwrap_or("");
    if moving && vi == last {
        let ms = if mood == "back" { rules.back_frame_ms } else { d.work_ms };
        tpl = &d.work[((o.t / ms.max(1)) as usize) % d.work.len()];
    }
    let mut s = fill(tpl, roster, d, mood, Opts { t: o.t, lid: o.lid, motion: false });
    // Younger versions have no moving part yet; they borrow the twirling baton.
    if moving && vi < last && s.len() <= rules.status_cells - 2 {
        s.push(' ');
        s.push(['|', '/', '-', '\\'][((o.t / 130) % 4) as usize]);
    }
    if mood == "nap" && s.len() < rules.status_cells { s.push('z') }
    s
}

/// The portrait for a version, falling back to the nearest one drawn.
pub fn portrait_for<'r>(roster: &Roster, d: &'r Daemon, version: &str) -> &'r [String] {
    if let Some(p) = d.portraits.get(version) { return p }
    let versions = &roster.rules.versions;
    let drawn: Vec<&String> = versions.iter().filter(|v| d.portraits.contains_key(*v)).collect();
    let at = versions.iter().position(|v| v == version).map(|i| i as i64).unwrap_or(-1);
    let below: Vec<&&String> = drawn.iter().filter(|v| versions.iter().position(|x| x == **v).map(|i| i as i64).unwrap_or(-1) <= at).collect();
    let pick = below.last().map(|v| **v).or(drawn.first().copied());
    pick.and_then(|v| d.portraits.get(v)).map(Vec::as_slice).unwrap_or(&[])
}

pub fn portrait(roster: &Roster, d: &Daemon, version: &str, mood: &str, o: Opts) -> Vec<String> {
    portrait_for(roster, d, version).iter().map(|line| fill(line, roster, d, mood, o)).collect()
}

/// The status cell: statusCells wide plus one cell of gutter each side, the sprite centred on its
/// base width (a borrowed baton or a nap's `z` grows to the right; the face never shifts).
pub fn status_cell(roster: &Roster, sprite: &str, base_width: usize) -> String {
    let cells = roster.rules.status_cells;
    let left = cells.saturating_sub(base_width.min(cells)) / 2;
    let mut s = format!(" {}{sprite}", " ".repeat(left));
    while s.len() < cells + 2 { s.push(' ') }
    s.truncate(cells + 2);
    s
}

/// The base width status_cell centres on: the version's sprite in its idle mood.
pub fn base_width(roster: &Roster, d: &Daemon, vi: usize) -> usize {
    sprite(roster, d, vi, "idle", Opts::still()).len()
}

/// A daemon's name as a banner, in the face from daemons/banner.json: every glyph padded to its own
/// widest row, `gap` columns between letters, blank rows dropped.
pub fn banner(b: &Banner, word: &str) -> Vec<String> {
    let blank: &[String] = b.glyphs.get(" ").map(Vec::as_slice).unwrap_or(&[]);
    let glyphs: Vec<Vec<String>> = word.to_lowercase().chars().map(|ch| {
        let g: &[String] = b.glyphs.get(&ch.to_string()).map(Vec::as_slice).unwrap_or(blank);
        let w = g.iter().map(String::len).max().unwrap_or(0);
        g.iter().map(|r| format!("{r:<w$}")).collect()
    }).collect();
    let gap = " ".repeat(b.gap);
    (0..b.rows)
        .map(|r| glyphs.iter().map(|g| g.get(r).map(String::as_str).unwrap_or("")).collect::<Vec<_>>().join(&gap).trim_end().to_string())
        .filter(|l| !l.trim().is_empty())
        .collect()
}

/// The nest while the first egg incubates: which of rules.nest to show for the habits done.
pub fn nest_stage(roster: &Roster, habits_done: &[String]) -> usize {
    let first = &roster.rules.first_egg;
    let known: Vec<&str> = first.habits.iter().map(|h| h.key.as_str()).collect();
    let mut done: Vec<&str> = Vec::new();
    for h in habits_done { if known.contains(&h.as_str()) && !done.contains(&h.as_str()) { done.push(h) } }
    let required = first.require.iter().all(|k| done.contains(&k.as_str()));
    let counted = if required { done.len().min(first.need) } else { done.len().min(first.need.saturating_sub(1)) };
    let last = roster.rules.nest.len() - 1;
    if counted >= first.need { last } else { counted * last / first.need.max(1) }
}

#[cfg(test)]
pub mod tests {
    use super::super::roster::{banner as the_banner, roster};
    use super::*;
    use serde_json::Value;

    pub fn frames() -> Value { serde_json::from_str(include_str!("../../../daemons/frames.json")).unwrap() }

    fn s(v: &Value) -> String { v.as_str().unwrap().to_string() }
    fn lines(v: &Value) -> Vec<String> { v.as_array().unwrap().iter().map(s).collect() }

    #[test]
    fn every_sprite_in_frames_json() {
        let r = roster();
        let f = frames();
        let mut n = 0;
        for c in f["sprites"].as_array().unwrap() {
            let d = r.daemon(c["id"].as_str().unwrap()).unwrap();
            let vi = r.version_index(c["v"].as_str().unwrap());
            let lid = c["lid"].as_str();
            let got = sprite(r, d, vi, c["mood"].as_str().unwrap(), Opts { t: c["t"].as_u64().unwrap(), lid, motion: true });
            assert_eq!(got, s(&c["out"]), "sprite {c}");
            n += 1;
        }
        assert_eq!(n, 2880);
    }

    #[test]
    fn every_portrait_in_frames_json() {
        let r = roster();
        for c in frames()["portraits"].as_array().unwrap() {
            let d = r.daemon(c["id"].as_str().unwrap()).unwrap();
            let got = portrait(r, d, c["v"].as_str().unwrap(), c["mood"].as_str().unwrap(), Opts::at(c["t"].as_u64().unwrap()));
            assert_eq!(got, lines(&c["out"]), "portrait {} {} {} {}", c["id"], c["v"], c["mood"], c["t"]);
        }
    }

    #[test]
    fn every_status_cell_in_frames_json() {
        let r = roster();
        for c in frames()["cells"].as_array().unwrap() {
            let d = r.daemon(c["id"].as_str().unwrap()).unwrap();
            let vi = r.version_index(c["v"].as_str().unwrap());
            let sp = sprite(r, d, vi, c["mood"].as_str().unwrap(), Opts::at(c["t"].as_u64().unwrap()));
            let got = status_cell(r, &sp, base_width(r, d, vi));
            assert_eq!(got, s(&c["out"]), "cell {c}");
            assert_eq!(got.len(), r.rules.status_cells + 2);
        }
    }

    #[test]
    fn every_nest_and_banner_in_frames_json() {
        let r = roster();
        let f = frames();
        for c in f["nests"].as_array().unwrap() {
            let habits = lines(&c["habits"]);
            let stage = nest_stage(r, &habits);
            assert_eq!(stage as u64, c["stage"].as_u64().unwrap(), "nest {c}");
            assert_eq!(r.rules.nest[stage], s(&c["out"]));
        }
        for c in f["banners"].as_array().unwrap() {
            assert_eq!(banner(the_banner(), c["id"].as_str().unwrap()), lines(&c["out"]), "banner {}", c["id"]);
        }
    }
}
