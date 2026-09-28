# hn release candidate: concurrent window creation

A fresh check of the merged hn source found a real asynchronous creation race.
[CI run 36384795117](https://github.com/autonomous-ai/openharness/actions/runs/36384795117)
failed on Linux x86-64 because window 18 contained `FAST_19`.
The corresponding [0.1.0 release run](https://github.com/autonomous-ai/openharness/actions/runs/36384791426)
was cancelled before its publish job ran. Its tag remains a record of that
unpublished candidate; the corrected candidate is 0.1.1.

## Cause and correction

`new-window` reserved a tab but placed its eventual shell in the active tab when
the asynchronous response arrived. Standalone CLI commands did not wait for that
response. Concurrent requests also shared a print format, reply slot, detached
selection restoration and last-created hook target.

The correction anchors placement to the reserved window ID and restores detached
selection before yielding. Each command waits only for the shell it started and
receives that request's output, error and exact session/window/pane identity.
After-hooks retain that identity through their own asynchronous commands.
Background shells open their streams, initial geometry survives placement, and
killed targets delete newly created shells. Cancelled command replies fail rather
than becoming empty successes. Popups retain their separate lifecycle.

The TUI release workflow now runs the native terminal integration before building
and publishing. The CLI release workflow separately publishes and byte-verifies
the current installer only after a production bundle passes its download checks.

## Deterministic regression

`async_creation()` in `tui/tests/native-terminal.py` pauses only its private local
supervisor, then overlaps one plain and two printed detached window requests.
It checks that unrelated reads still finish, creation replies remain pending,
commands and output reach the intended windows, and a later selection is never
replaced by an older completion. Two further requests exercise delayed
`after-new-window` hooks. Killing a reserved target must fail its caller and leave
no supervisor child behind.

The original frozen build fails this case. An independent tmux reviewer verified
the corrected frozen build against real tmux 3.5a and found no blocker. The final
macOS binary has SHA-256
`f27733e1bef6136ae63a1812bce65000ced42feddb83f8489b8298180664ddc5`.

Local verification passed:

- 122 release unit tests.
- Full mock-daemon E2E and local-shell lifecycle, including exact 176 KB paste,
  detach/crash recovery and daemon loss/reconnection.
- Full native terminal comparisons: concurrent creation, cancelled-target cleanup,
  retained exits/signals, hooks, respawn, startup typeahead and 1-by-1 geometry.
- All four native and rendered terminal-attribute comparisons.
- Release workflow YAML and installer shell syntax checks.

These tests use frozen copies, disposable homes, guarded ports, explicit hn and
tmux sockets, and cleanup of their own processes. They do not use a real daemon,
real harnesses, default servers or the installed hn. The creature remains outside
the TUI. Linux CI and publication are separate gates recorded on the release PR
and workflow runs; this document records the correction and local evidence.
