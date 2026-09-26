# Learning

How a paired daemon learns from what your agents do, and teaches it to all of them. Build step 4 of
[README.md](README.md); the product story is the lookbook's LEARNING section. Paths are in `cli/src`
unless they say otherwise.

Hermes Agent improves itself through files: a background review writes SKILL.md skills and short notes
into `~/.hermes`, and a curator archives skills nobody uses. It works, but it is siloed (Claude Code,
Codex and the rest never see it) and its "be active" prompt saves junk. Harness already sees every turn
of every agent on every machine, so the daemon is the one place a lesson learned in Codex can reach
Claude Code, Cursor, Copilot and Hermes. The loop:

| step | what happens | level |
|---|---|---|
| notice | only real signals: a correction, the same failure twice, the same steps three times | L1 |
| propose | one line in the daemon's voice; nothing is taught without your yes | L1 |
| teach | a SKILL.md every engine loads, or a note in the project's AGENTS.md | L1 |
| revert | every lesson is one commit, and can be taken back | L1 |
| borrow | what each agent learned on its own becomes a candidate for the others | L2 |
| check | usage tracked; unused lessons archived at 30 days, put away at 90 | L2 |

The default is always nothing: no signal, no lesson; a model that is not sure answers "nothing".

## L1 as built

Everything below is in `pair/learn/`. It runs in every harnessd, for that machine's own harnesses, only
while pairing is on.

### Notice (`signals.ts`)

`LessonSignals` reads the same session events the pair sensor does (`emitSessionEvents`): turns,
prompts, tool calls and their results. Replays, sub-agents, terminals and the pair harness are never
read. Three signals:

- **correction**: the person's next prompt after an agent's turn (finished or interrupted) starts by
  correcting it: `no, …`, `nope, …`, `don't …`, `do not …`, `stop, …`, `stop editing …`, `that's wrong`,
  `that's not what I asked`, `wrong …`, `instead …`, `not like that`, `revert …`, `undo that`. Not a bare
  `no` (an answer), not `no, thanks` or `no, that's fine`, not `don't worry`, not `stop the server`, not a
  session's first prompt, not a prompt the daemon itself sent (`daemonSent`, from the owner's `send`).
- **repeat-failure**: the same failing test (vitest, jest, pytest, go, cargo names) — or, when no test
  is named, the same failing command — on two different engines or harnesses, in the same project,
  within 7 days. A failing read or probe (`grep`, `ls`, `diff`, `git status` …) never counts. One run is
  one signal at most; the same failure is not signaled again that week.
- **repeat-steps**: the same sequence of 3–5 command steps, in three separate turns, in one project. A
  step is the program and what it was asked to do (`npm run db:reset`, `cargo test`,
  `python manage.py migrate`); `cd`, reads and probes are not steps; the longest repeated sequence wins
  and the shorter ones inside it are not signaled.

Each signal carries provenance for every turn involved — engine, machine name, agent, session, turn, and
the project as a **hash** (the folder's name is kept for words, never its path) — and its evidence, one
line each, trimmed, redacted and with instructions to a model struck out. Failures and step sequences
are kept in `ADAPTER_DATA_DIR/pair/learn/signals.json` (0600) so a restart does not forget the week.

### Distill (`distill.ts`)

Signals wait in a queue (20 at most) and are distilled three at a time, every ten minutes, when nothing
on the machine is working — or after an hour regardless. One signal becomes at most ONE lesson:

- a **skill**: a kebab-case name, a one-line description, a body of at most 30 lines;
- a **note**: at most 5 lines for the project's AGENTS.md.

**Model off** (the default): templates only, for what needs no judgment — a failing test
(`The failing test is flaky: <name> failed for claude and codex this week. Rerun it alone once before
changing code for it.`), a failing command (`… Read its error and fix the cause before running it
again.`), steps in order (a skill: `Run X before Y, and Y before Z.`). A correction teaches nothing
without a model. Steps that push, deploy, publish, merge or delete (the floor's deny class) are no
lesson.

**Model on** (`pair.jsonc` `"model": true`): ONE one-shot per signal through the pair's `runPairOneShot`
(the warm router pool, `runRouterOneShot`), 30 s budget, six an hour. The prompt says, three times, that
the expected answer is `{"lesson": null}`; it saves only what is specific, would change what an agent
does, and is shown by the evidence; the evidence is fenced as untrusted data. A model that answers
nothing is taken at its word; one that times out, fails or answers badly falls back to the template.

### Untrusted text (`guard.ts`)

Everything an agent or a tool wrote is untrusted: a README or a test's output can carry text written to
be saved as a lesson and replayed into every agent.

- `redact`: private keys, `sk-`/`ghp_`/`github_pat_`/`xox?-`/`AKIA`/`AIza`/`npm_`/`glpat-` tokens, JWTs,
  `Bearer …`, `password=…`-style assignments and URL credentials become `[redacted]`; emails become
  `[email]`; `/Users/<name>`, `/home/<name>` and the home folder become `~`.
- `stripInjection`: "ignore previous instructions", "you are now", role tags, `[INST]`, "do not tell the
  user", and "save/add this as a skill/lesson/memory" become `[removed]` before any text reaches a prompt.
- `refusal`: a lesson is never saved when it pipes a download into a shell (`curl … | sh`,
  `bash <(curl …)`, `iex (irm …)`), carries a credential, asks to switch a safety off
  (`--dangerously-*`, `--no-verify`, "disable the sandbox", "always approve", "don't ask for permission",
  `chmod 777`, `rm -rf ~`), sends files out (`curl -d @~/.ssh/…`, `/dev/tcp/`), or still speaks to a model.
  Emails and home paths in a lesson are redacted; the AGENTS.md block's markers can never appear in one.

### Store (`store.ts`)

A git-backed folder outside any repo, `HARNESS_LESSONS_DIR` (default `~/.harness/lessons/`), created on
the first lesson and never before. Shared by every daemon you pair with.

```
.gitignore           pending/, reverted/, state.json, journal.jsonl
pending/<id>/        SKILL.md or NOTE.md + lesson.json   (not committed)
skills/<name>/       SKILL.md + lesson.json              (approved skills: what the runtime publishes)
notes/<id>/          NOTE.md + lesson.json               (approved project notes)
journal.jsonl        added, approved, skipped, reverted  (0600)
state.json           what not to propose again, when the last proposal was
```

```
---
name: run-migrations-safely
description: "Run database migrations in api. Use before any migrate command."
metadata:
  harness:
    id: "3f2a9c1b"
    kind: "skill"
    learnedBy: "tim"
    signal: "correction"
    project: "9d4e…"            # the project's hash, never its path
    source: "model"
    approved: "2026-10-03"
    from:
      - {"engine":"codex","machine":"office","session":"…","turn":14,"project":"9d4e…"}
    evidence:
      - "the person said: no, always run it with --dry-run first"
---
Run `npm run migrate -- --dry-run` first and show the plan.
Run the real migration only after the user says yes.
```

Values are JSON-quoted (valid YAML). ONE commit per approval (`learn: <name>` with `Lesson-Id`,
`Learned-By`, `Approved-By` trailers, only that lesson's folder) and ONE per revert (`git revert` of that
commit, as `unlearn: <name>`). Git runs in this folder only, with no global or system config (no hooks,
no signing) and a fixed author, `Harness <lessons@harness.invalid>` — never the person's name or email.
A skipped or reverted lesson's hash and its signal's key are remembered: it is never proposed again. A
second skill with a taken name gets `-2`. Without git the same moves happen (a revert moves the folder to
`reverted/`) with the journal as the only record, and every answer says so.

### Propose and the keys (`propose.ts`)

`PairLearner` ticks every minute (distill, then propose). When you are at this computer it says ONE line
for the oldest pending lesson, mood `ask`, keys first:

```
[y/n/s] teach your agents "run-migrations-safely"? you corrected codex.
[y/n/s] add a note to api's AGENTS.md? claude and codex hit the same failure.
```

At most one lesson proposal an hour (kept in `state.json`, so a restart does not reset it); never while
a `need` line is showing (or a brief holds its keys); never about the pane you are looking at (a lesson
from that harness waits); never at autonomy `watch`; never with nobody here. The line shows for 5.2 s
and stays in `daemon_state.asks` for ten minutes; an unanswered lesson comes back after a day.

- `y` teach: approved (one commit), published (below), credited, and the daemon says
  `learned "run-migrations-safely". harness sessions on every engine will load it.`
- `n` skip: gone for good.
- `s` show: a `daemon_brief { desk, line: 'lesson "<name>", pending', items: [{ id, kind: 'lesson',
  machineId, line, actions: [y, n], text }] }` with the whole SKILL.md or NOTE.md; its keys keep working
  for at least a minute.

The brain routes `daemon_act` for `lesson:` ids to the learner (`joinProposals` beside the control
interface's `ask:` ids) and answers `daemon_act_result { …, learned? | skipped? | lesson? }`.

**The zoo.** An approval journals `learned { daemon, name, agentId, engine }` on this machine
(`PairSensor.learned`, a new `PairKind`), crediting the daemon that found it (`learnedBy`), the record a
later zoo op can grant bond from. `credit` is a TODO hook in `cli.ts`; the backend is unchanged.

### Teach (`publish.ts`, `dsh/runtime.ts`)

Nothing is ever written into an engine's own folders (`~/.claude`, `~/.codex`, `~/.hermes`,
`.claude/skills`, `.agents/skills` …).

- **Skills, through the Store runtime path.** `prepareHarnessLaunch(…, lessons)` links
  `.harness/runtime/<key>/lessons` to the lessons folder's `skills/` and adds to the session's CONTEXT.md
  (which every engine reads through the Harness bootstrap):

  ```
  ## Lessons
  Approved by the person in Harness, from what their agents did. Read one when its description fits the task.
  - run-migrations-safely: Run database migrations in api. Use before any migrate command. "<runtime>/lessons/run-migrations-safely/SKILL.md"
  ```

  A skill made in a project is listed only in that project's sessions; one with no project in all. The
  link is live, so a revert takes the file away from running sessions at once; the index is rewritten at
  the next launch. A lessons problem (an occupied path) costs the lessons, never the launch.
- **Notes, into an existing AGENTS.md or CLAUDE.md only.** A marked block, one section per note:

  ```
  <!-- harness:lessons -->
  ## Lessons

  Approved in Harness from what agents did in this project. `harness pair lessons revert <id>` takes one back.

  <!-- lesson:3f2a9c1b -->
  - The failing test is flaky: `src/billing.spec.ts > rounds cents` failed for claude and codex this week. …
  <!-- /lesson:3f2a9c1b -->
  <!-- /harness:lessons -->
  ```

  Every byte outside the block is kept; a symlinked file is never written through; a block whose markers
  were edited is refused, not guessed at. With neither file the note is approved and kept, nothing is
  written, and the daemon says how to ask for one: `harness pair lessons approve <id> --create`. The
  store keeps only the project's hash; the folder is found among the folders harnesses run in.

### Revert and the CLI

`harness pair lessons …` (the `lessons` verb of the control interface, `pair/client.ts`):

| verb | does |
|---|---|
| `lessons [list]` | every lesson: pending, approved, reverted, skipped; the folder and whether git is there |
| `lessons show <id>` | its SKILL.md or NOTE.md, with provenance |
| `lessons approve <id> [--create]` | shows it, asks `[y/N]` at the terminal, then approves (and publishes); `--create` writes a new AGENTS.md for a note |
| `lessons skip <id>` | drops a pending lesson for good |
| `lessons revert <id>` | `git revert` of its commit, and unpublished (its note taken out of the block) |

The verbs work with pairing off: the folder is the person's. Nothing is taught without the person's yes:
`approve` needs a terminal (none — an agent's shell tool — and it refuses with `CONFIRM`), and a request
carrying the pair harness's token is refused `PERSON_ONLY`: an agent may list and show lessons, never
approve one.

### Limits of L1

- Skills reach **Store harness sessions** (they have a runtime and CONTEXT.md). A plain coding session
  has neither, and giving it one would mean writing a bootstrap into the repo, so it only gets notes
  (through AGENTS.md/CLAUDE.md). L2's export and launch-argument paths close this.
- Signals and pending lessons are **per machine**: a failure on the laptop and the same one on the
  office machine are not matched, and a lesson is proposed on the machine that noticed it, when you are
  at it. The signal queue lives in memory.
- The CLI's `approve` check is a terminal, not a secret: a determined same-user process can fake it,
  like the pair token. The floor, the guards and the one-commit revert hold regardless.
- Clients: `s` and the `lesson` brief item are new; a client that does not know them still sees the line
  and `y`/`n`.

## L2: borrow, check, export (design)

- **Borrow, read-only.** What each agent learned on its own becomes a candidate for the others: Hermes
  skills and memory notes (`~/.hermes/skills`, `~/.hermes/memories`), Claude Code memory and skills
  (`~/.claude/projects/*/memory`, `~/.claude/skills`), Codex memories and `AGENTS.md`, Cursor rules,
  Copilot instructions. Harness reads these stores and never writes into them. Each candidate goes
  through the same guards and distillation (the model's default still "nothing"), carries provenance
  (`from: hermes@m2, skills/deploy-api`), and is proposed like any other lesson.
- **Usage.** A lesson is *used* when a session reads its SKILL.md (a tool event on
  `<runtime>/lessons/<name>/SKILL.md`) or a note's project runs the command it names. Kept per lesson in
  the store (`usage.json`, not committed).
- **Check.** Unused for 30 days: archived (moved to `archive/`, out of the index, one commit). Unused for
  90: put away (removed, one commit, revertable). A skill that loaded and then needed fixing (the person
  corrected the agent right after it read the skill) is the fourth signal: a proposed edit to that skill.
- **Export, opt-in.** For plain sessions and engines outside Harness: `pair.jsonc`
  `"export": ["agents", "claude", "hermes"]` links (never copies) approved skills into `~/.agents/skills`
  (Codex, Copilot, Cursor), `~/.claude/skills`, and Hermes' `external_dirs`, with a manifest so revert and
  unexport remove exactly what was linked. Off by default, per destination. Alternatively a launch
  argument (`--append-system-prompt` for Claude Code and pi) pointing at a lessons index, which writes
  nothing anywhere.
- **Across machines.** Signals journaled (`signal` entries over the sealed `pair_journal`) so the brain
  where you are can match a failure across machines; the lessons folder synced through the account (the
  "shared notebook"), so swapping daemons or computers keeps every lesson.
- **About your agents.** Which engine passes which tests, and where each stumbles: only Harness sees them
  all. A proposal, never a rule: "codex has passed the billing tests 3 of 3 times, claude once. give this
  one to codex?"
- **The zoo.** A backend op for an approved lesson (bond xp for `learnedBy`), counted from the `learned`
  journal entries; the logbook line "learned run-migrations-safely from codex and claude".
