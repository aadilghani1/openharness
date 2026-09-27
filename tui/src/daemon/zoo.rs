//! The zoo (daemons/README.md, "The zoo"): the account's daemons and eggs, read with `GET /api/zoo`
//! and changed with `POST /api/zoo/ops` through this computer's harnessd, as the desk is — and
//! re-read on `zoo_changed`, never on a desk change. Signed out there is no account zoo: hn shows
//! the nest from the habits it saw here and says "sign in to hatch" (no guest draws in hn).
//!
//! What hn keeps on this computer is ~/.harness/tui/daemon.json: Quiet, the habits it saw (so the
//! nest grows signed out, and they are reported once there is an account), and the days it ran.
//! It replaces tim.json, of which only `off` is kept (as Quiet).

use std::path::PathBuf;

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use super::roster::{roster, Daemon};

#[derive(Deserialize, Serialize, Clone, Debug, Default, PartialEq)]
#[serde(rename_all = "camelCase", default)]
pub struct Owned {
    pub id: String,
    pub hatched_at: Value,
    pub egg: Option<String>,
    pub shiny: bool,
    pub nickname: Option<String>,
    pub bond: u32,
    pub xp: u64,
    pub version: String,
    pub dupes: u32,
    pub serial: Option<u64>,
    pub origin: Option<String>,
}

#[derive(Deserialize, Serialize, Clone, Debug, Default, PartialEq)]
#[serde(rename_all = "camelCase", default)]
pub struct Egg { pub id: String, pub kind: String, pub granted_at: Value, pub date: Option<String> }

#[derive(Deserialize, Serialize, Clone, Debug, Default, PartialEq)]
#[serde(default)]
pub struct Consent { pub watching: bool, pub at: Value }

#[derive(Deserialize, Serialize, Clone, Debug, Default, PartialEq)]
#[serde(default)]
pub struct Progress { pub turns: u64, pub days: std::collections::BTreeMap<String, u64> }

#[derive(Deserialize, Serialize, Clone, Debug, Default, PartialEq)]
#[serde(rename_all = "camelCase", default)]
pub struct Zoo {
    pub daemons: Vec<Owned>,
    pub eggs: Vec<Egg>,
    pub pair: Option<String>,
    pub autonomy: Option<String>,
    pub consent: Option<Consent>,
    pub habits: Vec<String>,
    pub first_egg: bool,
    pub setup_egg: bool,
    pub progress: Progress,
}

#[derive(Deserialize, Clone, Debug, Default)]
#[serde(default)]
pub struct ZooDoc { pub revision: i64, pub zoo: Zoo }

impl Zoo {
    /// The paired daemon: its record, and its roster entry.
    pub fn paired(&self) -> Option<(&Owned, &'static Daemon)> {
        let id = self.pair.as_deref()?;
        let mine = self.daemons.iter().find(|d| d.id == id)?;
        Some((mine, roster().daemon(id)?))
    }

    pub fn owned(&self, id: &str) -> Option<&Owned> { self.daemons.iter().find(|d| d.id == id) }
}

impl Owned {
    /// Its version, as the roster names them (a record from before versions reads 0.1).
    pub fn version(&self) -> String { if roster().rules.versions.contains(&self.version) { self.version.clone() } else { roster().rules.versions[0].clone() } }

    /// `2026-09-26`, however the server wrote it (a date, an ISO time, or ms since the epoch).
    pub fn hatched_day(&self) -> Option<String> {
        match &self.hatched_at {
            Value::String(s) if s.len() >= 10 => Some(s[..10].to_string()),
            Value::Number(n) => n.as_i64().map(|ms| civil(ms.div_euclid(86_400_000))),
            _ => None,
        }
    }
}

/// `YYYY-MM-DD` of a day number (days since 1970-01-01).
pub fn civil(days: i64) -> String {
    let z = days + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = yoe + era * 400 + if m <= 2 { 1 } else { 0 };
    format!("{y:04}-{m:02}-{d:02}")
}

/// Today on this computer's clock, as the zoo counts days.
pub fn local_today() -> String {
    let secs = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs() as i64).unwrap_or(0);
    civil((secs + crate::app::utc_offset()).div_euclid(86_400))
}

pub fn now_ms() -> i64 { std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_millis() as i64).unwrap_or(0) }

// ── this computer's settings (daemon.json) ─────────────────────────────────────

#[derive(Deserialize, Serialize, Clone, Debug, Default, PartialEq)]
#[serde(default)]
pub struct Settings {
    /// Silent until turned off (the README's Quiet): no line nobody asked for.
    pub quiet: bool,
    /// Habits seen here (daemons/README.md, "First egg: habits").
    pub habits: Vec<String>,
    /// The local days hn ran (three make the `days` habit), the last few.
    pub days: Vec<String>,
    /// Hatches seen here: from the fourth, any key skips the reveal to the card.
    pub hatches: u32,
}

fn tui_dir() -> Option<PathBuf> {
    std::env::var("HOME").ok().filter(|h| !h.is_empty()).map(|h| PathBuf::from(h).join(".harness").join("tui"))
}

impl Settings {
    pub fn path() -> Option<PathBuf> { tui_dir().map(|d| d.join("daemon.json")) }

    /// daemon.json, or — the first time — what tim.json said: only its `off`, as Quiet. The rest of
    /// tim.json (a species drawn on this computer) is not a daemon, and goes.
    pub fn load() -> Settings {
        let Some(path) = Settings::path() else { return Settings::default() };
        if let Some(s) = std::fs::read_to_string(&path).ok().and_then(|t| serde_json::from_str::<Settings>(&t).ok()) { return s }
        let old = tui_dir().map(|d| d.join("tim.json"));
        let off = old.as_ref().and_then(|p| std::fs::read_to_string(p).ok()).and_then(|t| serde_json::from_str::<Value>(&t).ok())
            .and_then(|v| v.get("off").and_then(Value::as_bool));
        let settings = Settings { quiet: off.unwrap_or(false), ..Default::default() };
        if off.is_some() && settings.save() { if let Some(p) = old { let _ = std::fs::remove_file(p); } }
        settings
    }

    pub fn save(&self) -> bool {
        let Some(path) = Settings::path() else { return false };
        if let Some(dir) = path.parent() { let _ = std::fs::create_dir_all(dir); }
        std::fs::write(&path, serde_json::to_string_pretty(self).unwrap_or_default()).is_ok()
    }

    /// A habit seen here; true when it is new.
    pub fn saw(&mut self, key: &str) -> bool {
        if self.habits.iter().any(|h| h == key) { return false }
        self.habits.push(key.to_string());
        true
    }

    /// Today counted; true when it makes three different days.
    pub fn ran_today(&mut self, today: &str) -> bool {
        if !self.days.iter().any(|d| d == today) { self.days.push(today.to_string()); self.days.sort(); let n = self.days.len(); if n > 8 { self.days.drain(..n - 8); } }
        self.days.len() >= 3
    }
}

/// An op, as the server takes it.
pub fn op(name: &str, fields: Value) -> Value {
    let mut o = json!({ "op": name });
    if let (Value::Object(m), Value::Object(f)) = (&mut o, fields) { m.extend(f) }
    o
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn days_both_ways() {
        for d in ["1970-01-01", "2026-09-26", "2000-02-29", "2027-01-01"] {
            assert_eq!(civil(super::super::card::day_number(d).unwrap()), d);
        }
    }

    #[test]
    fn reads_a_zoo_as_the_server_writes_it() {
        let doc: ZooDoc = serde_json::from_value(json!({ "revision": 3, "zoo": { "daemons": [{ "id": "tim", "hatchedAt": "2026-09-26T10:00:00Z", "egg": "first", "shiny": true, "bond": 2, "xp": 160, "version": "1.0", "serial": 42 }],
            "eggs": [{ "id": "e1", "kind": "turn", "grantedAt": 1 }], "pair": "tim", "consent": null, "habits": ["turn"], "progress": { "turns": 41, "days": { "2026-09-26": 3 } } } })).unwrap();
        let (mine, d) = doc.zoo.paired().unwrap();
        assert_eq!((d.id.as_str(), mine.version().as_str(), mine.hatched_day().as_deref()), ("tim", "1.0", Some("2026-09-26")));
        assert!(doc.zoo.consent.is_none());
        assert_eq!(op("zoo.habit", json!({ "key": "split" })), json!({ "op": "zoo.habit", "key": "split" }));
        let mut s = Settings::default();
        assert!(s.saw("split") && !s.saw("split"));
        assert!(!s.ran_today("2026-09-24") && !s.ran_today("2026-09-25") && s.ran_today("2026-09-26") && s.ran_today("2026-09-26"));
    }
}
