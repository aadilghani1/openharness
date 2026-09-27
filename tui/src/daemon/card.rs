//! A port of daemons/tools/card.mjs: a daemon's card and a drop's shelf (the box back), as text for a
//! fenced code block and as SVG for places a code block does not travel. Never a live mood: a card
//! is a portrait, not a presence indicator. Checked against daemons/frames.json (`cards`).

use super::render::{portrait, sprite, Opts};
use super::roster::{Daemon, DropDef, Roster};

const W: usize = 42;
const INNER: usize = W - 4;

fn regulars<'r>(roster: &'r Roster, drop: &str) -> Vec<&'r Daemon> {
    roster.daemons.iter().filter(|x| x.rarity != "secret" && x.drop == drop).collect()
}

/// `#03/09`, or `#S/09` for a secret: secrets sit outside the numbered set.
pub fn card_number(roster: &Roster, d: &Daemon) -> String {
    let set = regulars(roster, &d.drop);
    let of = format!("{:02}", set.len());
    if d.rarity == "secret" { return format!("#S/{of}") }
    let at = set.iter().position(|x| x.id == d.id).map(|i| i as i64).unwrap_or(-1) + 1;
    format!("#{at:02}/{of}")
}

fn wrap(text: &str, width: usize) -> Vec<String> {
    let mut out = Vec::new();
    let mut line = String::new();
    for word in text.split(' ') {
        if format!("{line} {word}").trim().len() > width { out.push(line.trim().to_string()); line = word.to_string() } else { line.push(' '); line.push_str(word) }
    }
    if !line.trim().is_empty() { out.push(line.trim().to_string()) }
    out
}

/// What a card says besides the daemon: its version, whether it is shiny, its serial, nickname,
/// the day it hatched and the egg it came from.
#[derive(Clone, Debug, Default)]
pub struct CardOpts {
    pub version: Option<String>,
    pub shiny: bool,
    pub serial: Option<String>,
    pub nickname: Option<String>,
    pub hatched: Option<String>,
    pub egg: Option<String>,
}

fn pad_cut(s: &str, n: usize) -> String {
    let mut out = format!("{s:<n$}");
    out.truncate(n);
    out
}

fn drop_of(roster: &Roster, d: &Daemon) -> DropDef {
    roster.drops.iter().find(|x| x.id == d.drop).cloned().unwrap_or(DropDef { id: d.drop.clone(), n: 1, name: d.drop.clone(), announce: None, release: None })
}

/// The card as lines of printable ASCII, 42 columns wide.
pub fn card_lines(roster: &Roster, d: &Daemon, o: &CardOpts) -> Vec<String> {
    let version = o.version.clone().unwrap_or_else(|| roster.rules.versions[0].clone());
    let drop = drop_of(roster, d);
    let l = |s: &str| format!("| {} |", pad_cut(s, INNER));
    let head = format!("{}  DROP {}: {}", card_number(roster, d), drop.n, drop.name.to_uppercase());
    let rarity = format!("{}{}", if o.shiny { "SHINY " } else { "" }, d.rarity.to_uppercase());
    let serial = o.serial.as_ref().map(|s| format!("  #{s:0>4}")).unwrap_or_default();
    let name = format!("{}{} {version}{serial}", o.nickname.as_ref().map(|n| format!("{n} the ")).unwrap_or_default(), d.id);
    let art = portrait(roster, d, &version, "idle", Opts::still());
    let width = art.iter().map(String::len).max().unwrap_or(0);
    let pad = INNER.saturating_sub(width) / 2;
    let mut out = vec![format!(".{}.", "-".repeat(W - 2))];
    out.push(l(&format!("{head}{}{rarity}", " ".repeat(INNER.saturating_sub(head.len() + rarity.len()).max(1)))));
    out.push(l(""));
    for line in &art { out.push(l(&format!("{}{line}", " ".repeat(pad)))) }
    out.push(l(""));
    out.push(l(&format!("  {name}")));
    out.push(l(&format!("  {}", d.lineage())));
    out.push(l(""));
    for line in wrap(&format!("\"{}\"", d.first), INNER - 2) { out.push(l(&format!("  {line}"))) }
    if o.hatched.is_some() || o.egg.is_some() {
        out.push(l(""));
        let text = format!("  hatched {}{}", o.hatched.clone().unwrap_or_default(), o.egg.as_ref().map(|e| format!(", {e} egg")).unwrap_or_default());
        // `.replace(/\s+,/, ',')`: a missing date leaves `hatched , first egg`.
        let text = match text.find(',') { Some(i) if text[..i].ends_with(' ') => format!("{}{}", text[..i].trim_end(), &text[i..]), _ => text };
        out.push(l(&text));
    }
    out.push(format!("'{}'", "-".repeat(W - 2)));
    out
}

/// Days since 1970-01-01 of a `YYYY-MM-DD` (UTC midnight).
pub fn day_number(day: &str) -> Option<i64> {
    let mut it = day.split('-');
    let (y, m, d): (i64, i64, i64) = (it.next()?.parse().ok()?, it.next()?.parse().ok()?, it.next()?.parse().ok()?);
    let y = if m <= 2 { y - 1 } else { y };
    let era = if y >= 0 { y } else { y - 399 } / 400;
    let yoe = y - era * 400;
    let mp = (m + 9) % 12;
    let doy = (153 * mp + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    Some(era * 146097 + doe - 719468)
}

/// A drop's state `now_ms` (ms since the epoch): `released`, `announced` (silhouettes) or `hidden`.
pub fn drop_state(drop: Option<&DropDef>, now_ms: i64) -> &'static str {
    let at = |day: &str| day_number(day).map(|n| n * 86_400_000);
    let Some(drop) = drop else { return "released" };
    match drop.release.as_deref().and_then(at) {
        None => "released",
        Some(r) if r <= now_ms => "released",
        _ => if drop.announce.as_deref().and_then(at).map(|a| a <= now_ms).unwrap_or(false) { "announced" } else { "hidden" },
    }
}

/// The hatchling before it has colour: every drawn cell becomes `#`.
pub fn silhouette(s: &str) -> String { s.chars().map(|c| if c == ' ' { ' ' } else { '#' }).collect() }

/// A daemon on the shelf: owned, shiny, and how many duplicates were merged into it.
#[derive(Clone, Debug, Default)]
pub struct Shelved { pub id: String, pub shiny: bool, pub dupes: u32 }

/// A shelf: the drop's sprites in order, `[ ? ]` for missing regulars, `[ ! ]` for a missing secret,
/// `x2` beside a daemon with a duplicate merged into it.
pub fn shelf_lines(roster: &Roster, owned: &[Shelved], drop: Option<&str>, now_ms: i64) -> Vec<String> {
    let drop = drop.unwrap_or(&roster.drops[0].id).to_string();
    let have = |id: &str| owned.iter().find(|o| o.id == id);
    let set: Vec<&Daemon> = roster.daemons.iter().filter(|d| d.drop == drop).collect();
    let drop1 = roster.drops.iter().find(|x| x.id == drop);
    let state = drop_state(drop1, now_ms);
    if state == "hidden" { return Vec::new() }
    let last = roster.rules.versions.len() - 1;
    let cells: Vec<(String, String)> = set.iter().map(|d| {
        let number = if d.rarity == "secret" { "secret".to_string() } else { card_number(roster, d).chars().take(3).collect() };
        if state == "announced" {
            return (if d.rarity == "secret" { "[ ! ]".into() } else { silhouette(&sprite(roster, d, 0, "idle", Opts::still())) }, number);
        }
        match have(&d.id) {
            None => (if d.rarity == "secret" { "[ ! ]".into() } else { "[ ? ]".into() }, number),
            Some(mine) => (sprite(roster, d, last, "idle", Opts::still()), if mine.dupes > 0 { format!("{} x{}", d.id, mine.dupes + 1) } else { d.id.clone() }),
        }
    }).collect();
    let mut rows = Vec::new();
    for chunk in cells.chunks(5) {
        rows.push(chunk.iter().map(|c| format!("{:<10}", c.0)).collect::<String>().trim_end().to_string());
        rows.push(chunk.iter().map(|c| format!("{:<10}", c.1)).collect::<String>().trim_end().to_string());
        rows.push(String::new());
    }
    let count = set.iter().filter(|d| have(&d.id).is_some() && d.rarity != "secret").count();
    let of = set.iter().filter(|d| d.rarity != "secret").count();
    let secret = set.iter().any(|d| d.rarity == "secret" && have(&d.id).is_some());
    let head = format!("zoo: drop {} {}  {}", drop1.map(|d| d.n).unwrap_or(1), drop1.map(|d| d.name.clone()).unwrap_or(drop.clone()),
        if state == "announced" { format!("out {}", drop1.and_then(|d| d.release.clone()).unwrap_or_default()) } else { format!("{count}/{of}{}", if secret { "  +secret" } else { "" }) });
    let mut out = vec![head, String::new()];
    out.extend(rows);
    out.pop();
    out
}

fn esc(s: &str) -> String { s.replace('&', "&amp;").replace('<', "&lt;").replace('>', "&gt;") }

/// Lines of text as an SVG terminal (card.mjs svgFor), monospace system fonts only.
pub fn svg_for(lines: &[String], colors: &std::collections::HashMap<usize, String>, title: &str) -> String {
    let (cw, lh, pad_x, pad_y) = (8.4f64, 17usize, 18usize, 22usize);
    let cols = lines.iter().map(String::len).max().unwrap_or(0);
    let w = (cols as f64 * cw + (pad_x * 2) as f64).ceil() as i64;
    let h = ((lines.len() * lh + pad_y * 2) as f64 - 4.0).ceil() as i64;
    let text = lines.iter().enumerate().map(|(i, l)| {
        let fill = colors.get(&i).map(String::as_str).unwrap_or("#d0d0d0");
        format!("<text x=\"{pad_x}\" y=\"{}\" fill=\"{fill}\" xml:space=\"preserve\">{}</text>", pad_y + i * lh + 12, esc(l))
    }).collect::<Vec<_>>().join("\n  ");
    format!("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"{w}\" height=\"{h}\" viewBox=\"0 0 {w} {h}\" role=\"img\" aria-label=\"{}\">\n  <rect x=\"0.5\" y=\"0.5\" width=\"{}\" height=\"{}\" rx=\"6\" fill=\"#121212\" stroke=\"#3a3a3a\"/>\n  <g font-family=\"ui-monospace, SFMono-Regular, Menlo, Consolas, 'Liberation Mono', monospace\" font-size=\"14\" font-variant-ligatures=\"none\">\n  {text}\n  </g>\n</svg>\n",
        esc(title), w - 1, h - 1)
}

pub fn card_svg(roster: &Roster, d: &Daemon, o: &CardOpts) -> String {
    let lines = card_lines(roster, d, o);
    let version = o.version.clone().unwrap_or_else(|| roster.rules.versions[0].clone());
    let rows = portrait(roster, d, &version, "idle", Opts::still()).len();
    let color = if o.shiny { d.shiny.as_ref().map(|s| s.hex.clone()).unwrap_or(d.color.hex.clone()) } else { d.color.hex.clone() };
    let mut colors = std::collections::HashMap::new();
    for i in 3..3 + rows { colors.insert(i, color.clone()); }
    colors.insert(1, match d.rarity.as_str() { "rare" => "#5fafaf", "legendary" => "#d7af5f", "secret" => "#af87af", _ => "#d0d0d0" }.to_string());
    svg_for(&lines, &colors, &format!("{}, a {} daemon", d.id, d.rarity))
}

#[cfg(test)]
mod tests {
    use super::super::render::tests::frames;
    use super::super::roster::roster;
    use super::*;

    #[test]
    fn every_card_in_frames_json() {
        let r = roster();
        let mut n = 0;
        for c in frames()["cards"].as_array().unwrap() {
            let d = r.daemon(c["id"].as_str().unwrap()).unwrap();
            let o = CardOpts {
                version: c["version"].as_str().map(str::to_string),
                shiny: c["shiny"].as_bool().unwrap_or(false),
                serial: c["serial"].as_u64().map(|s| s.to_string()),
                nickname: c["nickname"].as_str().map(str::to_string),
                hatched: c["hatched"].as_str().map(str::to_string),
                egg: c["egg"].as_str().map(str::to_string),
            };
            let want: Vec<String> = c["out"].as_array().unwrap().iter().map(|v| v.as_str().unwrap().to_string()).collect();
            assert_eq!(card_lines(r, d, &o), want, "card {} {}", c["id"], c["version"]);
            n += 1;
        }
        assert_eq!(n, 60);
    }

    #[test]
    fn a_shelf_as_card_mjs_draws_it() {
        // node daemons/tools/card.mjs --shelf 'tim*x2,vim,grue'
        let r = roster();
        let owned = [Shelved { id: "tim".into(), shiny: true, dupes: 1 }, Shelved { id: "vim".into(), ..Default::default() }, Shelved { id: "grue".into(), ..Default::default() }];
        let now = day_number("2026-09-27").unwrap() * 86_400_000;
        let got = shelf_lines(r, &owned, None, now);
        assert_eq!(got[0], "zoo: drop 1 unix  2/9  +secret");
        assert!(got[2].starts_with("\\[o|o]/   [ ? ]     [ ? ]     [ ? ]     < o_o >_"), "{:?}", got[2]);
        assert!(got[3].starts_with("tim x2    #02       #03       #04       vim"), "{:?}", got[3]);
        // Before release the regulars are silhouettes and the date shows.
        let early = day_number("2026-09-20").unwrap() * 86_400_000;
        let before = shelf_lines(r, &owned, None, early);
        assert_eq!(before[0], "zoo: drop 1 unix  out 2026-09-26");
        assert!(before[2].starts_with("## ##     ####"), "{:?}", before[2]);
        assert!(shelf_lines(r, &owned, None, day_number("2026-09-01").unwrap() * 86_400_000).is_empty());
    }

    #[test]
    fn dates_and_wrapping() {
        assert_eq!(day_number("1970-01-01"), Some(0));
        assert_eq!(day_number("2026-09-26"), Some(20722));
        assert_eq!(wrap("\"oh hi. i'm tim.\"", 10), vec!["\"oh hi.", "i'm tim.\""]);
    }
}
