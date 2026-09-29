# Pro daemon redesign — installed prototype

The user narrowed the collection to the first drop, `init`, on 2026-09-29.
The authoritative roster is `daemons/roster.json`: Tim, GNU, Lynx, Mutt, Yak,
Gopher, Bug, Tux, Auk and Beastie. Future drops stay outside this device trial.
The Pro remains strictly dock-only.

Installed and verified on 2026-09-29 as `0.0.87-pro.companion.12` on the exact
Pro `E8:F6:0A:E7:64:61`. The 7,393,984-byte image fits the existing app slot
with 863,552 bytes remaining. App-only flashing preserved settings and the
desktop bridge; the prior `.11` application remains available for rollback.
At 120 seconds, live desktop data had produced 212 frames with zero touch-read
failures and no unexpected resets. Native verification covers all ten daemons,
eight moods, two portrait sizes, every scene and atomic appearance preferences.
See [validation evidence](DAEMONS-VALIDATION.json) for hashes and measured
limits. Physical gesture comfort and voice quality still require user review.

Acceptance requirements:

- All ten are distinct code-authored, antialiased bitmap illustrations, with
  eight shared moods, touch gaze, listening/speaking amplitude and held mail.
- Application actions do not depend on daemon identity. The registry and
  artwork adapters own appearance and choreography; recipient, voice, gestures,
  drafts, questions, updates and reading retain one implementation.
- Daemon and Scene pickers on the device preview locally. Use saves; Back
  cancels. Preview swipes never switch desktop panes or start voice.
- Persist stable daemon ID and scene together. Match daemon is the default;
  a manually selected scene survives daemon changes and reboot.
- Remove redundant branding, healthy-link labels and decorative summary
  headings. Keep workspace, daemon, readable output and pane/activity hierarchy.
- Preserve round device behavior and installed firmware.
- No allocations or decompression under the UI lock; only a bounded active
  bitmap working set. Account for decode time when measuring rendering.
- Verify native interaction/persistence, eager versus deferred pixels,
  incremental versus full redraw, every daemon/mood/size, scene changes,
  image integrity and partition fit. Inspect rendered art and actual UI.
- Install only the identified Pro, preserve NVS and boot metadata, retain a
  verified rollback image, and check desktop reconnection and render health.

This is a local prototype selection menu, not a change to desktop zoo grants,
rarities, collection unlocks or releases. No physical battery operation is in scope.
