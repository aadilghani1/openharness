# Firmware development boundary

The user reserved production firmware for Diego on 2026-09-30. His approved
commit and release process are the customer release. Do not choose or change
that commit, push to `main`, or publish a release. A production device may receive
Diego's exact code only when the user explicitly requests a production test;
never put a development image on it.

- Round development happens only on `dev/firmware-round` in its own worktree.
- Pro development happens only on `dev/firmware-pro` in its separate worktree.
- Check the branch and working tree before editing. A normal pull or push must
  use that development branch's upstream, never `origin/main`.
- Import upstream fixes deliberately; do not reset, rebase, or merge production
  just because the user asks to continue development. Any proposed contribution
  to production needs separate user authorization and Diego's review.
- Follow [the development workflow](devices/harness-device/development/README.md).
  Run its target check before any flash, then verify the actual device MAC and
  chip before writing. Unknown devices and production references are excluded.
  The development check deliberately rejects production-test deployments; those
  use an isolated, clean checkout of Diego's explicitly identified commit.
- Firmware changes do not authorize replacing the shared desktop app or CLI.
  Keep production reference testing separate from desktop experiments.

These instructions do not grant permission to contact or message Diego.
