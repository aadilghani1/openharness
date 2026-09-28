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
The inbox uses the same small portrait and text budget; the full result stays
available on the desktop.
Fixed **←** and **↗** controls sit 100 px apart below the text
and return home and open the result on the desktop. Each has a 180 × 66 px touch
target, and Open dims and disables while disconnected.

The home screen has one label on the bottom curve. Idle shows the selected
pane name. While working, it alternates between the pane name and live activity
every three seconds, fading around the transition. **Working** is the fallback
when no more specific native activity label is available. New tool updates do
not restart the cycle. Tapping this label always opens the pane picker.

Unread updates appear as a letter held by the creature, replacing the separate
`[n]` counter. Both characters share a 1.28-second delivery motion; arrivals
during that motion coalesce. The letter remains until the updates are handled.
Restoring history or returning from quiet mode does not replay the motion.
It layers over the current mood and is put away during voice input. The letter
is part of the portrait, with no separate tap action. Hold and slide right to
reach the inbox.

The central tap always starts voice, including over a summary or a letter.
It never requires a first tap to dismiss the summary. Discarding voice restores
the previous result. The top pane label is omitted on the home screen.

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
