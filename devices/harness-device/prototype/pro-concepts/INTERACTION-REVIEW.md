# Pro companion: interaction review

2026-09-29. An interaction and simplicity review inspired by the requested design
perspectives; this is not the opinion or participation of the named people.
Baseline inspected: main `59ce00535b5fd6ecb06e3bc0b41e46c8ae0e76a3` in
`/private/tmp/pro-concepts-20260929/source`.

## The selected concept

The user's words **“take a little company” identify page 06, Field companion**.
Page 01 says “A little company. A lot of possibility.” The selected design is the
solid purple octopus in a green landscape, not the ASCII portrait on dark green.
See `tools/design.py`, `field()` and `generated/06.png`.

The creature is the contact point, the desktop is the work surface, and the Pro
is an extension of the hand. Preserve the warmth and the landscape while making
the same physical action mean the same thing every time. More display area earns
clearer text and fewer hidden modes, rather than more controls on the home face.

## Recommended composition

All positions are native 720-square pixels. Use 40–44 px outer margins and an
80 px minimum touch target where space permits. The approximately 71 mm square
active area makes an 80 px target approximately 8 mm wide. Avoid 46 px strips as
the only means of reaching an important action.

| Region | Geometry | Purpose |
| --- | --- | --- |
| Quiet header | x44..676, y28..86 | Small Harness/tab context on the left; real host connection on the right. This is status, not a swipeable tab strip. |
| Main contact surface | x40..680, y106..580 | A single stable target for voice, pane swipes, desktop scroll and the hold launcher. Summary and mail never change this target. |
| Full creature | roughly x160..520, y160..474 | The page 06 illustration, at one fixed full size when there is no summary. |
| Small creature | roughly x278..442, y118..298 | One fixed small size when there is summary text or reading. No summary-length-dependent sizing. |
| Summary | x48..672, y330..562 | 36–40 px type with 46–50 px line spacing, at most four readable rows. Text gets priority. No trailing open arrow. |
| Current pane/activity | x44..676, y598..644 | One stable baseline. Idle shows pane name; working shows pane and a concrete activity or `Working`. It can alternate as on the dial, but never goes blank. |
| Learning hint | x44..676, y670 | `Tap to talk · hold for more`, small and quiet. Hide after familiarity if persistent learning state already exists; do not build a new preference merely for this. |

Keep the landscape a backdrop. Use the dark near hill as a naturally quiet text
surface. When there is longer summary text, simplify the landscape behind it;
never run text across the octopus, sun or changing tentacles. Flat fills are a
good match for RGB565. Reuse the selected palette: sky `#d9e8cf`, near hill
`#2b5949`, distant hills `#a8bf92` and `#6d966f`, sun `#fbebad`, cream text
`#f1f0d8`, purple body `#9974af`, dark facial details `#352d49`.

The default screen should show the actual selected pane, not a perpetual slogan.
Use “Take a little company.” only when no pane is available or on a first-run
welcome state. Do not claim “Docked” from charging alone; host connectivity is a
separate fact from external power.

## Gesture contract

| State / starting region | Input | Result |
| --- | --- | --- |
| Home, main surface, with or without a summary | Stationary tap | Begin voice to the selected pane. The summary is preserved underneath. |
| Home, main surface | Horizontal swipe left/right | Choose next/previous pane, once per contact. The visible name changes only with the selected target. |
| Home, main surface | Vertical drag | Scroll the selected pane's desktop output, continuously, with existing host inertia. No local screen navigation. |
| Home, main surface | Hold for 650 ms | Open the launcher. Consume this entire contact through release; choosing a destination requires a new contact. |
| Home, resting while app is busy | No input | Creature works gently; status remains available even when no live activity text exists. |
| Voice, main surface | Tap | Finish capture and send using the existing direct-send contract. Visible hint says `Tap to send`. |
| Voice, main surface | Hold | Finish into review when the host supports drafts. Visible hint changes to `Release to review` only after the threshold. |
| Voice | Discard control | Cancel capture/upload, return to the previous stable screen, retain prior summary and carried text. |
| Voice | Review control | Explicit alternative to the hold gesture; only enabled with draft support and live capture. |
| Any scrollable local list | Vertical drag | Scroll that list. Never also activate the row the finger leaves on. |
| Any screen while app state changes | Still-held finger | Cancel the old contact. A fresh release and press are needed for the new screen. |
| Screen asleep | First contact | Wake only; consume the contact. |

Single tap is enough for voice regardless of summary, unread mail, or creature
mood. Do not add double-tap, pinch, two-finger swipe or pressure semantics in this
revision. The current adapter exposes only one contact; those gestures would be
unreliable and substantially harder to learn. Avoid a hardware power-button
overload until its sleep/power-latch behavior has been reviewed separately.

Use a consistent direction claim in both the UI recognizer and scroll module.
A reasonable Pro starting point is 20–24 px motion slop, 70 px horizontal pane
threshold and a 1.25 directional dominance requirement. A diagonal contact with
no clear direction does nothing. Once a contact has become a drag, returning it
to its origin does not make it a tap. These are proposed thresholds that need
native replay and physical observation; they are not measured usability results.

## Voice is a visible, pinned state

The screen must distinguish `Starting`, `Listening`, `Sending`, and the host's
eventual work/result. While listening, eyes orient toward the user, the body
breathes subtly and tentacles respond to input level. Do not animate at an
unrelated speed that suggests speech is being captured before capture starts.

Keep the recipient name visible and pinned throughout a recording. Desktop
focus changes must not retarget an in-progress capture. `Discard` stays available
during starting and processing. Swipes while recording cannot hide the microphone
or change recipient. A delivery failure remains understandable text with an
explicit retry path; do not turn transport failures into unrelated inbox mail.

Suggested voice geometry: header contains `To <pane>`; creature stays within
x170..550,y160..450; live status around y505. Main tap-to-send surface spans the
full x40..680 width. At y600..690 use two generously separated 240×80 controls:
`Discard` at x56 and `Review` at x424. The two labels say what happens, rather
than using an ambiguous square stop symbol. If review is unavailable, omit its
action instead of simulating it. A separate Send button is unnecessary when the
whole creature is the direct-send target and the hint is explicit.

## A small launcher preserves the entire app vocabulary

Hold opens a separate, clearly titled sheet with six large, labeled destinations:

| Row | Left | Right |
| --- | --- | --- |
| 1 | Panes | Tabs |
| 2 | Inbox | Read output |
| 3 | Machines | Controls |

Suggested bounds: x40/376; each tile 304×122; rows y144,282,420. A persistent
`Back` action is centered in a 280×80 bottom target. Parent screens retain their
own titles. Launcher must be reachable when there are no agents or no notices;
disabled destinations explain their state, while brightness and local controls
remain available offline.

Controls contains Model, Stop current turn, Companion, Brightness, Sound,
Find Harness, New Harness, Latest output and Select text, filtered by the
existing negotiated capabilities. Stop remains an explicit confirmation. Drafts,
questions, forms, model choice, selection/carry and machine switching retain
their existing token/revision checks and host semantics.

Inbox should be unmistakably an inbox: title `Inbox`, position `2 of 4`, sender
and text; quiet paper or cream inset over the green environment. It is not another
home face. Browsing messages does not focus the desktop. `Open on desktop` is an
explicit action; Back returns to the creature. A held letter is the home unread
signal and does not create a new central tap meaning. Mail delivery animation
runs once for a new event, not whenever history is restored.

Read output uses the larger screen for text, one small companion, scroll position
and explicit Back/Open actions. Swipes scroll local text there; the title and
stable controls make the mode change visible. Do not let an upward swipe from
the lower half secretly jump home.

## Concrete source issues to fix or preserve

Line references below describe the inspected baseline and will shift with edits.

1. **A Pro written control can activate after cancellation or scrolling.**
   `ui_habitat.c:2777–2802` runs `pro_written_control()` before the
   `scrolled || s.touch_cancelled` branch, then dispatches solely from the release
   coordinates. `input_cancel()` at 510–520 retains `pressed_action` and its
   rectangle. Thus a contact invalidated by a view/roster change can still target
   the old action; a vertical drag that ends within a row can also scroll and
   select it. Gate activation on an uncancelled contact that is not owned by
   scrolling, guard, hold, or directional drag. Use a realistic button slop
   separately; never treat down-inside/up-inside as sufficient.

2. **Pro voice and many secondary hit targets are still round geometry.**
   `render_voice()` at 1546–1564 creates x33,y97,w400,h274 on a 720 face. The right
   side of the visible creature cannot finish voice. `render_notice()` at
   1484–1500, `heading()` at 713–717, and most question/form/draft controls also
   retain 466 constants. Updating artwork alone cannot fix this. Every new screen
   must supply matching native-coordinate hits and explicit page controls.

3. **The gesture dead band breaks deliberate taps.** `gestures.c:35–43` recognizes
   taps only at 25–350 ms and holds at 650–1800 ms. A 400 ms press does nothing.
   Existing Pro code attempts to repair this only for a short written-control
   whitelist at `ui_habitat.c:676–680`, which excludes many controls. For the new
   Pro face, a contact released before the hold commits should behave as a tap
   if it stayed within slop. Preserve the explicit hold-consumption behavior in
   `surface_tick()` at 805–809.

4. **Small movement thresholds are duplicated.** `gestures.c:24–28` and
   `scroll.c:5,106–110` each claim at 12 px. Raising only the UI threshold lets
   the scroll module consume an otherwise valid tap; raising only scroll still
   loses UI taps. Tune them together under the new Pro build flag, keeping the
   round dial's contract unchanged.

5. **The old top tab strip conflicts with a simple anywhere-swipe model.**
   `ui_habitat.c:2697–2700,2737–2755,2778–2779` lets y<96 own horizontal motion
   as tab-strip browsing. A new layout without the strip must disable this
   ownership and use the launcher for tab choice. Otherwise an invisible strip
   consumes gestures.

6. **Several swipe-to-home checks use y=400 as the bottom edge.**
   `ui_habitat.c:2864–2865` turns an upward drag beginning in the lower 320 px of
   a Pro secondary screen into Home. This collides with reading. Remove that
   shortcut for the new Pro face and retain an explicit Back target.

7. **Keep the existing voice and stale-state protections.** `view()` at 521–539
   prevents live recording, forms and active drafts from being hidden. Voice
   dispatch at 2197–2274 pins IDs, validates question/form/draft revisions, and
   aborts host work. A new visual layer should not bypass these paths.

8. **Touch failures are not releases.** `touch_habitat.c:145–151` cancels malformed
   or failed contacts and swallows until a trustworthy up. Sleep handling at
   159–164 and 172–178 likewise consumes the contact. Preserve these; do not
   introduce new gesture inference from missing samples. The driver currently
   requests one point at 106–107, so multitouch has not been implemented.

9. **Brightness should be physical on this LCD.** `ui_habitat.c:587–597` scales
   color values in software. `pro_panel_bus.c:68–72` exposes actual PWM backlight
   control. The new face should keep palette contrast stable and map its setting
   to physical backlight, avoiding double dimming and washed-out RGB565 shadows.
   `panel_pro.c` belongs to the alternate LVGL path, so changing it alone will not
   necessarily affect Habitat's display path.

## Verification recommendations

The existing `firmware/test/test_touch_ui.py` extracts real production function
bodies but constructs a round-only state struct. `run.sh` does not compile its
Pro branches, so the written-control problem above is not covered. Add an
independent native 720 px contact replay, with the actual `habitat_touch()` and
input cancellation functions, before relying on a passing dial suite.

Required replays: summary/no-summary central tap; left and right pane swipe;
vertical desktop scroll without navigation; diagonal cancel; hold opens exactly
one launcher and its release does nothing; release after a roster/view change;
list drag that returns to the starting row; button drift without scroll; voice
finish at the right edge of the new target; immediate Discard; voice guard;
back-to-back contacts after sleep or sensor failure. Check rendered bounds and
target non-overlap for every new Pro screen. Test the unchanged round suite too.

Preview all states on the same landscape before physical installation, including
long names, 90-character summaries, empty inbox, offline, recording-start error,
waiting upload, a question with long options, and a multi-part draft. Physical
review can validate perceived brightness and touch ergonomics; native checks
cannot prove those subjective properties.

## Implemented review checks

`firmware/test/test_pro_touch_ui.py` now enables `DEVICE_PRO_COMPANION` and
compiles the actual production state, contact handler, hold timer, cancellation,
action construction, home/voice renderers, canvas and proportional fonts. Bitmap
decoding is stubbed with the generated artwork dimensions; these tests do not
claim to inspect rendered illustration pixels or physical touch behavior.

The initial run reproduced the canceled-control, scroll-and-select, 450 ms tap,
small thumb drift, missing launcher and lower-half reading regressions described
above. Follow-up replays caught mismatched gesture-axis selection after a small
diagonal start, offline launcher inaccessibility, and draft holds becoming taps.
The root implementation corrected those paths under the Pro companion flag.

The initial **26 scenario groups passed** with both `undefined,bounds` and
`address,undefined` sanitizers. They include a 49-contact cancellation matrix,
stable actual home targets for short/long summaries and unread mail, fixed small
creature dimensions, eight actual home states with long pane names, full-width
voice finish, non-overlapping text and targets, immediate Discard, and an enabled
Stop sending action while processing. The generated Pro asset/font files are
prerequisites; the test does not install firmware or issue live app actions.

Commands from the source root:

```sh
python3 devices/harness-device/firmware/test/test_pro_touch_ui.py
SANITIZERS=address,undefined python3 devices/harness-device/firmware/test/test_pro_touch_ui.py
```

The final expanded run passes **36 scenario groups under ASan/UBSan** against
the production source. The additional cases verify the actual enlarged
`(32,24,496,80)` header: four-direction drags cancel without focusing, scrolling,
opening tabs, or arming the hidden legacy workspace preview; both quick and
deliberate stationary presses open the current tab picker. The real production
`A_TAB` dispatch and reload handler are included in this fixture: selecting the
current multi-pane tab returns directly Home without sending a command; changing
tabs keeps Home visible through the correlated snapshot and never passes through
Panes. The carry card renders the actual selected words while retaining source
attribution. Final log:
`/private/tmp/pro-concepts-20260929/companion-pro-touch-final.log`.

The final five groups check the existing saved-pattern lock on the square face:
all nine rendered dot centers match actual input centers; the radius boundary
admits 51 px and rejects 53 px; repeated samples do not duplicate dots; short and
wrong patterns stay locked; the configured test pattern unlocks without also
starting voice, then the next fresh tap works. Lock checks stub credential
verification only and never create/change a real saved pattern. The update page's
three text lines are centered, bounded and have no touch actions.
