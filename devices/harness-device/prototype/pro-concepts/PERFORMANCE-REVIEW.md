# Pro companion latency review

Read-only audit of the `.2` companion path on 2026-09-29. Source lines below
refer to the code before the performance changes. This is a performance plan,
not a claim that input latency has been measured on the glass.

## Evidence and the first changes to make

The saved physical `.2` boot receipt reports one full 720×720 paint:
`raster_max_us=66849`, `frame_max_us=67926`, `bytes=1036800`. Raster therefore
accounted for about 98% of this paint. It excludes scene construction and image
decompression, and there were no touches. The receipt also reports 42,387 bytes
free internal RAM, largest block 19,456, 24,708,000 bytes PSRAM, and 12,268 bytes
free renderer stack. Source: `/private/tmp/pro-concepts-20260929/companion-flash-result.json`.

The built SDK configuration is 400 MHz, 200 MHz PSRAM with XIP, 128 KB L2 cache,
and 1 kHz FreeRTOS tick. Do not use the old benchmark's literal `cpu_mhz=240`
and `panel_mhz=40` labels when interpreting Pro results.

1. Optimize the opaque image and solid rectangle raster paths first. A full
   repaint is CPU raster dominated in the one available hardware sample. The
   animation agent owns these changes and pixel-equivalence checks.
2. Measure and remove synchronous image inflate from the model lock if it is
   appreciable. `display_habitat.c:397–412` locks across `habitat_scene_take()`;
   `pro_visual.c:35–52` decompresses a changing hero frame to 367,500 bytes of
   PSRAM from inside that call. The priority-7 touch task and application state
   updates need this same lock. This is a code-proven blocking path; its wall
   time is not yet measured.
3. Correct input telemetry before comparing cadence settings. Existing
   `input_last_us` is a useful heartbeat clue, not an accurate touch-to-frame
   measurement. It can credit the wrong frame and misses release-to-action.
4. Schedule actual visible frame changes. Do not turn a static offline face or
   a menu into a permanent 30 Hz scene builder merely to improve responsiveness.

## What currently determines latency

`change()` (`ui_habitat.c:355`) marks dirty and immediately notifies the renderer.
`ulTaskNotifyTake()` (`display_habitat.c:465`) is interruptible. Thus the current
100 ms Pro animation clock is **not a 100 ms input delay**. A notification
arriving during paint is retained and consumed at the end of the frame. There
is one renderer; an in-flight paint still has to finish before another scene.

The renderer has priority 5 and touch priority 7 on core 1. Touch can preempt
rasterization, but cannot mutate UI state until the renderer releases
`model_lock`. Priority inheritance helps the lock owner finish; it cannot make
image inflation disappear. The existing two 24-row internal DMA buffers already
overlap preparation of the next strip with the previous DMA. Keep their fence
discipline. Larger strips are not a justified first change with only a 19 KB
largest free internal block and a raster-dominated result.

The GT911 path currently registers no interrupt (`touch_gt911.c`). The touch
task polls every 20 ms without a contact and every 4 ms during a contact
(`touch_habitat.c:187–189`). First-contact sampling can therefore add up to
roughly 20 ms, plus I²C and the controller's own scan interval. Measure I²C
duration and the controller configuration before claiming a tighter bound.
Lowering idle polling globally trades battery and shared I²C bandwidth for
latency. An interrupt with polling fallback is the better eventual tradeoff,
but needs the actual GT911 interrupt mode and board reset/strap behavior
verified. Do not guess the edge or change that bring-up while tuning raster.

## Cadence: 100 versus 50 versus 33 ms

`surface_tick()` currently dirties a visible non-quiet Pro face on `now/100`.
`habitat_next_wake_ms()` first picks that deadline, then overwrites it with
125 ms if voice is open. Make the voice deadline a minimum, not an assignment.
The Pro voice also runs the old curved-status shimmer timer even though its
new renderer does not use `s.status_phase`; remove that Pro-only wasted wake.
The shared ASCII body clock still advances `character.motion.frame` and can
dirty Pro scenes although Pro selects its own bitmap frame. Retain shared
reaction state (pressed, gaze, level and finite reactions), while decoupling
unused ASCII-body redraw requests when practical.

Generated bitmap timing is idle 150 ms, working 90 ms, attention 140 ms, done
55 ms, asleep 220 ms, booped 35 ms. Offline is one static asset. Listening
currently overrides its table duration with a four-frame 100 ms loop and a
125 ms input-level update. A faster generic poll cannot invent new poses.

Best bounded design: expose an actual next visual deadline/frame identity
from the selector. Dirty only when the asset identity, gaze, level, mail pose,
text or state changes. Combine that deadline with hold, model and voice
deadlines using `min()`. For looping art use `duration - elapsed % duration`;
stop scheduling a clamped one-shot after frame 23; return the normal long idle
deadline for offline, quiet, locked, hidden or sleeping UI. Input always wakes
immediately independently of that deadline. Recompute deadlines after paint
or use an absolute deadline so expensive paint does not add another full
interval to every frame.

If a temporary fixed clock is needed, 50 ms for active visual states improves
working/done sampling at modest cost. The 35 ms boop still loses poses at
50 ms; a short 33 ms clock is appropriate for that finite reaction after raster
and decode timings fit the budget. Do not use 33 ms for steady idle/offline.
If model+raster+DMA p95 exceeds the interval, skip obsolete animation frames
and keep the clock tied to elapsed time; never queue animation frames.

A scheduling-only model of the generated frame IDs is in
`/private/tmp/pro-concepts-20260929/pro-frame-cadence.py` and `.json`. It ignores
other UI wakes and runtime cost, so it is not a device benchmark. In a 60 s
idle loop it gives the same 399 frame changes at 100/50/33 ms, but respectively
200/800/1,419 duplicate timer ticks. Offline produces 599/1,199/1,818 duplicate
ticks and no image changes. The 840 ms boop displays 8/16/23 of its 23 changes.
This supports deadline-driven animation over a permanent faster poll.

## Safe decode/cache options

The present single renderer is the only writer of `portrait.memory`; paint
finishes before it decodes another image. That is safe despite both scene
records pointing into this memory. A new background prefetch worker writing
the same memory would race with raster and corrupt the currently displayed
scene. Copying a bitmap struct is not ownership of its pixels.

The lowest-complexity lock improvement is two-phase preparation: under the
model lock, choose immutable asset descriptors and assemble the scene; outside
it, on the renderer task, resolve those descriptors into the existing caches;
then damage/raster/paint. No new worker or shared mutable pixel lifetime is
needed. A first miss still costs display latency, but no longer stalls command
dispatch or microphone start behind the UI mutex.

For immediate reaction, optionally keep the first frame of every mood and the
five gaze/touch poses resident in both sizes. Conservative raw storage is
5,775,900 bytes before duplicate-asset deduplication. This is affordable in the
measured PSRAM and costs no new internal DMA allocation. It is preferable to
pre-decoding every mood: all 8×24 hero and compact frames need over 85 MB raw.
Pre-decoding one complete mood in both sizes costs 10,663,200 bytes and should
only be chosen after heap/audio headroom and benefit are measured.

If threaded prefetch remains desirable, use distinct ready/in-use/free slots,
publish a slot only after a complete decode, and retire it only after the
renderer finishes all raster reads. Never hold model_lock across inflate or
wait for a prefetch worker while holding that lock. Keep any worker below touch
and audio priority, wake it for a concrete next asset, and cancel stale work
on mood/view changes. Do not add another large internal task stack without
measuring the already-limited internal heap. Cache misses must have a bounded
fallback rather than deadlocking the scene.

## Measure actual contact, action and presentation separately

Reuse `perf_bench.c`'s sequence-tag idea (`begin`, `capture`, `commit`), not the
unmodified synthetic fixture. The fixture resets the model, creates sixteen
fake agents, and loops forever; it must never run against the live bridge.
Its ABBA toggle only stops the old character body clock, so it does not disable
the independent Pro clock. Its expected text also describes the round UI.

For passive real input, retain these timestamps with a monotonic event number:

| Timestamp | Location and purpose |
| --- | --- |
| `read_begin`, `sample` | Immediately before/after a successful GT911 read; split I²C from later delay. |
| `lock_wait_begin`, `dispatch_begin` | Around `display_lock()` in the touch task; expose mutex blocking. |
| `mutation_done` | After `habitat_touch()` under that lock; mark accepted DOWN, UP/action and axis-start separately. |
| `model_begin`, `scene_captured` | Renderer under the same lock; copy the event sequence into this scene's local tag after construction. |
| `raster_begin`, `first_submit`, `last_copy_done` | In paint/fence; account for CPU work and final framebuffer-copy completion. |

Do not overwrite an unpresented DOWN measurement with UP or another contact.
Use a small bounded pending ring and report dropped/coalesced events. For each
scene capture exactly which event numbers it includes under model_lock. An old
scene already in raster/DMA must never satisfy a newer event. Commit only a
tagged scene with actual visual damage; mark a no-op as no visual change,
rather than reporting a deceptively fast success. The existing
`input_us <= paint_started` check does not prove this: DOWN is stamped before
the touch task gets model_lock, so an earlier model snapshot can satisfy it.

Report separate p50/p95/max for:

- DOWN → first pressed/gaze feedback.
- UP → resulting voice/menu/pane view (excludes how long the user held down).
- Sample → command enqueued for desktop scroll/pane selection.
- Model-lock wait, scene construction, decode, damage, raster and paint.

Scroll is chiefly a desktop action; local repaint completion does not measure
its end-to-end result. Host acknowledgment/presentation needs separate host
timestamps. No framework can turn USB/host response into zero latency.

Use the existing `on_color_trans_done` timestamp, stored in internal memory by
the ISR, and copy a complete sample outside the ISR. Keep percentile storage
or a compact histogram bounded; avoid printf/logging per touch in the critical
path. Export aggregate samples periodically. Preserve the DMA fence callback:
`on_refresh_done` is a panel scan event, not permission to reuse a DMA buffer.

Copy completion is not photon latency. The Pro uses a continuously scanned
60 Hz framebuffer, so scan position adds up to roughly another frame period.
A high-speed camera or photodiode is needed to validate actual glass response;
an optional refresh timestamp is a useful bound, not proof of first pixel.

## Acceptance experiment

Collect at least 40 phase-jittered actions per case before and after each
change: hero DOWN/UP, small-summary DOWN/UP, listening stop/discard, menu open,
pane switch and vertical desktop scroll. Include concurrent live audio and
host updates. Compare p95, not just the fastest sample. Track idle frames,
model invocations, decoded bytes, raster time, heap largest block and audio
underruns. Verify offline/quiet/sleep produce no periodic image copies and
menus do not inherit an invisible creature clock. Preserve pixel-equivalence
and existing real-handler gesture regression gates. A 33 ms target is accepted
only when it improves delivered frames/input tail latency without raising
missed touch samples, audio errors or idle work.
