//! daemons/roster.json and daemons/banner.json, read once (`include_str!`): the art, the rules and
//! the lines every client draws from. Never edited here — `node daemons/tools/generate.mjs` checks
//! the roster, and `render::tests` checks this port against daemons/frames.json.

use std::collections::HashMap;
use std::sync::OnceLock;

use serde::Deserialize;

pub const ROSTER_JSON: &str = include_str!("../../../daemons/roster.json");
pub const BANNER_JSON: &str = include_str!("../../../daemons/banner.json");

#[derive(Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct Roster {
    pub rules: Rules,
    pub drops: Vec<DropDef>,
    pub daemons: Vec<Daemon>,
}

#[derive(Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct Rules {
    pub moods: Vec<String>,
    pub eyes: HashMap<String, String>,
    /// ack, look, slow: each a list of (lid, ms).
    pub blinks: HashMap<String, Vec<(String, u64)>>,
    pub no_blink_moods: Vec<String>,
    pub hold_ms: HashMap<String, u64>,
    pub back_frame_ms: u64,
    pub versions: Vec<String>,
    pub bond: Bond,
    pub status_cells: usize,
    pub duplicate_xp: u64,
    pub first_egg: FirstEgg,
    pub setup_egg: SetupEgg,
    pub eggs: HashMap<String, EggDef>,
    pub earn: Earn,
    pub nest: Vec<String>,
    pub egg: Vec<String>,
}

#[derive(Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct Bond { pub levels: Vec<u64> }

#[derive(Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct FirstEgg {
    pub need: usize,
    #[serde(default)]
    pub require: Vec<String>,
    pub habits: Vec<Habit>,
}

#[derive(Deserialize, Debug)]
pub struct Habit { pub key: String, pub label: String }

#[derive(Deserialize, Debug)]
pub struct SetupEgg { pub need: usize }

#[derive(Deserialize, Debug)]
pub struct EggDef { pub look: String }

#[derive(Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct Earn { pub turn: EarnTurn }

#[derive(Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct EarnTurn { pub every: u64, pub daily_cap: u64 }

#[derive(Deserialize, Debug, Clone)]
pub struct DropDef {
    pub id: String,
    pub n: u32,
    pub name: String,
    #[serde(default)]
    pub announce: Option<String>,
    #[serde(default)]
    pub release: Option<String>,
}

#[derive(Deserialize, Debug, Clone)]
pub struct Colour { pub xterm: u8, pub hex: String }

#[derive(Deserialize, Debug)]
pub struct Part { pub rest: String, pub work: Vec<String>, pub ms: u64 }

#[derive(Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct Daemon {
    pub id: String,
    pub drop: String,
    pub rarity: String,
    pub color: Colour,
    #[serde(default)]
    pub shiny: Option<Colour>,
    /// (name, year): screen -> tmux -> tim.
    pub family: Vec<(String, serde_json::Value)>,
    pub lore: String,
    pub first: String,
    pub lines: HashMap<String, String>,
    pub sprites: HashMap<String, String>,
    pub work: Vec<String>,
    pub work_ms: u64,
    pub portraits: HashMap<String, Vec<String>>,
    #[serde(default)]
    pub parts: HashMap<String, Part>,
    #[serde(default)]
    pub mood_parts: HashMap<String, HashMap<String, String>>,
    #[serde(default)]
    pub eyes: Option<HashMap<String, String>>,
    #[serde(default)]
    pub lid: Option<String>,
    /// The grue: pitch black wherever it is drawn.
    #[serde(default)]
    pub dark_only: bool,
}

#[derive(Deserialize, Debug)]
pub struct Banner {
    pub rows: usize,
    pub gap: usize,
    pub glyphs: HashMap<String, Vec<String>>,
}

pub fn roster() -> &'static Roster {
    static R: OnceLock<Roster> = OnceLock::new();
    R.get_or_init(|| serde_json::from_str(ROSTER_JSON).expect("daemons/roster.json"))
}

pub fn banner() -> &'static Banner {
    static B: OnceLock<Banner> = OnceLock::new();
    B.get_or_init(|| serde_json::from_str(BANNER_JSON).expect("daemons/banner.json"))
}

impl Roster {
    pub fn daemon(&self, id: &str) -> Option<&Daemon> { self.daemons.iter().find(|d| d.id == id) }

    /// The index of a version (`0.1` → 0), else the youngest.
    pub fn version_index(&self, version: &str) -> usize { self.rules.versions.iter().position(|v| v == version).unwrap_or(0) }

    /// What a habit key is called in the checklist.
    pub fn habit_label(&self, key: &str) -> Option<&str> { self.rules.first_egg.habits.iter().find(|h| h.key == key).map(|h| h.label.as_str()) }
}

impl Daemon {
    /// Its colour on the terminal background: the shiny one when it is shiny.
    pub fn colour(&self, shiny: bool) -> u8 { if shiny { self.shiny.as_ref().map(|s| s.xterm).unwrap_or(self.color.xterm) } else { self.color.xterm } }

    /// `screen -> tmux -> tim`.
    pub fn lineage(&self) -> String { self.family.iter().map(|(n, _)| n.as_str()).collect::<Vec<_>>().join(" -> ") }
}
