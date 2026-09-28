# Daemons: handoff (2026-09-27)

Where the daemons work stands, what was decided, and how to continue. The feature itself is described
in `daemons/README.md` (the contract), `daemons/BRAIN.md` and `daemons/LEARNING.md`; the build spec for
the work in progress is `docs/research/2026-09-27-daemons-eggs-individuals-spec.md`; the release plan
is `docs/research/2026-09-27-daemons-rollout.md`.

## Decisions (all made by the product owner)

- **Drop 1 is `init`** (init(8), PID 1, the parent of every daemon): ten animals hiding in Unix names,
  drawn as FILLED plates in colour (line-printer density shading from shape models), animated:
  tim (the octopus: tmux improved), gnu, lynx, mutt (common); yak, gopher, bug (rare); tux, auk
  (legendary); beastie (secret). The old drops `unix` and `tty` are kept in the roster with
  `hold: true` and no dates: never drawn or shown. Decide on them later, as a step up.
- **tim is a species; every hatch is its own individual** with a server-rolled seed, traits and a
  serial, and a name the user gives it at the hatch. Traits read as flags
  (`tim -c coral --spots --glasses --fidgety`); each species has 6 colour families, its own
  markings, shape proportions and 3 rare extras; a card shows how rare the combination is
  (`1 in 2,130`). **Duplicates of a species are allowed** (identical individuals are practically
  impossible). The first 4 hatches are always a new species; after 8 hatches with no new species the
  next is new. No `diff` egg.
- **The status line** keeps one-line sprites (8 cells); an individual with a rare extra uses that
  extra's one-liner; a fidgety one animates twice as fast; colour and markings do not show there.
- **Eggs** are filled plates that crack as you EARN them (whole, a crack, across with a chip, split
  with light, ready with eyes peeking) and crack open when you OPEN them (rock, burst in the rarity's
  light, the top breaks in two and tumbles, the hatchling rises out). Each stage has a one-liner.
- **Server** work stays inside the zoo module (its own files, its own collections), all behind
  `HARNESS_DAEMONS` (off by default: routes not registered).
- **Naming**: user-facing text calls the harness CLI's background process `harnessd` so "daemon"
  stays the creature. Nothing is renamed; it is only a word in docs and a few UI strings.
- All PRs are drafts titled `WIP:`. Do not merge.

## Branches and PRs

| branch | PR | state |
|---|---|---|
| `daemons` | #369 (base main) | Green. Synced with main (merge 2f19cd72). Drop init, plates, colour, held drops, and step 1 of the eggs/individuals spec (the contract: shader materials, egg model, trait-aware models, roster catalogues and one-liners, references, fixtures, cards, README; 5483f911..9707a57f). This handoff. |
| `daemons-desktop` | #370 (base daemons) | Synced with main and the contract (merge 34e77980). **WIP cfae86b9: unfinished**, may not compile. |
| `hn-daemons` | #375 (base ship-hn) | Synced with ship-hn (a40236ae) and the contract (merge 4201a737). **WIP c5668e3c: unfinished**, may not compile. |
| `daemons-server` | none | From `daemons` 9707a57f. **WIP 14a94361: unfinished** (zoo individuals, draw rules, tests half-updated). Merge into `daemons` when green. |
| `daemons-cli` | none | From `daemons` 9707a57f. **WIP b6dddf93: unfinished** (the individual-art service: plateRender.ts, individuals.ts, a worker, frames). Merge into `daemons` when green. |
| `daemons-phone` | none | From `daemons` 9707a57f. **WIP c46b7dc3: unfinished** (phone eggs and individuals). Merge into `daemons` when green. |
| `fix/pane-close-launch-feedback` | #366 | Separate fix, draft. |
| `fix/stale-question-answer` | #367 | Separate fix (question-answer safety), draft; land before #369. |

The WIP commits were saved when the agents building them stopped at a usage limit mid-task; each
commit message says so. Local backup refs of the branches before the sync exist only on the original
machine (`backup/*-20260927`).

## What is left (step 2 of the spec)

Read the spec's "Step 2 protocol" first: it fixes the zoo shape, the ops, and the plate frames so the
parts can be built in parallel.

1. **Server** (`daemons-server`, backend/): the zoo holds individuals (uid, id, seed, serial, name,
   shiny, xp, bond, version, hatched, egg); `paired` is a uid; hatch adds a new individual even for an
   owned species; first-4-new and 9th-new rules; ops by uid (`pair`, `zoo.nickname`); old zoos read as
   individuals (seed 0, deterministic uid); limit 256; tests for all of it; full backend suite green.
2. **Harness background process** (`daemons-cli`, cli/): render an individual's plates with the
   generated models (`cli/src/pair/plates/*.g.ts`, `bakeModel`) off the event loop, cache on disk keyed
   by (PLATE_SOURCE, species, seed), pre-render at hatch, serve `daemon_plate_get`/`daemon_plate` on the
   Unix socket and sealed `pair_plate_get`/`pair_plate` for the phone (applicationFrames.ts, never
   core.ts); the pair brain reads the paired uid's species and name. Full cli suite green.
3. **Phone** (`daemons-phone`, mobile/), **desktop** (`daemons-desktop`, desktop/), **hn**
   (`hn-daemons`, tui/): follow the contract (the roster no longer has `rules.nest`, `rules.egg`,
   `eggs[kind].look`; frames.json has no `nests`), port the references and match every frames.json
   fixture, eggs as plates with the cracking stages and one-liners, the hatch sequence and the optional
   name prompt, the zoo as individuals grouped by species with flags, `1 in N` and a trait log, the
   status line's individual one-liner, individual art from the harness process with the recoloured
   species plate as the fallback.
4. Merge `daemons-server`, `daemons-cli`, `daemons-phone` into `daemons`; merge `daemons` into
   `daemons-desktop` and `hn-daemons`; run every suite; push the three PR branches (drafts, WIP).
5. Later: release per the rollout doc (server dark, CLI, apps, then on for the founder via
   `HARNESS_DAEMONS_USERS`).

## How to build and test

- Roster and copies: `node daemons/tools/generate.mjs` (writes; baking plates takes minutes, cached by
  a hash), `--check` in CI (~10 s). Cards: `node --test daemons/tools/card.test.mjs`.
- Backend: `cd backend && npm test` (755 passed on `daemons`); `npx tsc --noEmit` shows 5 Prisma
  `harnessSession` errors that come from main.
- CLI: `cd cli && env -u TMUX -u TMUX_PANE npx vitest run` with the cli's stub tmux; one known flaky
  test in `hookNotify.spec.ts`.
- Phone: Flutter 3.47.2 (`flutter test` in mobile/; 609 passed after the sync).
- Desktop: Flutter 3.47.2 (`flutter test` in desktop/; 32 failures also fail on main 93f148d6:
  workspace_account_lifecycle x8, terminal_panel_presentation x4, workspace_expiry_screen x4,
  signout_recovery x2, boot_flow_widget x4, machines_manager x4, and one each in orchestrator,
  local_cli_discovery, environment_setup_screen, open_picker_rendering, first_workspace,
  environment_recheck_timer).
- hn: `cd tui && env -u TMUX cargo test` (123 passed after the sync) and `tests/e2e.sh` against its
  mock (set `HN_TMPDIR` to a fresh temp dir so its sockets stay out of the shared /tmp/hn-<uid>).

## Safety rules for whoever continues

- Tests must never reach a real tmux server: unset `TMUX` and `TMUX_PANE`, use a private
  `tmux -L <name>` socket (setting `TMUX_TMPDIR` alone once killed a real server), or the stub tmux.
- Never launch the desktop app from a worktree: a debug build shares the real `~/.harness` state.
- Never touch the real Harness daemon, `~/.harness`, `~/.claude` or `~/.codex`; never type synthetic
  input into a client that can reach real harnesses.
- The repo is public: no personal paths, usernames or emails in commits.
- `core.ts` (the E2EE keystone) is hash-pinned: new sealed frames go in `applicationFrames.ts`.
- Keep PRs as drafts; do not merge.
