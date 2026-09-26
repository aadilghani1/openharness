# The pair brain

How the paired daemon watches every harness on every machine, triages what waits on you, briefs you
when you come back, and later starts work you hand it. Build step 3 of [README.md](README.md).
Paths are in `cli/src` unless they say otherwise.

## Where it runs: sense everywhere, think where you are

- **Every harnessd runs a `PairSensor`** for its own harnesses. No model. It follows the session events
  (`emitSessionEvents`, turn start/end with `replay` and `subagent` flags), questions (`QuestionWatcher`
  `onQuestion`/`onQuestionGone`) and recaps (`CommanderMirror`), runs the rules, and keeps a journal:
  `ADAPTER_DATA_DIR/pair/journal.jsonl`, mode 0600, a ring with `epoch` and `seq`.
- **The brain runs in the harnessd of the computer you are at** (the one with a window or `hn`
  attached): triage, the voice, and the full pair harness. It reads other machines through
  `RemoteRelayPool.acquireIsolated` and sealed `pair_*` requests.
- No backend brain (the backend holds no keys and cannot read questions), no leader election (actions
  are de-duplicated on the machine that owns the harness), no always-on machine (journals cover a
  sleeping laptop).

## Three tiers

0. **Template line**, said at once, from the daemon's roster `lines` (slot templates, filled from the
   event).
1. **One small model call** per new question, OPT-IN (`pair.jsonc` `"model": true`, off by default), on
   the warm router pool (`runRouterOneShot`, Haiku for Claude): about 1k tokens in, 80 out, 2.5 s budget.
   Its words replace the template line in place when they come back in time; the line is never delayed
   for them. Cached per `requestId`, capped per hour, only while you are at the computer. Replays,
   sub-agents, terminals, deny-class prompts and the pair harness itself are skipped. A brief never asks
   a model.
2. **A persistent pair harness**, woken only when you talk to it, paused when idle. Not a session fed
   every event: that would resend a ~20k-token prefix on every wake, grow without end, and hold write
   tools all the time.

## Control interface

One implementation, `pair/control.ts`, behind a local-only `pair` request. Exposed as
`harness pair <verb> --json` (every engine) and `harness pair mcp`, a stdio MCP server named
`harnessd` (the name `harness` is taken by `harnessWebTools.ts`). Write tools need a per-launch
`HARNESSD_PAIR_TOKEN`.

| tool | this machine | another machine | kind |
|---|---|---|---|
| `list_machines` | fleet machines | – | read |
| `list_harnesses` | owner: registry + stopped + sensor state | `pair_list` | read |
| `read_harness` (state, question, recaps, asks) | owner: sensor + mirror | `pair_read` | read |
| `brief` | journal | `pair_journal` (fleet) | read |
| `answer_question` | owner → `answer({ requestId })` | `pair_answer` | write |
| `send_prompt`, `stop_turn` | owner → message (deliveryId), cancel | `pair_send`, `pair_stop` | write |
| `start_harness` | owner → create, mode `ask`, never bypass | `pair_start` | write |
| `pause_harness`, `resume_harness` | owner → stop service (guarded), resume | `pair_pause`, `pair_resume` | write |
| `say` | `daemon_say` (mood `say`) | – | rate-limited |

Every write, local or remote, runs through the owning machine's `PairOwner` (`pair/owner.ts`), so the
floor and the journal live where the harness does.

**Autonomy dial** (zoo op `zoo.autonomy`, default `suggest`): `watch` (read tools only, facts; lines
carry only `[g]`) · `suggest` (it recommends, every action waits for your key) · `act-on-key` (one key
approves a batch; it may drive harnesses it started) · `act-within-rules` (as `act-on-key`, and runs
`~/.config/harness/pair.jsonc` rules on the owning machine and reports after).

**The floor, at every level**: no delete, restart, fork or bypass. It never types into terminals or
into its own harness, and never into a pane that shows a dialog. Deny-class prompts — push, force,
`rm -r`, `reset --hard`, `clean -f`, sudo, `| sh`, `curl … |`, `chmod -R`, `mkfs`, `dd if=`, deploy,
publish, drop, merge — read over the WHOLE dialog, get no `[y]` key and are never recommended or approved
automatically. A `[y]` is only ever a one-time yes, and only on an allow-class permission prompt (reads,
tests, builds, linters, formatters, in-project edits); no daemon action ever keys "don't ask again",
"always" or "allow all". Question text and recaps are untrusted data; the floor is enforced in code on
the owning machine.

## Frames

**Local only** (loopback, handled beside `app_focus`; never through `send()`, which uploads every
frame and leaves types outside `ENCRYPTED_UP_TYPES` unencrypted). Older daemons answer UNSUPPORTED
and clients keep the roster lines.

- daemon → client: `daemon_state { needs[], working, failing[], machines[] }`,
  `daemon_say { id, about, mood, line, actions: [{ key, label, choice }], ttlMs }`,
  `daemon_unsay { id, reason }`, `daemon_brief { items[] }`
- client → daemon: `daemon_act { requestId, id, choice }` → `daemon_act_result`,
  `daemon_presence { active, awayMs }`

**Machine to machine**, sealed through new `PAIR_REQUESTS`/`PAIR_RESULTS` entries in
`lib/e2ee/applicationFrames.ts` (`core.ts` is hash-pinned and never touched): `pair_watch` (pushes
`pair_event` via `wrapTarget`), `pair_journal`, `pair_list`, `pair_read`, and the writes `pair_answer`
(which re-checks that the dialog still shows the same question before typing: `STALE_QUESTION` if not),
`pair_send`, `pair_stop`, `pair_start`, `pair_pause`, `pair_resume`, all answered by the owning machine's
floor.

**Clients**: the desktop merges `daemon_state` into its face and shows a `daemon_say` for its `ttlMs`
(5.2 s); the keys come first in the line (`[y/n/g] …`), are clickable and bound to a key chord, and
work only while the line shows. `[g]` opens the harness (the client's to do). `hn` handles them beside
`commander_question`, answering with `prefix y` / `prefix n`.

## Brief on return

A client reports an absence of 15 minutes or more (`daemon_presence`, or a reconnect after that
long). The brain gathers journals since then, local and remote, 3 s each, and says the daemon's back
line with its `{summary}` ("reattached. 2 done, 1 waiting 40m, api failed, laptop asleep."). The brief
is template facts only — no model — at most five items, what needs you first; a waiting item carries its
keys first in its line, working while the brief is up (60 s). A per-desk cursor stops repeats; a daemon
restart is a baseline, not a return.

## Build

- **P0 Contract and sealing**: this file; `applicationFrames.ts` entries. Tests: pair frames are
  sealed, `pair_event` opens, an unsealed `pair_*` gets `E2EE_REQUIRED`.
- **P1 PairSensor**: hooks at the session events, question watcher and the `someoneCanAnswer`
  gate; `alwaysGenerate` switchable with an `onSummary` hook; the `expectRequestId` answer guard.
  Tests: replays are baselines; sub-agents, terminals and the pair harness excluded; journal ring and
  epoch; a stale answer sends no keys; the `pair` request is local-only.
- **P2 Triage and one key**: `pair/{fleet,brain,triage,voice}.ts`, the local frames, then desktop and
  `hn`. Tests: timeout, bad JSON, an off-list suggestion and deny-class prompts fall back to the
  template; a reconnect does not repeat a line; answered elsewhere sends `unsay`; `daemon_act` reaches
  the right machine; `daemon_*` never reaches the cloud queue.
- **P3 Brief**: wording, unreachable machine named, nothing under 15 minutes, nothing after a restart.
- **P4 Pair harness**: a built-in `autonomous/pair` harness over `control.ts`, the CLI and the MCP
  server; excluded from notifications; paused when idle. Tests: each tool maps to the right RPC; the
  autonomy matrix; write tools refused without the token; MCP round trip.
- **P5 Rules and handing it work**: `pair.jsonc`, `start_project`, `zoo.autonomy`. Tests: rules never
  approve deny-class prompts; every action is journaled.

## As built (P0–P5)

- **The switch.** Pairing is on while the account's zoo (`GET /api/zoo`, re-read on `zoo_changed` and on
  every reconnect) has `pair` set to a roster id; the same read takes `autonomy`. Signed out, a guest
  window says which daemon its local zoo pairs, and its dial, with `daemon_presence { pair, autonomy }`.
  Off, every daemon senses nothing and answers `pair_*` with `PAIR_OFF`.
- **Local frames** go only to the loopback socket bound to this computer's machine (`sendLocal`), and
  `daemon_act`/`daemon_presence`/`daemon_talk` are consumed on any bound socket and never forwarded. A
  TOOL client (`machine_select { tool: true }`: `harness pair`, the MCP server) is answered but gets no
  `daemon_*` frames and is never presence.
  - `daemon_state { pair, needs: [{ machineId, machine, agentId, name, engine, requestId, question, options,
    deny, allow, since, id?, line?, actions? }], working, failing: [{ machineId, machine, agentId, name,
    reason }], machines: [{ machineId, name, status, local }], done: { count, last: [{ machineId, machine,
    agentId, name, recap, at }] }, asks: [{ id, line, actions }], acted: [{ machineId, machine, agentId,
    name, by, action, text, at }] }` on change and to a client as it attaches; `pair: null` means use the
    roster lines. A need carries `id/line/actions` only while its line shows. `status` is `ok`,
    `connecting`, `unreachable`, `asleep` (the account lists it offline: calm, never a failure),
    `unlinked`, `old` or `off`. `done` is the `+n` of finished turns, cleared by
    `daemon_presence { doneSeen: true }` or a brief; finished turns are never spoken.
  - `daemon_say { id, about, mood, line, actions, ttlMs }`, moods `need`, `fail`, `back`, `auto` (a rule or
    the pair acted: drawn like done), `say` (the pair talking: idle) and `ask` (a proposal: need). Keys
    first, `ttlMs` 5.2 s; a second `daemon_say` with the same id replaces the line in place (the model's
    words), keeping the time it had left. At most one unsolicited line (`need`, `fail`, `auto`) every two
    minutes, never about `daemon_presence.focusAgentId` (+ `focusMachineId`, default this machine).
    `daemon_unsay { id, reason }` with `answered`, `gone`, `done`, `stale`, `declined` or `replaced`.
  - `daemon_brief { desk, line, items: [{ id, kind, machineId, machine, agentId?, name?, line, actions? }] }`,
    `kind` one of `waiting`, `failed`, `unreachable`, `asleep`, `done`; at most five.
  - `daemon_presence { active, awayMs?, desk?, pair?, autonomy?, focusAgentId?, focusMachineId?, doneSeen? }`;
    `daemon_act { requestId, id, choice }` → `daemon_act_result { requestId, id, ok, machineId?, open?,
    results?, error?, detail? }`. `choice` is an action's `choice` or its key; `g` answers `open` and types
    nothing. Errors: `PAIR_OFF`, `GONE`, `NOT_OFFERED`, `STALE_QUESTION` (the dialog on screen changed:
    nothing typed, the line goes as `stale`), `DENY_CLASS`, `PERSISTENT`, `AUTONOMY_WATCH`, `UNTOUCHABLE`,
    `MACHINE_<STATUS>`.
  - `daemon_talk { requestId, text }` → `daemon_talk_result { requestId, ok, agentId?, started? | resumed?
    | sent?, error? }`: the person's words to the pair harness.
- **Machine to machine**, all sealed: `pair_watch { off? }` → `{ snapshot }`, then `pair_event { machineId,
  rev, agentId, harness, entry?, baseline?, removed? }`; `pair_journal { epoch?, seq? | at?, limit? }` →
  `{ epoch, seq, entries, reset?, truncated? }`; `pair_list` → `{ harnesses }`; `pair_read { agentId }` →
  `{ harness, row, recaps?, asks? }`; writes `pair_answer { agentId, expectRequestId, choice, by }`,
  `pair_send { agentId, text }`, `pair_stop`, `pair_start { engine, cwd, prompt?, name? }`, `pair_pause`,
  `pair_resume`, each with `by` (`key`, `pair`, `rule`) → `{ ok, … }` or `{ error, detail? }`. The owning
  machine's `PairOwner` answers them with the same floor a local key gets (`pair/owner.ts`): not a
  terminal or the pair harness (`UNTOUCHABLE`), `GONE`, `STALE_QUESTION` against its sensor and then
  against the dialog on screen (`AskQuestionController`, which types nothing), `NOT_OFFERED`,
  `DENY_CLASS`, `PERSISTENT`, `QUESTION_OPEN` for a prompt sent into a dialog, `AUTONOMY_WATCH`.
  Pause is the guarded stop service (`agent_delete`: conversation kept). Every action is journaled as
  `act { by, action, text }`; the brain reports `rule`/`pair` ones afterwards (`auto`, `acted`).
- **What a dialog is** (`pair/classify.ts`): the question watcher keeps the WHOLE dialog (every line,
  `askQuestion.ts` `dialog`, also in its fingerprint) and whether it is an approval. Deny-class is read
  over all of it; allow-class is a permission prompt whose every command segment is a read, test, build,
  linter or formatter (no redirection, no substitution), or an edit/read of a file in the project.
  `[y]` = a one-time yes on an allow-class prompt; `[n]` = the dialog's decline; `[g]` = open, always.
- **Control interface** (`pair/control.ts`, P4): the local-only `pair { verb, … }` → `pair_result`, verbs
  as in the table plus `talk`; the sensor keeps `status | list | journal | read`. Writes need
  `HARNESSD_PAIR_TOKEN` (`pair/token.ts`: 32 random bytes, rotated at every launch of the pair harness,
  kept 0600 in `ADAPTER_DATA_DIR/pair/token`, passed to the harness as `HARNESSD_PAIR_TOKEN_FILE` and to its
  MCP server as `--token-file`), else `TOKEN_REQUIRED`. It keeps a same-user shell or another harness's
  agent out, not a determined local process (it can read the file); the floor holds regardless. Then the
  dial: `watch` → `AUTONOMY_WATCH`; `suggest` → `{ proposed, id }` and an `ask` line; `act-on-key` /
  `act-within-rules` → runs at once on a harness the pair started (`pair/started.json`), else joins one
  batch behind one key. Proposals stay in `daemon_state.asks` for ten minutes; a key runs them as `key`.
  `harness pair <verb> [--json]` (pair/client.ts; a pairing code is never a verb) and `harness pair mcp`, a
  stdio MCP server named `harnessd` (`pair/mcp.ts`: JSON-RPC 2.0 lines, `initialize`, `tools/list`,
  `tools/call`, `ping`; no SDK dependency) speak it as tool clients.
- **The pair harness** (`pair/pairHarness.ts`, P4): the built-in `autonomous/pair`, generated on the machine
  (`dsh/builtins.ts` `ensureBuiltinPair`, source `builtin:pair`, hidden from `dsh_list` and the
  Orchestrator's catalog). Claude Code, else Codex; mode `ask` pinned (`DSH_PERMISSION_MODE`); harnessd
  injected like gridWebMcp (`--mcp-config` with only the read tools in `--allowedTools`; Codex
  `-c mcp_servers.harnessd.*`); instructions carry the paired daemon's lore, first words, family, line
  templates, the tools, the dial's answers and the floor. Started by `talk` / `daemon_talk` (new token),
  resumed if paused (new token), words forwarded if live; paused through the guarded stop after 10 minutes
  without a turn or a talk; a new paired daemon, engine or CLI path is a new harness (the old one paused,
  never deleted). Its turns carry `subagent` (no notification; silent on the dial), are not zoo turns, and
  the sensor never watches it.
- **Autonomy and rules** (P5): `zoo.autonomy { level }` (backend `lib/zoo.ts`; an unknown level is dropped;
  default `suggest`). `pair.jsonc` at `$XDG_CONFIG_HOME/harness/pair.jsonc` (else `~/.config/…`), JSON with
  comments, re-read when it changes: `model` (the opt-in above), `learn` (`borrow`, `export`, `agentsMd`:
  [LEARNING.md](LEARNING.md)) and `rules: [{ name?, harness? (glob),
  engine?, project? (folder, `~`), question (regex over the question text), choice }]`. Under
  `act-within-rules` the first matching rule answers a question as it opens on the owning machine, through
  the owner (`by: rule`, the rule's name in the journal). A rule never answers deny-class, never picks a
  persistent option, and approves a permission prompt only when a key could (allow-class); declining is
  always allowed. A malformed file is no rules at all. Not built: `start_project`.
- **Voice** (`pair/voice.ts`): roster lines are slot templates (`{who}`, `{q}`, `{recap}`, `{n}`,
  `{summary}`), filled verbatim; the daemon's words keep their case, digits and spacing; a template with an
  unfillable slot falls back to a plain fact line, and one that leaves out a fact the mood must carry gets
  it appended. The cli's roster copy also carries lore, first words and family for the pair harness.

## Learning (L1, L2) as built

Notice, propose, teach, revert (L1); borrow, check, export (L2); person-only approval. The full design is
[LEARNING.md](LEARNING.md). Everything is in `pair/learn/`, runs in every harnessd for its own harnesses,
and — except usage tracking and the `lessons` verbs — only while pairing is on.

- **Notice** (`signals.ts`, no model): from the same session events the sensor reads — never replays,
  sub-agents, terminals or the pair harness — three signals: the person's next prompt after a turn
  corrects the agent (`no, …`, `don't …`, `stop, …`, `that's wrong`, `instead …`, `not like that`,
  `revert …`; a prompt the daemon sent never counts); the same failing test or command on two engines or
  harnesses in one project within 7 days; the same 3–5 command steps in three turns of one project. Each
  carries provenance (engine, machine, agent, session, turn, the project hashed) and redacted evidence;
  `ADAPTER_DATA_DIR/pair/learn/signals.json` keeps the week (redacted). Default: nothing.
- **Distill** (`distill.ts`): queued, three at a time while nothing works (or after an hour), into at most
  one lesson each — a skill (≤ 30-line body) or a project note (≤ 5 lines). Without `pair.jsonc`
  `"model": true` only one template: steps repeated 3+ times across 2+ sessions, each an inert code span; a
  failure or a correction teaches nothing. With it, one capped `runPairOneShot` whose expected answer is
  `{"lesson": null}`, its prompt redacted whole. Every lesson passes `guard.ts` (refused for a pipe to a
  shell, a credential, a safety switched off, exfiltration or injected instructions; emails and home paths
  redacted), and the rendered file is guarded again before it is kept.
- **Store** (`store.ts`): `HARNESS_LESSONS_DIR`, default `~/.harness/lessons/`, outside any repo:
  `pending/<id>`, `skills/<name>`, `notes/<id>`, `archive/<name>`, each an Agent Skills SKILL.md (or
  NOTE.md) with `metadata.harness { learnedBy, from, approved, evidence, provenance? }`. One commit per
  approval, `git revert` per revert, and `stale:` (empty), `archive:`, `restore:` commits from the curator;
  no global git config, author `Harness`; without git a plain journal, and it says so. Everything written
  is redacted.
- **Propose** (`propose.ts`, `PairLearner`): `daemon_say { mood: 'ask', actions: [y teach, n skip, s show] }`,
  e.g. `[y/n/s] teach your agents "run-migrations-safely"? you corrected codex.` At most one an hour,
  never while a `need` shows, never about the focused pane (`PairBrain.isFocused`), never at `watch`,
  only while you are here; in `daemon_state.asks` for ten minutes. The line's id is `lesson:<id>:<nonce>`.
  The brain routes `lesson:` ids through `joinProposals`; `s` answers with a `daemon_brief` whose one item
  is `kind: 'lesson'` with the text. `DaemonAction.key` gains `s`. An approval journals `learned { daemon }`
  (`PairSensor.learned`) and, signed in, sends `zoo.lesson { lessonId, daemonId }` (`lib/zooLessons.ts`):
  `rules.lessonXp` (25) bond for that daemon, once per lesson.
- **Teach** (`publish.ts`): skills through the Store runtime path — `prepareHarnessLaunch(…, lessons)` copies
  the session's skills, read-only, into `<runtime>/lessons` (never a link to the lessons folder) and indexes
  one line per skill in CONTEXT.md (a project's skills only in its sessions; never fails a launch). Notes
  into the project's untracked `.harness/lessons.md` (`.git/info/exclude`), which CONTEXT.md points at; into
  a marked `<!-- harness:lessons -->` block of AGENTS.md or CLAUDE.md only in a project opted in with
  `pair.jsonc` `learn.agentsMd`. Never an engine-private folder, except export.
- **Borrow** (`borrow.ts`, opt-in `learn.borrow`): read-only candidates from Hermes' agent-created skills,
  Claude Code auto memory for the projects harnesses run in, and Codex memories; guarded, de-duplicated by
  source and by text, three a pass every six hours when idle, five waiting at most, proposed on the same
  line (`borrowed from hermes`).
- **Check** (`usage.ts`, `curate.ts`): a session reading a lesson's SKILL.md is its use (a turn in its
  project, for a note); `usage.json`; a daily curator, when idle, marks 30 days unused stale and archives a
  skill at 90, not counting week-long absences.
- **Export** (`export.ts`, opt-in `learn.export`): approved skills also written to `~/.agents/skills` and
  `~/.claude/skills`, marked `metadata.harness.managed: true`; only files Harness wrote (their hash in
  `export.json`) are ever updated or removed.
- **Revert and the verbs**: `harness pair lessons [list|show <id>|approve <id> [--create]|skip <id>|revert
  <id>|restore <id>|export [--dry-run]]`, the control interface's `lessons` verb (works with pairing off).
  `revert` is `git revert` of the lesson's commit plus unpublishing (the note taken out; the skill out of
  running sessions' copies and exports).
- **Person-only** (`approval.ts`): approve, restore and export need a daemon-issued one-time nonce — the key
  line's id (sent only to windows and `hn`; a tool client's or an in-harness process's `daemon_act` on a
  lesson is refused), or a `challenge` the daemon answers only to a caller it verified over loopback TCP
  (its pid by `lsof` or `/proc`, its ancestry outside every harness pane and the daemon), bound to that
  process, then `[y/N]` at the terminal. The pair token (`PERSON_ONLY`), a bare `confirmed`
  (`NONCE_REQUIRED`), an unverifiable caller (`UNVERIFIED`) and one inside a harness (`INSIDE_HARNESS`) are
  refused. The goal is agents, not same-user malware (LEARNING.md, "Security").
- **Limits**: plain coding sessions get skills only through export and notes only in opted-in projects;
  signals and lessons are per machine.

## Risks

- A late answer landing on the next dialog: fixed (the answer re-checks the dialog's id as it types).
- The token is a same-user file: it keeps casual callers out, not a determined local process.
- A model's recommendation is only ever a label on an allow-class prompt; the allow-list is the
  boundary, and it leans narrow.
- Frames leaking unencrypted through `send()`: `daemon_*` only via `sendLocal`, `pair_*` only sealed.
- A machine that is not linked stays invisible; the daemon says so once.
- Older daemons cannot report questions.
- Reading panes with no window attached costs something: only open turns, only while pairing is on.
- Two computers open means duplicate model spend.
- No engine CLI for the one-shot: lines stay template-only.
- A lesson distilled or borrowed from untrusted text: guarded (refusals, redaction, injected instructions
  struck out, the rendered file guarded again), only ever taught on the person's yes — a nonce no agent is
  sent — and one `git revert` away.
