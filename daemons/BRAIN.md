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

0. **Template line**, instant, from the daemon's roster `lines`.
1. **One small model call** per new question or return, on the warm router pool (`runRouterOneShot`,
   Haiku for Claude): about 1k tokens in, 80 out, 2.5 s budget, else the template. Cached per
   `requestId`, capped per hour, only while you are at the computer. Replays, sub-agents, terminals
   and the pair harness itself are skipped.
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
| `list_machines` | machine list + peers | – | read |
| `list_harnesses` | registry + sensor state | `agents_list` + `pair_watch` snapshot | read |
| `read_harness` (recap, tail, question) | mirror / capture / sensor | `agent_recent` / `pair_read` | read |
| `brief` | journal | `pair_journal` | read |
| `answer_question` | `answer({ expectRequestId })` | `pair_answer` | write |
| `send_prompt`, `stop_turn` | message (deliveryId), cancel | `message`, `cancel` | write |
| `start_harness` | create, mode `ask`, never bypass | `agent_create` + `creationId` | write |
| `pause_harness`, `resume_harness` | stop service (guarded), resume | `pair_pause`, `agent_resume` | write |
| `say` | `daemon_say` | – | rate-limited |

**Autonomy dial** (zoo op `zoo.autonomy`, default `suggest`): `watch` (read tools only, facts) ·
`suggest` (it recommends, every action waits for your key) · `act-on-key` (one key approves a batch;
it may drive harnesses it started) · `act-within-rules` (runs `~/.config/harness/pair.jsonc` rules on
the owning machine and reports after).

**The floor, at every level**: no delete, restart, fork or bypass. It never types into terminals or
into its own harness. Permission prompts matching push, force, `rm -rf`, deploy, publish, drop or
merge get no `[y]` key and are never recommended or approved automatically. Question text and recaps
are untrusted data; the floor is enforced in code on the owning machine.

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
`pair_event` via `wrapTarget`), `pair_journal`, `pair_read`, `pair_pause`, and `pair_answer`, which
re-checks that the dialog still shows the same question before typing (`STALE_QUESTION` if not).

**Clients**: the desktop merges `daemon_state` into its face and prefers a matching `daemon_say`
within 2.5 s; `[y]`/`[n]` are clickable and bound to a key chord. `hn` handles them beside
`commander_question`, answering with `prefix y` / `prefix n`.

## Brief on return

A client reports an absence of 15 minutes or more (`daemon_presence`, or a reconnect after that
long). The brain gathers journals since then, local and remote, 3 s each, and says a template line
("welcome back. 2 done, 1 waiting 40m. nothing on fire."; a failure or an unreachable machine
replaces "nothing on fire"). One model call fills `daemon_brief` only when there are 3+ items, a
failure or a question. A per-desk cursor stops repeats; a daemon restart is a baseline, not a return.

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

## As built (P0–P3)

- **The switch.** Pairing is on while the account's zoo (`GET /api/zoo`, re-read on `zoo_changed` and on
  every reconnect) has `pair` set to a roster id. Signed out, a guest window says which daemon its local zoo
  pairs with `daemon_presence { pair }`. Off, every daemon senses nothing and answers `pair_*` with `PAIR_OFF`.
- **Local frames** go only to the loopback socket bound to this computer's machine (`sendLocal`), and
  `daemon_act`/`daemon_presence` are consumed on any bound socket and never forwarded:
  - `daemon_state { pair, needs: [{ machineId, machine, agentId, name, engine, requestId, question, options,
    deny, since, id?, line?, actions? }], working, failing: [{ machineId, machine, agentId, name, reason }],
    machines: [{ machineId, name, status, local }] }` on change and to a client as it attaches; `pair: null`
    means use the roster lines. `status` is `ok`, `connecting`, `unreachable`, `unlinked`, `old` or `off`.
  - `daemon_say` as above; `daemon_unsay { id, reason }` with `answered`, `gone`, `done` or `stale`.
  - `daemon_brief { desk, line, items: [{ id, kind, machineId, machine, agentId?, name?, line }] }`, `kind` one
    of `waiting`, `failed`, `unreachable`, `done`.
  - `daemon_presence { active, awayMs?, desk?, pair? }`; `daemon_act { requestId, id, choice }` →
    `daemon_act_result { requestId, id, ok, machineId?, error?, detail? }`. `choice` is an action's `choice`
    or its key. Errors: `PAIR_OFF`, `GONE`, `NOT_OFFERED`, `STALE_QUESTION`, `DENY_CLASS`, `UNSUPPORTED`,
    `MACHINE_<STATUS>`.
- **Machine to machine**: `pair_watch { off? }` → `{ snapshot }`, then `pair_event { machineId, rev, agentId,
  harness, entry?, baseline?, removed? }`; `pair_journal { epoch?, seq? | at?, limit? }` → `{ epoch, seq,
  entries, reset?, truncated? }`; `pair_read { agentId }` → `{ harness }`. `pair_answer` and `pair_pause`
  answer `UNSUPPORTED` until the stale-answer guard and the control layer land; so does the local answer
  behind `daemon_act` (after the brain's own checks). Local-only `pair { verb: status | list | journal |
  read }` → `pair_result`.

## Risks

- A late answer landing on the next dialog (fixed on main first; see the stale-answer PR).
- Frames leaking unencrypted through `send()`: `daemon_*` only via `sendLocal`, `pair_*` only sealed.
- A machine that is not linked stays invisible; the daemon says so once.
- Older daemons cannot report questions.
- Reading panes with no window attached costs something: only open turns, only while pairing is on.
- Two computers open means duplicate model spend.
- No engine CLI for the one-shot: lines stay template-only.
