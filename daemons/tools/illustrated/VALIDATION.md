# Desktop illustrated Tim validation

Validated on 2026-09-29 with Flutter 3.47.2 / Dart 3.13.2 and Xcode on macOS.

- All 628 bundled PNGs decode and match their generated dimensions, transparency
  bounds and manifest hashes. Regeneration produces identical assets.
- 202 daemon and render tests pass, including 63 actual widget render fixtures
  for eggs, hatching, growth, cards, light/dark themes and workspace widths.
- 26 lifecycle tests pass, including feature-off geometry, native/Flutter hover,
  focus preservation, Cmd-P dismissal before/after the preview delay, and a
  disabled slot preserving unread work.
- 1,538 native AppKit titlebar checks pass, including all 314 compact frames,
  bounded image caching, asset-path validation, layout and hover events.
- Analysis of every changed Dart source and test file reports no issues.
- The universal macOS release build passes for Intel and Apple Silicon. Its
  local ad-hoc signature verifies and all 628 PNGs are present in the bundle.
  This is a review build, not a notarized public release; no installed app was
  replaced. Its updater uses an unavailable loopback metadata URL so the review
  build cannot silently switch to a public release.

Commands run from `desktop/`:

```sh
flutter test --no-pub test/daemons test/daemon_review_render_test.dart
flutter test --no-pub test/daemon_off_test.dart
bash tool/check_swarm_titlebar.sh /path/to/flutter --window-layout
```

Full-repository analysis also encounters an inherited duplicate
`connectWithCode` declaration in `integration_test/native_workspace_e2e_test.dart`
and existing third-party xterm lints. Those files were not changed by this work.

The illustrated art does not alter earning rules, ownership, hatch outcomes,
consent or saved progress. Rolled traits remain metadata; this first Tim pass
uses the curated purple artwork rather than drawing arbitrary markings.
