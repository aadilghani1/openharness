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
| `mobile/lib/daemons/roster.g.dart` | Generated. The same raw string for the phone, which depends on no other package here. |
| `backend/src/lib/daemonRoster.g.ts` | Generated. Only what decides a draw, a grant or a level: ids, rarities, drops, egg, earn and bond rules. |
| `cli/src/pair/roster.g.ts` | Generated. Ids, line templates, lore, first words and family: the pair brain's voice and the pair harness's persona ([BRAIN.md](BRAIN.md)). |

`hn` (the Rust terminal client) reads `roster.json` with `include_str!` and tests against `frames.json`.

## Words

- **daemon**: the creature. User-facing text calls the background service `harnessd` so the word is free.
- **zoo**: your daemons and eggs. `hn zoo`.
- **hatch**: opening an egg. The reveal says `fork() returned 0.`
- **pair**: the one daemon in your status line.
- **drop**: a set of daemons released together. Drop 1 is `unix`. Drops ship when an idea is ready.

## Art rules

Printable 7-bit ASCII only (0x20–0x7e), so every terminal, font, phone and paste into Slack or GitHub
shows the same thing. Turn off ligatures wherever a daemon is drawn, and keep the art safe where that
is impossible (a terminal's own font):

- **No ligature pairs.** Many people keep ligatures on, so no frame may contain a pair that programming
  fonts (Fira Code, JetBrains Mono, Cascadia) draw as one glyph: `rules.ligatureUnsafe` lists them
  (`==` `??` `!=` `::` `~~` `->` `=>` `<=` `>=` `<>` `||` `&&` `++` `//` `^=` `~=` `:=`), and
  `generate.mjs` renders every sprite, portrait, nest and egg in every mood, frame and blink and fails on
  any of them. So two eyes never touch (tim's `[o o]`, not `[oo]`, or working would draw `[==]` as one
  glyph), and an eye never touches a face character that pairs with a mood's eye (`=` `?` `-` beside `>`,
  `<`, `!`, `^`, `~` or `:`). Put a nose, a mouth, a pane `|` or a space between.
- **Sprite**: one line, at most 8 cells, centred in the status line with one cell of gutter each side.
  Three versions: `0.1`, `1.0`, `2.0`. Every 0.1 sprite has its own silhouette characters, so ten
  hatchlings never read alike at a glance.
- **Portrait**: at most 8 rows by 28 columns. Shown in the daemon's panel, the hatch reveal, the zoo and
  the card. Every daemon in drop 1 draws one portrait per version, growing from the same face (NetHack's
  kitten, housecat, large cat): fewer parts when young, a lore-true feature each release. A missing
  version uses the nearest one drawn.
- **Eyes carry the mood.** The body stays still; a mood changes at most two cells of the sprite. A
  portrait may add one or two lore-true mood parts, never more.
- **Placeholders** (see `render.mjs`): `{e}` an eye; `{<part>}` a moving part with a `rest` glyph and
  `work` frames; `{<moodPart>}` a value per mood (tim's mouth `{m}` and tmux window flag `{g}`, vim's
  mode line `{mode}`, fish's mouth bubble `{b}`, ping's sonar `{s}`, biff's mouth `{m}` with its tongue
  out when happy, fzf's match count `{n}`, and the grue's teeth `{t}`, seen only when something was eaten).
- **Colour** is a filter over the drawing, never the only signal. Each daemon has one xterm-256 colour,
  used only on the terminal background (panel, reveal, zoo, card), with a darker variant on light
  themes. In the status line the daemon takes the status line's own text colour: daemon colours fail
  contrast on tmux's green bar and on the yellow message line.

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
6. `fail` while a harness you have open failed to start or its last turn failed. A machine that is
   asleep or unreachable is not a failure: the panel says so calmly and the face stays as it was.
7. `idle`.

Imported history, reconnects and restored state are baselines, never fresh reactions. Several
finishes at once do not queue.

## Motion and blinks

Every motion is finite and ends at rest. There is no idle animation timer.

- **Working**: the 2.0 sprite steps through its `work` frames, one step per real agent event (a tool
  starting, output arriving), at most two steps a second (tim's arms turn like a twirling baton), and
  the portrait's parts move the same way (tim's arms wave, bat's wings flap, zsh's claws snap, biff's
  tail wags). A baton that stops turning means an agent that stopped. Younger versions borrow the
  baton `|/-\` after the sprite; the face never shifts, because the slot centres on the version's base
  sprite. A Motion setting turns all of this off.
- **Blinks answer something**:
  - `ack`, one blink 160 ms after something it watches changes (a harness needs you, a turn finishes, a test fails);
  - `look`, one blink when you look at it (hover, open its panel, return to the window), at most once per 2.5 s;
  - `slow`, a slow blink (cats show trust this way), about a second long (half-lid, shut, half-lid), when you
    return after a break, when you meet, when it levels up.
  - No blinks while working, napping or booped.
- Reduce Motion and background windows stop all frames; the face still changes.

## Voice

One line at a time, in the status line. Every line carries information; the joke rides on the fact.
Silent by default.

- **Only what needs you takes over the status line** (it becomes tmux's yellow message line for
  5.2 s): a harness waiting on you, and a failure. Finished turns become a small `+3` beside the
  daemon, cleared when you look.
- At most one line nobody asked for every two minutes. Nothing about the pane you are looking at.
- It speaks after Enter, a pane switch, or 8 s without a key, never mid-thought, and never while a
  dialog is open. A Quiet setting keeps it silent until you turn it off; a nap lasts 15 minutes.
- Lines are templates in `roster.json` with slots: `{who}` the harness, `{q}` the question, `{recap}`
  the turn's recap, `{n}` the count that matters, `{summary}` the brief's facts. A client fills them
  from what it knows; a line whose slot cannot be filled is dropped, never shown with made-up facts.
  `examples` holds each line filled with sample values for previews.
- Answer keys come first in the line, and work only while the line is showing.

## The zoo (server contract)

The zoo is account state, the same on every client, like the desk but separate from it: a desk
change never re-fetches the zoo and the other way round.

```
GET  /api/zoo        -> { revision, zoo }
POST /api/zoo/ops    -> { ops: [...] } applied in order under `revision`;
                        answers { revision, zoo, hatched, grants, levelUps }
event zoo_changed    { revision }   (same paths as desk_changed: bus -> adapter -> harnessd -> local clients,
                                     and bus -> web socket -> phone and browser)
```

`grants: [{ kind, eggId }]` is every egg that arrived in the nest during the request (first, easter,
earned, or held until there was room); `levelUps: [{ id, level, version }]` is every daemon whose bond
reached a new level. Only the client that sent the request sees them; every other client learns the
same thing by re-reading the zoo after `zoo_changed` (a new egg id, a higher `bond`).

`harnessd` proxies `/api/zoo` for local clients exactly as it proxies `/api/desk`.

```
zoo = {
  daemons: [{ id, hatchedAt, egg, shiny, nickname?, bond, xp, version }],   // id is a roster id
  eggs:    [{ id, kind, grantedAt, date? }],     // kind is a key of rules.eggs; date on a history egg
  pair:    daemonId | null,
  autonomy: 'watch' | 'suggest' | 'act-on-key' | 'act-within-rules',   // the pair's dial; default suggest
  habits:  [habitKey],             // first-egg habits done, from rules.firstEgg.habits
  firstEgg: bool,                  // the first egg has been granted
  pity:    number,                 // hatches since the last secret
  easter:  [word],                 // easter words already used
  progress: {                      // what counts toward eggs earned from work (server-written)
    turns:    number,              // counted turns, all time
    days:     { 'YYYY-MM-DD': n }, // counted turns per local day, the last 14 days
    weeks:    ['YYYY-Www'],        // ISO weeks whose week egg was earned (last 8)
    nights:   ['YYYY-MM-DD'],      // nights counted since the last night egg
    machines: [machineId],         // the first 2 of the account's machines that reported turns
    marathon: ['turns' | 'machines'],  // marathon eggs earned
    history:  ['YYYY-MM-DD'],      // days whose history egg was earned (last 16)
    held:     [{ kind, date? }],   // eggs earned while the nest was full, oldest first (up to 64)
    batches:  [batchId],           // the last 64 zoo.turn batches applied
  },
}
```

Ops (every op is idempotent; an op on something missing is dropped, never an error):

| op | effect |
|---|---|
| `zoo.habit { key }` | Records a first-egg habit. When `need` habits are done and `firstEgg` is false, grants a `first` egg. |
| `zoo.hatch { eggId }` | Draws on the server, adds the daemon, removes the egg, pairs it if nothing is paired. Answers `hatched: [{ eggId, daemonId, shiny }]`. |
| `zoo.pair { id }` | Pairs a daemon you own. |
| `zoo.nickname { id, nickname }` | 1–24 printable ASCII characters, or null to clear. |
| `zoo.autonomy { level }` | How much the paired daemon may do on its own ([BRAIN.md](BRAIN.md), "Autonomy dial"). A level the server does not know is dropped. |
| `zoo.easter { word }` | A word from `rules.easterWords` grants one `easter` egg, once per word. |
| `zoo.seed { zoo }` | A guest's local zoo on first sign-in. Applied only while the account zoo is empty. |
| `zoo.turn { batchId, n, day, hour, machineId }` | Turns finished on one machine in one local hour (see "Earning eggs and growing"). harnessd sends it. |

Limits: 12 eggs, 64 daemons. The server alone grants turn, week, marathon, night and history eggs
from the turns reported to it; clients never send a draw result or an egg.

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
  if the guest's pair did not survive. It takes the guest's `progress` too, except its machine and
  batch ids, unless this account has already reported turns (a signed-in harnessd got there first):
  then the account's progress stays. A guest with only progress still seeds. `zoo.seed` is refused once
  the account holds any daemon, egg or habit, so a client seeds right at sign-in.
- Held eggs land after any op that leaves room, a hatch included, oldest first, and are answered in
  `grants` like any other.

**Guests** (no Harness account) keep a local zoo with the same shape and rules, drawn on the client.
On first sign-in it is sent once with `zoo.seed`. A guest's turns are counted by its client, not by
harnessd (which reports only while signed in).

## Earning eggs and growing

Work earns eggs; the server decides. `harnessd` reports turns, the server counts them under
`rules.earn`, grants eggs, and grows the paired daemon under `rules.bond` (`backend/src/lib/zoo.ts`).

**What counts as a turn** (`cli/src/lib/zooTurns.ts`). A turn counts when `turn_ended` arrives for a
turn whose `turn_started` harnessd saw live: the engine normalizers' prompt record, which already
leaves out tool results, injected context, compaction summaries and interrupts. Never counted: a
replayed transcript or a turn picked up at attach, a sub-agent's turn (an Orchestrator specialist, or
its Director while specialists are out), a terminal, the pair harness (`dsh` `autonomous/pair`), a turn
killed by an interrupt. There is no per-prompt signal that a person typed it (a delivered message has a
`deliveryId`, a prompt typed straight into a pane has nothing), so a prompt typed by a script or a
`/loop` counts too; the daily cap bounds it.

**Reporting.** Counted turns gather for 60 s, then go out as `zoo.turn` ops, one per local day and hour,
through the same signed-in backend path harnessd uses for `/api/zoo`. `day` and `hour` are the machine's
local time when the turn finished; `machineId` is the machine's id. Each op has a fresh `batchId`; a send
that failed is retried a minute later with the same ids, beside newer ops (at most 64 wait). A 400,
401 or 403 drops the report; a day the server would no longer take is let go. Shutdown sends the last
minute, waiting at most 2 s.

**`zoo.turn { batchId, n, day, hour, machineId }`**: `batchId` and `machineId` are 1–64 id-safe
characters, `n` is 1–50, `day` a real `YYYY-MM-DD` in 2000–2999, `hour` 0–23. Anything else refuses the
request. Then, in order:

1. A batch id among the last 64 applied is dropped (a retry of a send that landed).
2. A `day` that cannot be today anywhere on Earth (UTC−12 to UTC+14) is dropped, allowing one day late:
   from two days before the server's UTC date to one day after.
3. **Machine**: the first 2 of the account's machines to report are remembered; the second earns a
   **marathon** egg, once. An id that is not one of the account's machines is not remembered, but its
   turns count.
4. **Daily cap**: at most `earn.turn.dailyCap` (20) turns count per local day, whatever machine reports
   them. Only counted turns do anything below.
5. **turn** egg every `earn.turn.every` (40) counted turns. **marathon** egg once at
   `earn.marathon.turns` (500).
6. **week** egg once per ISO week (Monday start; 2027-01-01 is in 2026-W53) once `earn.week.days` (3)
   distinct local days of that week have a counted turn.
7. **night** egg when `earn.night.nights` (3) distinct local days have had a counted turn in hours
   `fromHour`–`toHour` (00:00–04:59); the count then starts again from none. Nights need not be in a row.
8. **history** egg on the first counted turn of a day whose `MM-DD` is in `rules.historyDates`, once per
   date per year. The egg carries `date: 'YYYY-MM-DD'`. `historyDates` maps `MM-DD` to the daemon that
   day belongs to, or null: `04-01` teapot (HTTP 418), `09-09` moth (the first actual bug, 1947),
   `10-31` zombie (processes). None of them exists yet. Hatched, a history egg gives its date's daemon
   when a released drop holds it and you do not own it; otherwise (today: always) it draws from the
   usual pool with `eggs.history` weights.
9. **Bond**: the paired daemon (the first hatched with the paired id) gains `bond.xpPerTurn` (1) xp per
   counted turn, plus `bond.xpPerDay` (5) for the first counted turn of a local day. `bond` is the level
   its xp reached on `bond.levels` [0, 50, 150, 300, 600] (levels 0–4); `version` follows
   `bondForVersion`: 0.1, 1.0 at level 2, 2.0 at level 4. Nothing is earned without a pair, and xp never
   goes down. At the cap a full day is 25 xp, so 2.0 takes about 24 full days.
10. A batch that changed nothing (its day already at the cap) is not remembered, and writes nothing.

**A full nest** (12 eggs): an earned egg is held in `progress.held`, oldest first, up to 64, and lands
when there is room (after the op that makes it). Earned past 64 held, an egg is lost.

**Stored daemons** from before xp read `xp` as the least xp their stored `bond` needs; `bond` and
`version` are always read back from `xp`, so they never disagree.

Not built: the lookbook's "first merged PR" marathon, and bond from suggestions you take or talking to
the daemon (later, with the pair brain). What the client shows for a grant or a level-up (a new egg in
the nest, a slow blink, the release's changelog) is the client's.

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
| #01/09  DROP 1: UNIX            COMMON |
|                                        |
|  [o o]   tim 0.1                       |
|  screen -> tmux -> tim                 |
|                                        |
|  "oh hi. i'm tim. tmux, improved.      |
|  what are we building?"                |
|                                        |
|  hatched 2026-09-26, first egg         |
'----------------------------------------'
```

## Cards and shelves

`daemons/tools/card.mjs` draws what people share. A card is the daemon's portrait at its version, its
number, rarity, name, lineage and first words, 42 columns of printable ASCII, copied as a fenced code
block. The same lines render as SVG for places a code block does not travel (X, previews, a GitHub
profile README), in monospace system fonts. A shelf is the zoo as a box back: owned sprites in their
colours, `[ ? ]` for a numbered slot still empty, `[ ! ]` for a secret. Cards and shelves never show a
live mood, so they never reveal whether you are working.

Secrets sit outside the numbered set: drop 1 is `#01/09` to `#09/09`, and grue is `#S/09`.

```
node daemons/tools/card.mjs tim --version 2.0 --serial 42          # a card as text
node daemons/tools/card.mjs tim --version 2.0 --svg > tim.svg      # the same card as SVG
node daemons/tools/card.mjs --shelf tim,vim,grue --svg > zoo.svg   # a shelf
node --test daemons/tools/card.test.mjs
```

## Build

1. **Ready fixes** from the companion branch as their own PR (a tab closes with its last pane; the
   New Harness launch spinner).
2. **One daemon everywhere**: this folder; the zoo on the server; the desktop replaces its local
   companion with the zoo (status line, nest, hatch, panel); `hn` replaces `~/.harness/tui/tim.json`.
3. **The pair brain** ([BRAIN.md](BRAIN.md)): always sensing on every machine, thinking on the one
   you are at, plus a persistent pair harness that pauses when idle, over a Harness control interface
   (list, read, answer, send, start, pause). First jobs: triage what waits on you, and brief you when
   you come back.
4. **Learning**: notice real signals, propose in one line, teach every agent with SKILL.md, only with
   your yes. See the lookbook's LEARNING section.
5. **The rest of the zoo**: turn/week/marathon/night/history eggs, bond and versions (the server and
   harnessd: see "Earning eggs and growing"; the clients' side is still to do), logbooks, drops.
