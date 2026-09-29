# Harness Pro product and interaction review

2026-09-29. Source baseline: `59ce00535b5fd6ecb06e3bc0b41e46c8ae0e76a3` in the isolated `prototype/pro-concepts-20260929` checkout. Read-only desktop/protocol review; no desktop installation, account changes or remote actions.

The selected direction is **“Take a little company”**, the solid purple octopus in a green landscape. The Pro should feel like a living companion to the desktop, while preserving the round dial's mature command paths. This is a Jobs-inspired product critique, not a claim to represent any real designer.

This document preserves the initial baseline audit and implementation review.
The [connected prototype README](../pro-companion/README.md) describes the final
Pro behavior, current build status and remaining limits. In particular, the new
Pro hold opens Explore, movement thresholds have been adapted, and secondary
screens use the new square layout; baseline findings below are historical.

## Product decision

The Pro is a hand controller first and a glanceable companion second. Its extra pixels should make intent and outcomes readable, not multiply permanent buttons. Keep one large creature, one clearly named recipient, one unambiguous activity line, and a restrained way to reach more commands. A summary changes the composition, never the central tap's meaning.

**Default interaction contract:**

| Gesture | Meaning | Existing implementation |
| --- | --- | --- |
| Tap the creature/body | Start voice for the selected pane, even with a summary | `ui_habitat.c:2825`, `A_VOICE`, worker `audio_client_start_cable` at 2544 |
| Tap while listening | Finish capture and send through the existing route | `ui_habitat.c:2829`, `A_VOICE_STOP` |
| Hold while listening, then release | Review the transcript before sending, if the host advertises drafts | `ui_habitat.c:2839`, `CABLE_FEATURE_DRAFT` |
| Swipe left/right on home | Previous/next open agent pane | `ui_habitat.c:2885`, `A_AGENT` → `cable_client_send_focus` |
| Drag up/down on home | Scroll the desktop's active terminal immediately, with velocity on release | `ui_habitat.c:2717`, `scroll.c`, `cableSession.ts:942` |
| Tap during inertial scrolling | Brake the scroll; the next deliberate tap starts voice | `ui_habitat.c:2808` |
| Hold the home creature | Open Tabs without changing a tab until a choice is tapped | `ui_habitat.c:805`, `tabs_open`, `workspace.c` |
| Tap recipient/pane label | Open the pane picker | `ui_habitat.c:1047`, `A_AGENTS` |
| Tap visible unread/letter affordance | Open Updates; reading and opening are separate operations | `A_INBOX`, `A_NOTICE`, receipt functions at `ui_habitat.c:351–415` |
| Tap labeled Controls affordance | Show rare functions as a readable list | Existing `A_SETTINGS`; currently no dependable permanent Pro entry |

Keep secondary pages unmistakably different from home: an explicit page title, Back in one location, a content field with generous spacing, and bottom actions with verbs. An inbox result is an **Update** with a sender and a position, not a smaller copy of the home companion.

## Already wired into the desktop

Use the shared Habitat state machine and cable worker. A separate Pro application would unnecessarily discard these paths and their revision/receipt guards.

| Capability | Firmware/UI entry | Host and desktop entry | Recommendation |
| --- | --- | --- | --- |
| Pane focus and live activity | `A_AGENT`, `ui_focus_project`, `ui_project_set_busy_tokens`, `ui_project_set_tool` | `cableSession.ts:880`, `:1845`; `app_state.dart:12949` (`dial_focus`) | Primary home behavior; retain “Working” when a live footer is absent |
| Workspace/tab switching | `A_TABS`, `A_TAB`, `ht_workspace_*` | `cableSession.ts:848–856`; `app_state.dart:12991` (`dial_swarm`) | Hold opens a clearly named Tabs sheet; tap commits |
| Spatial pane overview | `render_desk`, `s.tiles`, `ui_tiles_replace` | `CableTile` at `cableSession.ts:195`; desktop active tile shape | Useful large-screen secondary view; don't turn it into permanent dashboard clutter |
| Terminal scrolling | `ht_scroll_*`, `A_SCROLL` | `cableSession.ts:942`; `app_state.dart:12906` → `activeTerminal.scroll` | Preserve streaming down/move/up, not page-at-release emulation |
| Voice and task routing | `A_VOICE`, `A_VOICE_STOP`, `A_VOICE_ABORT`, audio client | `cableSession.ts:1062–1170`, `:1279`; `app_state.dart:12969` (`voice_route_request`) | One-tap creature voice; transparent listening/writing/sent state |
| Read/edit voice draft | `DRAFT`, `DRAFT_OPTIONS`, `ht_draft_*` | `cableSession.ts:1015`; `voiceDraft.ts` | Big readable transcript; explicit Send, re-speak a part, append, undo, discard |
| Questions and choices | `QUESTION`, `CHOICE`, `ANSWER_REVIEW`, `A_ANSWER` | `cableSession.ts:1024–1057`; `questionInbox.ts` | Keep explicit review and send; a glance or swipe must never approve |
| Notifications | `INBOX`, `notice_frame`, `ui_notif_read`, `A_NOTICE_READ` | `cableSession.ts:922`, `:1923`; `notificationRead.ts` | Preserve read-token acknowledgements and only acknowledge after pixels are presented |
| Open an update on desktop | `A_NOTICE` → `A_DESKTOP` | `cableSession.ts:928`; host `openAgent` | A clearly labeled Open action; browsing updates must not move focus |
| Pick machine | `MACHINES`, `A_MACHINE` | `cableSession.ts:842–847`, `:1780`; `machineFleet.ts` | Secondary Controls; preserve availability and error states |
| Model and effort | `MODELS`, `A_MODEL`, `ui_service_model_picker` | `cableSession.ts:857`, `:1059`; host `updateAgent` | Secondary Controls; use host catalog, never manufacture model IDs |
| Stop current turn | `STOP`, `A_STOP_YES` | `cableSession.ts:1012` | Explicit confirmation with named recipient |
| Find existing Harness | `A_FIND` → `FORM` | `cableSession.ts:986`; `app_state.dart:12465`; `device_finder.dart:10` | Reuses real Cmd-P search and explicit row activation |
| Create Harness | `A_FORM` → `FORM` | Same semantic form channel; `DeviceFormPort` | Render the live current field/choice; don't synthesize keyboard presses |
| Read/select output | `SELECTION`, `A_SELECT_BEGIN`, `A_SELECT_FIND`, `A_SELECT_EXTEND` | `cableSession.ts:953`; `app_state.dart:12767`, `:12784`; `windowSelection.ts` | Secondary Controls; vertical drag selects/reads locally, no simultaneous terminal scroll |
| Carry passage between panes | `A_CARRY`, `A_CARRY_DROP`, carry-aware voice | `cableSession.ts:966`; `passageCarry.ts` | Preserve source identity, preview, and explicit drop; show carried state on home |
| Visit latest output and return | `A_LATEST`, `A_RETURN`, `ht_visit_*` | `cableSession.ts:999`; `app_state.dart:12525`; `windowVisit.ts` | Useful reading-place preservation; existing host feature gate remains |
| Fork | Host protocol `agent.fork` exists | `cableSession.ts:932`; `app_state.dart:13000` (`dial_forked`) | Host-ready but no shared UI action currently; defer new surface unless reviewed independently |
| Companion, brightness, mute, lock | `COMPANION`, `SETTINGS`, `A_CHARACTER`, `A_BRIGHT`, `A_MUTE`, `A_LOCK` | Device-local configuration store | Keep functional controls reachable without crowding home |

The desktop itself exposes many additional actions in `desktop/lib/shortcuts/keymap_commands.dart`: pane layouts/zoom, branch and PR inspection, share/invite, clone/restart, new terminal, machine linking, stores, keyboard lessons, history, usage and settings. They do **not** all have corresponding semantic cable operations. Pretending a device button can run an arbitrary desktop command would create a second brittle keybinding system. The existing semantic form and spoken-task routes are the extension points for future work.

`DeviceFinder.supported` explicitly excludes command/help scopes, management mode and split placement (`device_finder.dart:30`). Voice search sanitizes command prefixes; keep this deliberate boundary. `DeviceFormPort.command` rejects stale revisions and scopes each voice query (`device_form.dart:48`). Do not weaken those guards for a prettier screen.

## Hardware-fit interaction findings

* GT911 hardware may support multiple points, but current Habitat requests **one coordinate** (`touch_habitat.c:105`). Pinch, two-finger swipe and palm gestures are not available through this input contract. They should not be advertised as implemented.
* The Pro is physically larger, but the common movement threshold is only 12 pixels (`gestures.c:31`) and a stationary tap is limited to 25–350 ms (`:51`). A normal deliberate button press can drift enough or last long enough to be rejected. Pro buttons need calibrated hit handling while keeping motion ownership and send/approval guards.
* `pro_written_control` (`ui_habitat.c:676`) currently relaxes handling for only seven controls. This makes home labels behave differently from secondary form/model/settings buttons. A consistent Pro control policy is a priority.
* The circular rim model uses round-dial coordinates. Disable or adapt rim gestures for the square Pro instead of exposing a misleading option. Vertical direct scrolling already satisfies the user's request.
* `s.agents` contains controllable agent panes. The desktop's tile shape also includes shell/viewer seats. `focus` requires an agent ID, so “all desktop panes” is not yet a valid claim; label unsupported seats clearly or leave them as overview only.
* Real backlight and high-contrast ink matter more than pure black. Use rich green midtones and cream text from the chosen landscape concept. Reserve brighter saturated accents for state or a single primary action. Static secondary sheets should not redraw continuously.
* Use haptics only for a meaningful transition if the board driver is already verified. Do not invent pressure, hover, orientation or dock hardware signals.

## Implementation order

1. Build the chosen landscape/solid-octopus home **inside shared Habitat**, wire its live mood to the same character state, and preserve pane/scroll/voice behavior. Verify empty, idle, working, summary, disconnected, listening, and voice-failure presentations.
2. Give all secondary pages a square layout using existing state/actions, especially voice review, questions, inbox and Controls. Make Back and Send easy to distinguish. Keep `notice_frame` receipt semantics.
3. Correct Pro hit areas, physical movement thresholds, text wrapping/page counts and obsolete circular assumptions. Extend meaningful native replay checks to Pro coordinates; verify actual target hardware.
4. Only then add flourish: anticipation on touch, listening response to input level, focused working motion, one delivery reaction on new unread content, reduced motion/quiet mode. Familiar motion must explain state rather than obstruct reading.
5. Keep the larger desktop-only feature catalog as future semantic protocol work. No fake command buttons, manufactured keystrokes, unapproved creation or background sending.

Read design guidance: `desktop/AGENTS.md`, `desktop/CLAUDE.md`. No desktop chrome changes are proposed in this prototype.

## Implemented Pro sheets and review evidence

`firmware/main/ui/habitat/pro_controls.inc` implements the secondary Pro presentation against the existing state and actions: Explore, Panes, Tabs, Updates, Machines, Models, Controls, Companion, Read, Question, Choices, Answer review, Selection, Form, Draft, Draft options, Stop and Message. Pro's center tap stays voice on the home face; reading sheets have explicit titles and Back. Updates are inert reading cards with one explicit Open on desktop button. Companion controls expose quiet motion, rest and brightness; circular rim and curved-text options are omitted from this square display.

`firmware/test/test_pro_controls.py` renders those actual sheets with the generated proportional font assets. It passed under native undefined-behavior/bounds sanitizers for all eighteen screens with normal text and capacity-sized unbroken text, asserting glass bounds, no text overlap, minimum target height, read receipt assignment, and explicit Send/Stop plus pending-delivery guards. It also exercised empty updates, form/question errors and uncertain draft delivery. Pixel-exact previews were inspected at `/private/tmp/pro-concepts-20260929/controls-preview/contact-sheet.png`.

The flow review found no lost shared pane/tab/scroll, semantic form, question review or explicit stop path. Four-row lists moving three rows overlap one row; nine-row reading pages moving five rows preserve reading context. These do not make items unreachable. Two integration recommendations were implemented: retain cancellation while transcription is pending (the existing abort protocol supports it), and use `DRAFT_ROWS` rather than a literal five when returning to the previous draft part. A later audit also prompted centered Pro lock-pattern and update screens, so the live interface no longer falls through to round geometry on those paths. These checks are code/native evidence, not a claim that the physical user voice trial has been completed.
