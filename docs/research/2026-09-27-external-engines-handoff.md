# Handoff: external sessions for every engine

Branch `external-engines`, based on `244cfe71` (#387). Not yet rebased, no PR yet.

## What it is

⌘P and the welcome page already found Claude Code and Codex conversations that Harness did not start,
and could take one over from a terminal (#380, #385). This branch does the same for every engine that
keeps its conversations on this computer: Cursor, OpenCode, Kilo, Hermes, Devin, Pi, Command Code,
Muse, Grok, Antigravity and Copilot. Amp is left out: its threads are on its server.

The design, each engine's store and evidence, the edge cases and the test results are in
[the session search note](2026-09-26-session-search.md#every-engine). Read that first.

## Where the code is

- `cli/src/lib/sessionSearch/externals/`: one provider per engine (`scan`, `owners`, `busy`), with
  `types.ts`, `support.ts` (file, process and memo helpers) and `index.ts` (paths and the provider
  list). Every file has a spec beside it.
- `cli/src/lib/sessionSearch/external.ts`: `ExternalSessions` (one list), `OpenSessions` (who has a
  session open, as `terminal`, `app`, `harness` or `maybe`), `stopSessionOwner`.
- `cli/src/cli.ts`: `adoptableSession`, `heldBy`, `takeOverWhenIdle`, and the `onCreateAgent` resume
  path.
- `cli/src/lib/sqliteRead.ts`: an idle WAL store is opened `immutable=1`, so reading never creates
  `-wal`/`-shm` files in an engine's folder.
- Index: `transcript.ts` (`lineTime`, `copilotOwnLine`, `museOwnStream`), `indexer.ts`
  (`historyPass` for database engines).
- Desktop: `swarm_search.dart` (`sessionUnavailable`), `take_over.dart`
  (`engineResumesWithMessage`), `take_over_dialog.dart`, `swarm_navigation.dart`
  (`externalEngineName`).

## Rules this code keeps

- Never write to an engine's store. Never log a scanned process's arguments (they can carry keys).
- Never stop a process on a guess. Only a record, a live lock, or a file held open counts. A process's
  arguments alone make the session `maybe`: refused, never stopped.
- `continue` is sent on *Take Over Now* only to engines that take a first message (Claude, Codex,
  OpenCode).

## State

- CLI: all new code at 100% statements, branches, functions and lines (436 tests in 32 files, no
  `v8 ignore`). Full CLI suite passes except `hookNotify`, which #390 fixes, and
  `backendSocket.gridReads`, which fails only under load (passes alone).
- Desktop: the base commit fails the same 25 tests this branch fails. This branch had one extra:
  `test/environment_recheck_timer_test.dart` failed to load in a filtered run. It is unrelated to this
  change and probably timing, but not yet confirmed.
- End to end, through a sandboxed daemon: real stores read-only (229 sessions indexed, 210 of them
  external), then take-over with made-up stores and stand-in engines (Grok *Now* and *Wait*, OpenCode
  `maybe` refused, stale lock ignored). Results are in the session search note.

## Left to do

1. Run `flutter test test/environment_recheck_timer_test.dart` alone on this branch and at `244cfe71`.
2. Rebase onto `origin/main` (#391, #392 landed; a trial merge had no conflicts), then run
   `npx vitest run` in `cli/` and `flutter analyze` and `flutter test` in `desktop/`.
3. #388 (Codex context blocks, schema 9) touches `transcript.ts` and `store.ts`. Whichever merges
   second reconciles the index schema version.
4. Open a PR against `main`. The owner merges and releases (`make release-cli`, then the desktop
   release); never merge or release without their explicit go-ahead.

## Sandbox end-to-end recipe

Never run a test daemon or tmux against the person's real ones:

- `mkdir -p` the `TMUX_TMPDIR` folder first. tmux falls back to the real default server when it does
  not exist.
- Run with `env -u TMUX -u TMUX_PANE -u XDG_DATA_HOME -u XDG_CONFIG_HOME` and set `HOME=<sandbox>`,
  `PORT=<free port>`, `TMUX_TMPDIR=<folder>`, `ADAPTER_UPDATE_DISABLE=true`,
  `DISABLE_HOOK_INSTALL=true` and `DISABLE_GRID_INSTALL=true`.
- Point each engine's home at its store (read-only), or at a made-up one for take-over tests.
- Set `<ENGINE>_PATH` to a stand-in script that records its argv and forwards `--help`/`--version` to
  the real binary.
- Hold a session with a stand-in owner process in its own `tmux -S <socket>`.
- Afterwards, stop the sandbox daemon and kill both tmux servers. Check that no pane on the real
  server sits in the sandbox folder, and that no new `-wal`/`-shm` appeared in the engines' folders.

## Found in Harness's own code, not changed here

- Cursor's config and data folders are one `CURSOR_HOME` in `discovery.ts`, `subagent.ts` and
  `oneshot.ts`.
- `OPENCODE_DATA_DIR` does not keep a recap out of the person's OpenCode store.
- The hook server and notifier treat a Hermes `tui` session as a sub-agent.
- Command Code's slug in Harness does not match the one Command Code writes.
