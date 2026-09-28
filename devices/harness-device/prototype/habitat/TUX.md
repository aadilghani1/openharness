# Characters in Habitat

Tim and Tux run the same Habitat application. Tap the character to talk; hold,
then slide down to **controls → Companion / gestures → Character** to switch.
The choice is saved on the dial and survives a restart. Swapping artwork keeps
the current pane, voice session, unread results, preferences and navigation.

`firmware/main/ui/habitat/character.h` is the application interface. Characters
implement the same eight moods: idle, working, attention, done, offline, asleep,
booped and listening. `character_motion.c` owns touch gaze, blinking, microphone
levels, pause/resume, quiet mode and the animation clock. `character_layout.c`
owns title/status text, recaps and portrait size. The character registry selects
the art adapter; artwork never dispatches application actions.

The main screen uses two portrait sizes: full without a summary, and small with
any summary. Summary length never changes the creature size or position. All
summaries use a fixed 28 px font, up to four rows, and at most 90 characters
including any trailing ellipsis. Clipping prefers a whole-word boundary and
counts UTF-8 characters rather than bytes. Complete summaries end naturally.
The small portrait starts at y=92 and the summary at y=230, leaving more room
below the top title and between the portrait and prose. Lower rows narrow to
stay inside the circle; four rows retain the 90-character maximum.
The inbox uses the same small portrait and text budget; the full result stays
available on the desktop.
Fixed **←** and **↗** controls sit 100 px apart below the text
and return home and open the result on the desktop. Each has a 180 × 66 px touch
target, and Open dims and disables while disconnected.

The home screen has three states. Idle with no summary shows only the full-size
creature. Working shows the pane name on the top curve, the full-size creature,
and live activity on the bottom curve. A completed summary shows the pane name
on the top curve, the fixed small creature, and the summary beneath it.
**Working** is the fallback when no more specific native activity is available.
The name and activity stay visible together. Current work has a soft left-to-right
highlight sweep followed by a pause, matching the supplied terminal recording.
The title stays still. Quiet mode, sleeping and touches pause the sweep.
Curved glyph masks stay cached; only the old and new highlight bands redraw.
The 2.048-second cycle has 20 steps at 64 ms, then a 768 ms rest.
Tapping a visible pane name opens the pane picker. Idle has no hidden caption
target; hold and slide up opens panes from the creature in every home state.

The orange trial uses `-DDEVICE_DEFAULT_CHARACTER=tim -DDEVICE_HABITAT_ORANGE=1`.
Tim and text actions use saturated orange `#ff6d00` on the existing charcoal, with
neutral text and a light envelope. This is a compile-time palette; it adds no
image assets, animation state, or allocations. Normal builds keep purple.

Unread updates appear as a solid light envelope held by the creature, replacing
the separate `[n]` counter. Reverse-video ASCII cells provide its filled paper
and dark flap, using the existing text ink and saved brightness. Both characters
share a 1.28-second delivery motion; arrivals
during that motion coalesce. The letter remains until the updates are handled.
Restoring history or returning from quiet mode does not replay the motion.
It layers over the current mood and is put away during voice input. The letter
is part of the portrait, with no separate tap action. Hold and slide right to
reach the inbox.

The central tap always starts voice, including over a summary or a letter.
It never requires a first tap to dismiss the summary. During capture, the pane
name stays on the top curve and animated `Listening` follows the bottom curve.
The timer is hidden. Tim keeps moving at the gentle idle pace, with microphone
reactions layered over his body motion. One tap on the creature stops and sends; the recording screen has no Discard button.
`Sending` uses the same cached-mask highlight sweep, without trailing dots.
Starting, Finding and Writing use the same treatment during their voice states.
Removing the displayed timer leaves recording duration guards unchanged.
Cancelling capture through the existing host lifecycle restores the previous
result. There is no duplicate bottom label on the home screen.

To add a character, append a stable ID and registry entry, then supply its mood
clips and painter for the five portrait sizes. Keep frame and colour data
immutable: the compositor retains two scenes during incremental DMA redraws.
Existing IDs are persisted in NVS and must never be renumbered. The common
interaction suite should run with every supported character selected.

## Multiple USB dials

The desktop uses `CableFleet` to discover every matching USB serial number and
create one `CableSession` per dial. Each session owns its decoder, audio upload,
firmware transfer and reconnect state, while desktop events are sent to all of
them. The shared desktop connection is released only after the last dial leaves.
An offline Tim is intentionally still and gray; connecting another dial must
not leave Tim without a desktop session.

`HARNESS_DIAL_SERIALS` optionally limits discovery to a comma-separated list of
USB serial numbers. Each dial writes its own log under
`~/.harness/logs/usb-<serial>/dial-YYYYMMDD.log`. The fleet tests cover simultaneous
voice uploads, disconnecting during another dial's transcription, USB path
changes, shutdown during an open, and discovery errors.

## Tux artwork

The pumpkin-orange dial uses the selected gallery sample **1363**:
`tux -c midnight --bowtie`, with a blue gradient and pink bow tie.
Its exact gallery frames and traits are retained in
[assets/tux/sample.json](assets/tux/sample.json). The previous ice-blue sample
2138 remains in [assets/tux/ice.json](assets/tux/ice.json) for reference.
The exact source is `daemons/review/traits.html` and `daemons/plates/tux.mjs` at
`2fe1d35dfa31c79ec66a06692ab8c218678f4da1`
(`internal/experimental-creature-2fe1d35`), not current `main`.

[assets/tux/moods.json](assets/tux/moods.json) contains 36 frames derived from
that pinned model with the approved traits, registered eye/beak positions, and
source hashes. The original moods map as follows:

| Habitat | Tux model |
| --- | --- |
| idle | idle |
| working | work |
| attention | need |
| done | done |
| offline | fail |
| asleep | nap |
| booped | boop |
| listening | need + shared microphone expression |

Frames share a 52×24 crop and immutable RGB565 cell colours. Geist Mono atlases
cover the full, compact, brief, reading and shortcut portraits. The firmware
does not run the procedural model or decode images. Unread results give Tux a
letter to hold; offline and sleeping portraits dim. Shared reactions overlay the
registered face cells without changing application behaviour.

Regenerate from the source checkout and then bake firmware data:

```sh
node devices/harness-device/firmware/scripts/import_tux_moods.mjs /path/to/art-checkout 1363
python3 devices/harness-device/firmware/scripts/gen_tux_moods.py
python3 devices/harness-device/firmware/scripts/gen_character_fonts.py
```

The font generator needs Pillow. Geist Mono's OFL license is in
`firmware/fonts/GeistMono-OFL.txt`. The mood generator needs only Python's
standard library and supports `--check`.

Build normal Habitat with Tux as the initial character on an unconfigured dial:

```sh
idf.py -DIDF_TARGET=esp32s3 -DDEVICE_HABITAT=1 \
  -DDEVICE_DEFAULT_CHARACTER=tux -DDEVICE_CREATURE_GALLERY=0 \
  -DDEVICE_FORCE_PROD=1 -DDEVICE_PERF_BENCH=0 \
  -DPROJECT_VER=0.0.87-tux.1363.1 build
```

The default remains Tim when `DEVICE_DEFAULT_CHARACTER` is omitted. A saved
choice takes precedence over the build default. Both characters ship in every
Habitat image. This replaces the earlier standalone Tux animation build.

`test/run.sh` checks both adapters' clocks, moods, portrait sizes, circle bounds,
microphone reactions and colour-aware incremental redraws against full frames.
It also checks preference persistence and runs the production gesture, voice,
recap and notification tests once per character. Tim's original rendering
reference tests remain in place.

## Main integration and orange-dial trial — 2026-09-28

Integrated the `88c0e5c4` handoff onto `main` at `621a2b8f`. Retained the
handoff's hold-and-slide menu and single bottom caption. Kept main's larger
interface font and four-row lists; corrected their question/draft scroll limits
and secondary-screen buttons so text remains reachable and action labels fit.
The form shows the current choice and detail, with errors replacing the detail.

Validation used ESP-IDF 5.5, separate Tim/Tux build directories, and the production
Habitat configuration above. Both images are 777,664 bytes. The complete device
gate passed: 19 built-bridge checks, 796 host tests, framed bridge-to-renderer
replay, and the native ASan/UBSan suite. The touch/notification soak exercises
200,000 updates per character. Rendered screenshots were reviewed for both
characters. These host checks do not establish physical display latency.

The orange trial dial received `0.0.87-tux.1363.4` by verified USB OTA and reported
that version after reboot. A user voice test reached the selected pane. Mute
remained enabled. The production reference dial was not flashed, and the installed
desktop app and CLI 0.3.25 were left unchanged. The multi-dial bridge is integrated
and tested in this checkout; a simultaneous two-dial hardware trial remains open.

Desktop notification placement above the creature and the relevance policy for
old-session/swarm-introduction notifications remain separate follow-up work.

## Orange Tim refinement — 2026-09-28

The orange trial dial (`90:70:69:F3:D8:54`, CST816S) rebooted and reconnected
on `0.0.87-tim.orange.2` after verified USB OTA. This revision uses saturated
`#ff6d00`, moves the summary portrait down 26 px and prose down 40 px, and adds
the terminal-style brightness sweep to the bottom activity curve. It retains
the three home states, curved voice status and filled letter described above.
The letter's touch behavior is unchanged pending the interaction discussion.

The application is 777,936 bytes, 1,328 bytes (0.17%) above orange.1. Its SHA-256
is `8d4477e638f1be00b21fd78cbc6be0370b5cc09c47b296be6e09b61b64c4884a`.
The sweep uses the unused byte beside the arc flag, 128 bytes of temporary
colour-table stack space and one phase byte in UI state; it allocates no heap.
It reuses the existing glyph masks and does not redraw the full screen.

Validation: 796 host tests; full native ASan/UBSan, real bridge replay and touch
soaks for both characters; original 64 arc pixel hashes unchanged; incremental
shimmer frames match fresh renders, including skipped frames and clock wrap.
Full 90-character summaries stay inside the round display. The installed CLI
and desktop executable hashes remained unchanged. The production reference
dial was not updated. Physical touch/audio and ESP32 timing for this revision
remain separate from these automated checks; no new hardware latency claim
is made.

Artifacts: `/private/tmp/harness-orange-tim-layout/` contains the exact image,
release report, actual renderer previews, host-only sweep benchmark and OTA
receipt. A previous full check caught the old summary-bottom bound (380 px);
it was updated to keep at least 16 px above the inbox controls at y=400, and
the complete check passed on the final inputs.


## Listening and sending motion — 2026-09-28

Orange trial revision `0.0.87-tim.orange.3` shows only `Listening`, with the
same cached brightness sweep as `Working`. `Sending` has the sweep and no
trailing dots. Tim keeps the idle body pace while recording, with independent
microphone reactions. Quiet mode and touches still pause motion. Recording
duration limits and dispatch behavior are unchanged.

The image is 777,968 bytes, 32 bytes larger than orange.2. The full bridge,
796 host tests, native ASan/UBSan and both-character touch/replay checks passed.
The listening traffic limit now includes idle body motion: native simulation
transfers 25,772,160 pixel bytes/minute versus idle's 25,499,360. This is a
render-traffic measure, not ESP32 timing. The existing extra 2.5 MB/minute
allowance for microphone reactions is now applied above idle body traffic.

USB OTA verified the image, but the updater stalled closing USB and the dial
did not answer after reboot or USB reset. The updater was stopped, its lease
removed and the existing host restored. A user power cycle recovered the dial;
it reported orange.3 at 15:51:20Z. Desktop/CLI hashes stayed unchanged.
Artifacts and the full recovery receipt: `/private/tmp/harness-orange-tim-voice/`.
Inbox gestures and layout remain under discussion; this revision does not
change them.
