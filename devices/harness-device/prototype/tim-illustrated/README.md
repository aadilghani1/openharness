# Illustrated Tim on the round dial

This opt-in Tim adapter uses the approved Pro Octo artwork on the round 466 px
display. Tux and the shared Habitat controls remain available. The generated
assets come directly from `../pro-companion/tools/generate_art.py`.

Build with `DEVICE_HABITAT=1`, `DEVICE_TIM_ILLUSTRATED=1` and
`DEVICE_DEFAULT_CHARACTER=tim` on ESP32-S3. The first illustrated installation selects Tim and saves a one-time migration
mark. Later character choices remain persistent, including a switch back to
Tux. The character registry and common mood interface are unchanged.

The two native sizes are 240 × 240 for the full creature and 108 × 108 when text
needs space. Eight moods each have 24 frames: idle, working, attention, done,
offline, asleep, booped and listening. Touch gaze, shared delivery/letter state,
quiet mode, finite reactions and live microphone levels use the same interface.

No SVG parsing, vector drawing, scaling or per-frame allocation happens on the
device. Independent compressed RGB565/alpha frames occupy 3,647,994 bytes of
flash. Two fixed PSRAM buffers occupy 178,608 bytes. Opaque spans copy directly;
only edge pixels blend. Decoding happens outside the UI mutex and only when the
selected asset changes. The existing damaged-region compositor remains in use.

`firmware/test/test_tim_illustrated.py` exercises actual C rendering against an
independent pixel oracle under ASan/UBSan: 391 full/incremental scenes, every
mood/frame/size, clipping, touch gaze and switching Tim → Tux → Tim. It also
checks microphone levels, quiet mode, reaction completion, clock wrap and the
two-allocation bound. Actual renderer previews are under `generated/previews`.

The trial image is `0.0.87-tim.illustrated.3`, 4,417,888 bytes. The user explicitly
identified **28:84:85:90:65:94** as the target round dial on 2026-09-29. Do not
infer another target from a case color or the older Tim/Tux device labels.

Installed and verified on that exact target. The physical board reports 32 MB
flash and retains its existing 16 MB partition layout. The prior 792,224-byte
application was read back and matched its known SHA-256 before any write.
The new image was verified after flashing; partition/OTA bytes and saved
settings matched before boot. First boot changed only the documented character
selection and migration marker. Touch, renderer heartbeat and the selected Tim
artwork were verified in the boot log.

The renderer reserves a 24 KB task stack for the ROM inflater's temporary
Huffman tables. The earlier 6 KB ASCII stack passed an offline boot but
corrupted memory on the first connected illustrated frame; the larger stack
is required on the round target as well as Pro.

The connected `.3` trial reached 1,490 frames at 121 seconds with live pane
updates, zero resets, zero touch-read failures and 12,124 bytes of renderer
stack still free. The reported maximum raster pass was 13.285 ms and the
maximum panel-render pass was 24.530 ms; these are measured passes, not a
claim of zero end-to-end input latency.
