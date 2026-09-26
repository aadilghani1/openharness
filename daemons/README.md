# Daemons

Pair-programming buddies that hatch from your work and live in your status line. One daemon pairs
with you at a time. It watches every harness on every machine, tells you what needs you, and runs
the orchestration you ask for. Every daemon can do the whole job; they differ in lore, look and
voice. Each is named after a piece of terminal history, the way **tim** is **t**mux **im**proved.

The lookbook ([lookbook.html](lookbook.html)) shows all of it moving: the status line, drop 1, a
working hatch simulation, eggs, growth, moods, memory and learning. This file is the contract the
clients and the server build against.

## Files

| file | what it is |
|---|---|
| `roster.json` | The source of truth: rules, odds, drops, and every daemon's art, lore and lines. |
| `tools/render.mjs` | The reference renderer. Every client port draws exactly what it draws. |
| `tools/generate.mjs` | Checks the roster against the art rules and writes the copies below. `--check` in CI. |
| `frames.json` | Generated. Frames every port must reproduce, byte for byte. |
| `desktop/lib/daemons/roster.g.dart` | Generated. The roster as a Dart raw string. |
| `backend/src/lib/daemonRoster.g.ts` | Generated. Only what decides a draw: ids, rarities, drops, egg rules. |

`hn` (the Rust terminal client) reads `roster.json` with `include_str!` and tests against `frames.json`.

## Words

- **daemon**: the creature. User-facing text calls the background service `harnessd` so the word is free.
- **zoo**: your daemons and eggs. `hn zoo`.
- **hatch**: opening an egg. The reveal says `fork() returned 0.`
- **pair**: the one daemon in your status line.
- **drop**: a set of daemons released together. Drop 1 is `unix`. Drops ship when an idea is ready.

## Art rules

Printable 7-bit ASCII only (0x20–0x7e), so every terminal, font, phone and paste into Slack or GitHub
shows the same thing. Turn off ligatures wherever a daemon is drawn (`->` and `==` merge in Fira Code).

- **Sprite**: one line, at most 8 cells, centred in the status line with one cell of gutter each side.
  Three versions: `0.1`, `1.0`, `2.0`.
- **Portrait**: at most 8 rows by 28 columns. Shown in the daemon's panel, the hatch reveal, the zoo and
  the card. A daemon may draw one portrait per version; a missing version uses the nearest one drawn.
- **Eyes carry the mood.** The body stays still; a mood changes at most two cells of the sprite.
- **Placeholders** (see `render.mjs`): `{e}` an eye; `{<part>}` a moving part with a `rest` glyph and
  `work` frames; `{<moodPart>}` a value per mood (tim's mouth `{m}` and tmux window flag `{g}`, vim's
  mode line `{mode}`).
- **Colour** is a filter over the drawing, never the only signal. Each daemon has one xterm-256 colour.

## Moods

`idle` content · `work` agents working · `need` a harness needs you · `done` a turn finished ·
`fail` a turn failed or a harness is offline · `back` you returned · `nap` asleep · `boop` clicked.

Moods come from work, never from the clock. The face is decided in this order:

1. `boop` for 900 ms after a click.
2. `need` while any harness waits on you. It wins over everything automatic, and it wakes a nap.
3. `nap` while you asked it to nap (15 minutes, or until you interact).
4. A held reaction: `done` 3 s after a turn you started finishes (at most once per 20 s),
   `back` 1.3 s when you return after 15 minutes or more (it waves), `fail` 4.2 s when a turn fails.
5. `work` while any agent works.
6. `fail` while a harness you have open is offline or failed to start.
7. `idle`.

Imported history, reconnects and restored state are baselines, never fresh reactions. Several
finishes at once do not queue.

## Motion and blinks

Every motion is finite and ends at rest. There is no idle animation timer.

- **Working**: the 2.0 sprite cycles its `work` frames (tim's arms turn like a twirling baton).
  Younger versions borrow the baton `|/-\` after the sprite.
- **Blinks answer something**:
  - `ack`, one blink 160 ms after something it watches changes (a harness needs you, a turn finishes, a test fails);
  - `look`, one blink when you look at it (hover, open its panel, return to the window), at most once per 2.5 s;
  - `slow`, a slow blink (cats show trust this way) when you return after a break, when you meet, when it levels up.
  - No blinks while working, napping or booped.
- Reduce Motion and background windows stop all frames; the face still changes.

## Voice

One line at a time, lowercase, in the status line (it becomes tmux's yellow message line for 5.2 s).
Every line carries information; the joke rides on the fact. Silent by default. It speaks for `need`,
`done` (cooldown 20 s), `fail`, `back`, a boop and its first words. It never speaks while you are
typing (it waits until 2 s after the last key) or while a dialog is open. Lines in `roster.json` are
the voice for each mood until the pair brain writes real ones (see Build).

## The zoo (server contract)

The zoo is account state, the same on every client, like the desk but separate from it: a desk
change never re-fetches the zoo and the other way round.

```
GET  /api/zoo        -> { revision, zoo }
POST /api/zoo/ops    -> { ops: [...] } applied in order under `revision`; answers { revision, zoo, hatched }
event zoo_changed    { revision }   (same path as desk_changed: bus -> adapter -> harnessd -> local clients)
```

`harnessd` proxies `/api/zoo` for local clients exactly as it proxies `/api/desk`.

```
zoo = {
  daemons: [{ id, hatchedAt, egg, shiny, nickname?, bond, version }],   // id is a roster id
  eggs:    [{ id, kind, grantedAt }],                                     // kind is a key of rules.eggs
  pair:    daemonId | null,
  habits:  [habitKey],             // first-egg habits done, from rules.firstEgg.habits
  firstEgg: bool,                  // the first egg has been granted
  pity:    number,                 // hatches since the last secret
  easter:  [word],                 // easter words already used
}
```

Ops (every op is idempotent; an op on something missing is dropped, never an error):

| op | effect |
|---|---|
| `zoo.habit { key }` | Records a first-egg habit. When `need` habits are done and `firstEgg` is false, grants a `first` egg. |
| `zoo.hatch { eggId }` | Draws on the server, adds the daemon, removes the egg, pairs it if nothing is paired. Answers `hatched: [{ eggId, daemonId, shiny }]`. |
| `zoo.pair { id }` | Pairs a daemon you own. |
| `zoo.nickname { id, nickname }` | 1–24 printable ASCII characters, or null to clear. |
| `zoo.easter { word }` | A word from `rules.easterWords` grants one `easter` egg, once per word. |
| `zoo.seed { zoo }` | A guest's local zoo on first sign-in. Applied only while the account zoo is empty. |

Limits: 12 eggs, 64 daemons. The server alone grants turn, week, marathon, night and history eggs
(a later step); clients never send a draw result.

**The draw** (`zoo.hatch`, server only, `crypto.randomInt`):

1. Eligible: every daemon in a released drop that you do not own. When you own them all, duplicates
   are allowed again.
2. Weight: `egg.weights[rarity] / (eligible daemons of that rarity)`, plus `pity * pityPerMiss` for
   secrets, times `egg.boost[id]` when the egg has one. A rarity with no eligible daemon gives its
   weight to nothing (it is not redistributed).
3. Shiny: 1 in `shinyOneIn`, independent of who hatched.
4. `pity` resets on a secret and grows by one otherwise.
5. An egg with nothing new to give (an easter egg once every legendary and secret is owned) draws
   from every released daemon, as if you owned them all.

**Details** (as built in `backend/src/lib/zoo.ts`; a guest client follows the same rules):

- A daemon's `egg` is the kind of egg it came from (the card's "first egg"). Egg ids come from the server.
- Duplicates share their roster id; `pair` and `zoo.nickname` address the first one hatched.
- A name the server does not know (a habit key, an easter word, an egg id, a daemon you do not own)
  drops that op. A malformed op, such as a 25-character nickname, refuses the whole request. Nicknames
  are trimmed.
- A full nest does not lose anything: the first egg arrives with the next habit report, and an easter
  word stays unspent.
- `zoo.seed` keeps only what the roster knows, gives each egg a server id, and pairs the first daemon
  if the guest's pair did not survive.

**Guests** (no Harness account) keep a local zoo with the same shape and rules, drawn on the client.
On first sign-in it is sent once with `zoo.seed`.

## First egg: habits

The first egg arrives after 5 of these 8, in any order. Each client reports the ones it sees with
`zoo.habit`.

| key | counts when |
|---|---|
| `turn` | A turn you started finishes in any harness. |
| `split` | Two harnesses are side by side in one tab. |
| `find` | You open something from Cmd-O (or `hn`'s finder). |
| `elsewhere` | You answer a harness from a different device than the one that started it. |
| `machine` | A second computer connects to your account. |
| `store` | A turn finishes in a Store harness. |
| `resume` | A paused harness is resumed. |
| `days` | You use Harness on three different days. |

While it incubates, the status line shows the nest: `\_O_/` `~\_O_/~` `\_.._/` `\_o.o_/` as 0–1,
2–3, 4 and 5 habits are done. An egg never hatches on its own; clicking a ready egg hatches it.

## Hatching

Crack, silhouette, name, card, in about 4 s (Reduce Motion: straight to the card):
the egg wobbles twice, cracks, the top pops; the hatchling's 0.1 sprite appears as `#` in the faint
colour, holds 850 ms, fills with its colour, blinks; its name types in as a small banner; the rarity
stamp and first words appear. A secret's reveal starts pitch black. The card copies as a fenced code
block:

```
.----------------------------------------.
| #01/10  DROP 1: UNIX            COMMON |
|                                        |
|  [oo]    tim 0.1                       |
|  screen -> tmux -> tim                 |
|                                        |
|  "oh hi. i'm tim. tmux, improved.      |
|  what are we building?"                |
|                                        |
|  hatched 2026-09-26, first egg         |
'----------------------------------------'
```

## Build

1. **Ready fixes** from the companion branch as their own PR (a tab closes with its last pane; the
   New Harness launch spinner).
2. **One daemon everywhere**: this folder; the zoo on the server; the desktop replaces its local
   companion with the zoo (status line, nest, hatch, panel); `hn` replaces `~/.harness/tui/tim.json`.
3. **The pair brain**: the paired daemon runs as an always-on harness with a Harness control
   interface (list, read, send, start, pause). First jobs: triage what waits on you, and brief you
   when you come back.
4. **Learning**: notice real signals, propose in one line, teach every agent with SKILL.md, only with
   your yes. See the lookbook's LEARNING section.
5. **The rest of the zoo**: turn/week/marathon/night/history eggs, bond and versions, logbooks, drops.
