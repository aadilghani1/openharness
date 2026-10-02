# Validation and release

The release clock starts at the user's request, not at the tag. The October 2
[audit](performance/2026-10-02-release-process-audit.md) found repeated full suites,
baseline investigations, local environment failures, and waiting before publishing.
Keep a short validation plan and reuse its evidence through merge and release.

## Select the checks once

| Change | Required scope |
| --- | --- |
| Documentation or static artwork | Relevant links/schema/assets, visual inspection when the result is visual |
| Isolated CLI behavior | Typecheck, affected unit tests, relevant integration/real-engine tests |
| Isolated desktop behavior | Analyze changed Dart code, affected widget/unit tests, native/browser check for the surfaces changed |
| Shared state, authentication, protocol, dependencies, or unclear impact | Full suite for each affected component, plus relevant integration/platform checks |
| Packaging, signing, updater, or release workflow | Script/workflow checks and artifact/manifest contract checks; use a test publication when publication behavior changes |

This is an impact assessment, not a file-extension bypass. A small deletion change
can require real disposable worktrees and lifecycle tests. A resource label change
does not require retesting every unrelated engine. Keep required coverage gates.
An unavailable native engine or platform is an unverified row, never a passing one.

Use the pinned toolchain and lockfile. Check free disk space before installing,
compiling, or starting a broad suite. Do not clean other sessions' files to make room.
Run independent checks concurrently, with enough capacity for their workers;
two commands each spawning every CPU is not useful parallelism.

Manual **CI → Run workflow** accepts `scope`: `cli`, `tui`, `backend`, or `full`
(the default). `cli` includes typecheck, all CLI tests, updater coverage, release
bundle checks, and the serial/login-shell OS/Node matrix. `tui` includes its native
CLI integration tests. Select `full` for cross-component changes or uncertain impact.
The workflow remains on demand; this change does not introduce new required gates.

CLI's default Vitest suite runs as four file shards on separate runners, retaining
its worker cap and isolation. Typecheck, lockfile checks, guard fuzz, registry and
release-bundle integration, and updater coverage run alongside them. Guard fuzz
keeps its own process and timing budget. The existing `typecheck-test` job is the
aggregate: it requires passing shard/contract jobs and verifies that their JSON
reports cover every discovered file exactly once. Missing, duplicated, failed or
unfinished results fail it. Review the complete workflow result, including the
serial/login-shell matrix, rather than one early finishing job. Shard reports,
inventories and the combined summary are retained as artifacts for seven days.

For repository process tooling only, `scope=process` runs its Python regression
tests without installing or building unrelated components. It does not validate
application changes. Workflow edits also need `actionlint` and a run exercising
the changed workflow behavior, such as the desktop cache preparation checks.

Desktop SDK and pub caches are prepared on `main` when their inputs change by
**Prepare desktop caches**. Run that workflow on `main` after cache eviction if
needed; it does not publish anything. Release tags restore those caches without
saving another tag-specific copy. Cache misses still install the pinned SDK and
resolve dependencies normally. macOS enables Swift Package Manager before pub get.
The shared keys include SDK version/commit, OS/architecture, and the dependency
lockfiles for pub. Signing, notarization and artifact checks remain required.

Native TUI CI tests and builds the shipped musl target in the same Cargo output
directory. Dependency caches are keyed by target, Rust toolchain, and Cargo inputs;
cache hits still run every test. The ten native TUI fixtures run two at a time,
using their own homes, socket names, and mock ports. CI retains each fixture's log
and validation receipt as an artifact. To run the same set locally after building:

```bash
python3 scripts/validate-tui-native.py tui/target/release/harness-tui
```

This needs tmux, the pinned Node runtime, and the CLI's installed dependencies.
Do not run another copy on the same host at the same time: each fixture has a
separate port, but separate invocations use the same reserved fixture ports.
TUI release platform builds run alongside unit tests. Native release checks run
against the actual Linux artifact, and publication waits for both unit tests and
all platform builds/native checks. A build-only run uses `publish=false`.

## Bound checks and preserve the result

`make validate ARGS=".harness/validation-plan.json"` runs an explicit plan, at most
two checks at once, without installing tools or retrying tests. Create a local plan
with only the checks relevant to the diff, for example:

```json
{
  "reason": "DSH doctor/materialize shell isolation: typecheck and affected behavior",
  "minimum_free_gib": 2,
  "checks": [
    {
      "name": "cli-types",
      "cwd": "cli",
      "argv": ["node", "node_modules/typescript/bin/tsc", "--noEmit"],
      "timeout_seconds": 180
    },
    {
      "name": "cli-dsh",
      "cwd": "cli",
      "argv": ["node", "node_modules/vitest/vitest.mjs", "run", "src/dsh/command.spec.ts", "src/dsh/materialize.spec.ts", "--maxWorkers=2"],
      "timeout_seconds": 180
    }
  ]
}
```

Commands use argv arrays; use separate checks for independent work. CLI and desktop
checks can run together if memory/disk allow it. Put dependent operations in separate
plans. A scoped desktop test command should name its affected files and start with
`flutter test --no-pub --concurrency=2 --timeout=60s ...`. Two workers are a starting
point, not a fixed cap for a full suite. Choose and record a worker count that fits
the host and other running checks: eight VM workers were validated on a 16-core,
64 GiB Mac in the [baseline repair](performance/2026-10-02-desktop-baseline-repair.md).
Chrome and native integration tests ignore Flutter's concurrency option.
Tests legitimately needing longer can declare that explicitly. Start a necessary
broad desktop run early, with
an outer limit (initial budget: 15 minutes); investigate a timeout instead of waiting
through multiple ten-minute stalled fixtures. Budgets are diagnostic deadlines,
not permission to turn failures into success.

For Desktop VM tests, `make desktop-test` provides a bounded full-suite command.
Use `make desktop-test ARGS="test/affected_test.dart --workers 2"` for named files,
or add `--flutter /path/to/flutter` when the pinned SDK is not on `PATH`.
It runs the selected files once, with half the host's logical CPUs capped at eight
workers by default; lower `--workers` when memory or other running checks need it.
Its `--timeout 900` budget includes the initial test process and any recovery.
Dependencies must already be installed. Browser files under `test/web/` and native
integration checks remain separate; this command does not validate those platforms.

The Desktop command records every attempt, its log hash, registered/completed case
counts, existing skips, worker count, source and toolchain/environment identities
in `.harness/validation/*-desktop-*/receipt.json`. A file counts as verified only
when all its registered cases and setup/teardown work finish successfully.
Only Flutter's exact pre-test `Invalid WebSocket upgrade request` loader error
can trigger recovery: no cases or root group may have registered in that file,
every other file must be complete, and the source/environment must still match.
Those files run once more with one worker, within the original budget. Assertions,
unknown errors, missing files/cases, timeouts and cleanup failures cannot trigger
recovery. A second startup failure still fails the command. Successful recovery
is explicitly `passed_after_startup_retry`, with the failed attempt preserved;
it must not be described as an uninterrupted passing run. Use `--no-loader-retry`
when diagnosing the startup failure itself. This bounds its cost; it does not fix
the external trigger, which remains unproven.

The runner writes logs and `receipt.json` under ignored `.harness/validation/`.
It records source commit/tree, dirty-source fingerprint, start/end times, exit codes,
timeouts, and disk preflight. A source edit during validation invalidates the receipt.
Timeout or Ctrl-C terminates only process groups started by that invocation. Tests
remain responsible for any deliberately detached daemons. macOS/Linux are supported.
Choose a lower disk minimum only for a plan whose known requirements justify it;
the default is 2 GiB, not an estimate of a full Flutter build's needs.

## Reuse evidence without hiding regressions

Record the tested SHA/tree, toolchain, dependency lock, selected checks, results,
and links in the PR. A clean squash with the same tree preserves evidence. After a
rebase, examine the diff and rerun checks covering new interactions or conflict
resolutions. Do not reuse results across dependency/toolchain changes. A dirty
receipt identifies the tested working copy, not HEAD alone.

A passing CI run satisfies the equivalent full local check; don't repeat both
before merge and then again on the merged commit. Check the merged source identity
and rerun only validation invalidated by the merge. Native checks absent from CI
still need their own evidence.

For deterministic local checks, the runner can do that comparison and reuse the
original logs. Add an explicit `reuse` contract to each eligible check:

```json
{
  "name": "desktop-toolbar",
  "cwd": "desktop",
  "argv": ["flutter", "test", "--no-pub", "--concurrency=2", "--timeout=60s", "test/native_toolbar_sync_test.dart", "test/status_menu_test.dart"],
  "timeout_seconds": 180,
  "reuse": {
    "inputs": ["desktop"],
    "toolchain": [["flutter", "--version", "--machine"]]
  }
}
```

Run the plan normally first. After a documentation edit, rebase or squash, pass
its receipt to `make validate ARGS=".harness/validation-plan.json --reuse
.harness/validation/RUN/receipt.json"` (on one line). Unchanged eligible checks
are labeled `reused`, with the original timestamps, log and duration; changed or
failed checks run. A mixed failed run can contribute its independent passing
checks. There are no automatic retries and no test selection inferred from paths.

Inputs are literal checkout-relative files/directories and include tracked and
untracked source, deletions and file modes. Declare every relevant component,
fixture, configuration and dependency lock; prefer a whole component to an
incomplete hand-picked file list. Supply version commands for every tool involved.
The runner also compares the check command, executable, checkout, OS, inherited
environment and its own implementation. Tool/environment values are hashed, not
written to receipts. Missing/modified logs, changing source, failed cleanup and
an unavailable toolchain cannot satisfy reuse. Install dependencies from the
declared lock; generated or ignored build/dependency directories are not source
inputs. Reinstalling or manually modifying them requires a fresh run.

Leave out `reuse` for real engines, mutable services/hardware, native visual or
physical input checks, and performance measurements affected by host load. Their
external state needs fresh evidence. A reuse contract documents a reviewed scope;
it cannot prove that the author included every dependency. The
[October 2 pre-merge audit](performance/2026-10-02-premerge-validation.md) records
the motivating failures and the measured effect.

For a failure, isolate the failing test once. If its code, fixtures, dependencies,
or environment changed, investigate it as a possible regression. Otherwise check
existing baseline evidence before starting another baseline run. Link the exact
failure, baseline SHA, and relevant file/lockfile comparison. If no valid evidence
exists, perform one bounded baseline reproduction of the affected test. Preserve
the failure as a maintenance item; a baseline failure is not a passing full suite.
Do not repeatedly run thousands of tests to rediscover it. The October 2 desktop
[baseline record](performance/2026-10-02-buffered-diagnostic-validation.json) is
historical evidence, not an allowlist: changes to those paths need fresh checks.

If a broad run is interrupted, retain completed-file evidence only when every
registered case in that file finished and its source/environment still match.
Run every incomplete file again. A tester startup/loader error leaves that file
unverified; isolate it once and retain the original error beside the new result.
Report the combined coverage and any retries explicitly. This is not an
uninterrupted passing suite, and it is not permission to retry assertion failures
until they disappear.

## Complete the authorized release

Once required checks pass, merge, verify the resulting source, and tag that source
using the existing release scripts. Do not introduce an additional full-suite phase.
For a client/server change, publish required server support before exposing clients
that need it. Independent product releases may build concurrently; preserve their
source/version compatibility and manifest publication safeguards.

Check the live version and artifact checksum, and give the user the release link
promptly. Broader maintenance testing must not silently turn into another release
gate after shipping. Record these UTC timestamps in the PR or release task:

- Request received; implementation ready; required validation started/completed.
- Merge; each product's release trigger and live publication; completion reported.
- Pauses and waiting, with their known reason. Mark missing data unknown.

For Desktop, use the existing release command with `--wait` to follow the exact
tag and source through completion:

```bash
make release-desktop ARGS="--notes-file /path/to/reviewed-notes.md --wait"
```

The workflow's `publish` job downloads all six public artifacts three at a time,
using the updater's Dart user agent, and checks every version, full SHA-256, and
size. It starts immediately after publication on the same runner.
Each transfer has a total deadline; any failure makes the workflow fail and keeps
the JSON receipt in the `desktop-release-verification` artifact. A successful
verification satisfies that release's download checks: report completion instead
of downloading everything again locally. The watcher requires this job to pass
and checks the tag's full SHA, so another release's success cannot satisfy it.

Different Desktop versions may build concurrently. The shared release lock covers
publication and its public verification, so a second workflow cannot change the
live version midway through that check. Versions are checked before building and
again immediately before publication. A late older version fails as superseded;
do not retry it over a newer live release. All four platform manifests must contain
exactly the six expected entries for one version. Artifact writes are create-only,
and the final manifest write requires the GCS generation read by the publisher.
Concurrent external changes therefore cause a failure instead of being lost.

For publication changes, run the local process suite and the disposable GCS
contract check on the candidate branch:

```bash
gh workflow run release-desktop.yml --ref BRANCH -f version=0.0.0 -f test_publication=true
```

This mode skips all product build/release jobs. It uses tiny public fixture objects
under `harness/desktop/.publication-check/<run>-<attempt>/`, checks actual GCS
preconditions and downloads, and removes only that run's prefix. It exercises
normal publication, duplicate/older versions, incomplete platform sets, concurrent
manifest writes, and immutable artifact collisions. It cannot publish an app.

For a release made before that job existed, or to investigate a download failure:

```bash
python3 scripts/verify-desktop-release.py 1.2.51
```

This is read-only. A failed verification after publication means the release may
already be live; inspect the receipt and fix the cause rather than blindly
retagging or retrying immutable artifact uploads.

Report both total elapsed time and its stages. For small changes, aim to return to
the team's previous 10–15 minute merge/release overhead; publishing duration alone
does not demonstrate that target. At ten minutes without progress, identify the
blocked phase and its next action instead of silently extending testing. Compare
the next ten tasks using request-to-completion data before claiming an improvement.
