# Harness desktop design system

The desktop is a welcoming Mac application around a real terminal workspace.
People should be able to start, find, configure, and manage a harness without
learning terminal notation or memorizing shortcuts. The terminal panes keep
their character, density, colors, font preferences, and direct interaction.

This is the current presentation authority for the desktop experiment. It
supersedes the BIOS, fixed-cell, plain-text-only, bracket-button, and universal
monospace rules in earlier design documents. Keep the existing tabs, panes,
creation, search, and resource-management workflows. This is a UI redesign,
not authorization to change launch defaults, permissions, or data ownership.
The branch remains unmerged until the user requests otherwise.

The [research record](macos-design-research.md) separates Apple guidance,
observations of excellent Mac apps, and our own design choices. The choices
below are Harness specifications, not claims of Apple approval.

## The boundary

| Surface | Presentation |
| --- | --- |
| Terminal output, in-pane composer/find, code and logs | Terminal fonts, terminal colors, exact bytes and existing keyboard behavior |
| Welcome, New Tab, Cmd-N, Cmd-P, menus, dropdowns, pickers, dialogs | System UI typography, real controls, deliberate spacing, semantic colors |
| Settings, Store, setup, sharing, notifications, history | The same desktop system, with hierarchy suited to their content |
| Tabs and pane headers | Preserve compact structure and established activity marks; app controls stay discoverable |
| Footer context | Preserve focused machine/project/branch/PR and model/effort placement; keep user-selected status themes |

Prefer actual platform services for windows, menus, file selection, clipboard,
and accessibility. Shared Flutter surfaces implement the same interaction
conventions on macOS and Linux. Do not describe a Flutter control as an AppKit
control. Do not fork controllers or whole screens to achieve a visual effect.

## Hierarchy and space

Use one obvious starting action, a readable content area, and quiet supporting
information. A title describes the task; an action says what will happen.
Secondary controls should be visible without competing with the content.
Never turn every label into a pill or put a card inside another card just to
create separation. Prefer alignment, whitespace, and a subtle divider.

Use a 4-point spacing rhythm: 4 for tightly related text, 8 between controls,
12 within compact groups, 16 between groups, and 24 at a panel's outer edges.
Small optical corrections are valid when verified at real scale. These are
logical points, independent of terminal cells and terminal zoom.

| Role | Starting geometry |
| --- | --- |
| Compact toolbar/menu control | At least 28 high; content may grow |
| Standard control | 32 high minimum; 10–14 horizontal inset |
| Editable field | 36 high minimum; increase for text scaling |
| Menu row | Natural content height plus 8 vertical inset on each side |
| Small confirmation/rename | 440–480 maximum width; 20–24 outer inset |
| Main composer | 680 maximum width, shared by popup and full-page entry |
| Search | Content-led bounded width, existing list/preview split retained |
| Window edge clearance | At least 16; 24 when space permits |

Never lock a content block to a height that clips enlarged text, translated
copy, a validation message, or a long resource name. Let the content scroll
inside the window. Align the search text, list titles, and detail text; reserve
icon slots so checkmarks and changing states do not move labels.

## Typography

`AppType` owns the system type hierarchy. `DesktopChrome` supplies compact
control, metadata, and heading roles. Use the platform system sans for titles,
buttons, labels, text fields, descriptions, and navigation. Use semibold for
hierarchy sparingly. Sentence case is the default. Avoid uppercase eyebrows,
ASCII prompt marks, and decorative punctuation in normal app controls.

Base sizes are 13 for controls and body, 12 for supporting metadata, 15–17 for
section headings, 20 for page titles, and 28 only for a true display heading.
The message composer remains 15 and search 17. Use comfortable line heights
for prose and tighter ones for single-line controls. Respect accessibility
text scaling; ordinary UI must not resize when the terminal zoom changes.

Use explicit monospace only when it makes the value easier to read: commands,
paths, logs, identifiers, and the user's chosen terminal/status presentation.
Do not use monospace just because a control is for a developer.

## Color, surfaces, and states

Use the existing `AppPalette` as the color source. Do not add a second palette
in each feature. `DesktopChrome`, `AppMenu`, and the app theme derive their
surfaces and control states from it. Shared controls support both appearances
and are reviewed in light and dark fixtures; the desktop currently retains
its existing dark appearance policy. This experiment does not add a mode switch.

Prefer a quiet opaque window surface and a subtly separated popover/dialog.
Use a thin rim and restrained shadow only for floating layers. Preserve the
approved Agent/Repo and Store capsules; standard controls use the shared shape
for their role. Use related corner radii: 8 for small controls/rows, 12 for
compact panels, and 16 for larger floating surfaces. These are starting
tokens, not universal platform constants.

Hover, press, keyboard focus, selection, disabled, and unavailable are distinct
states. Hover gently lifts a control. Press is stronger. Focus has a visible
accent boundary and must not move content. Selection retains its checkmark or
selected state when focus arrives. Disabled controls do not advertise hover
or activation. Increase Contrast strengthens essential boundaries. Status
must remain understandable without color alone.

Normal text should meet 4.5:1 contrast; essential control marks/focus should
meet 3:1 against their adjacent surface. Measure the final composited colors,
not an opacity value in isolation. Do not rely on shadows for focus.

## Controls and menus

Use real buttons, checkboxes, toggles, search fields, and menu items. A label
such as `[ New Harness ]` or `[x] Worktree` is not a desktop control style.
Keep concise labels and recognizable icons. A dropdown exposes its purpose
through a label, useful icon, or disclosure indicator. Tooltips supplement
visible meaning; they must not be the only explanation of an important choice.

Use one visually primary action per task. Cancel is clearly available; a
destructive action names the affected object and never receives accidental
default activation. Keep the existing confirmation policy and operation guards.
Do not invent extra prompts as part of a visual redesign.

Menus share row geometry, checkmark alignment, separators, surface, and focus.
Use icons selectively, especially where repeated symbols add no meaning.
Searchable choosers retain search focus, current selection, and scroll position
when live data changes. Distinguish keyboard highlight from a saved choice.
Show a short explanatory line when a choice changes approval or connection
behavior. Keep full values available through accessibility and tooltips.

## Creation and welcome

Startup and New Tab use the same `NewHarnessForm` and `NewHarnessController`
as Cmd-N, embedded at the same maximum width. The full-page entry has no modal
frame or Close button. Recent sessions sit below the composer with enough
context to distinguish similarly named work. No task starts merely by opening
the page. Each empty tab preserves its own draft.

The popup retains the user-approved 95% dark backdrop and explicit Close
button; outside clicks and Escape do not discard the main form. Child pickers
can close independently and return to the same draft. The backdrop covers the
native footer as well as Flutter content. Do not apply this unusually strong
backdrop to every unrelated popover or sheet.

Agent and project lead above the message. Model, approvals, and profile remain
compact and understandable below; Worktree and branch stay together. Keep the
existing local default and machine selector inside the project search row.
Use the current coding-agent-first order without changing the saved selection.
Long branch names preserve their identifying suffix. Enter submits the message
under the existing keymap and composition rules; the primary action remains
New Harness. No Return glyph is printed on that button.

## Search and navigation

Cmd-P remains the shared searchable picker. Clear, clickable scope controls
explain what is being searched. The empty-prefix scope is Harnesses, not All.
Prefixes and keyboard shortcuts remain available as accelerators. Keep the
same editor and list when the scope changes, with the preview optional.

Results show recognizable identity and concise context. Names come first;
supporting machine/project/branch text is secondary. Unavailable rows retain
their preview and explain why they cannot open. Show authentic progress and
errors in place, not invented status or unnecessary celebratory animation.

Preserve navigation and management in the current right-hand preview. A live
inventory update must not switch the resource being edited. Model Get, Use,
and Stop remain distinct actions. Sharing and security-sensitive operations
keep their existing scope, confirmation, and stale-response protections.

## Interaction and accessibility

Every primary workflow works with the pointer and keyboard. Show the hand
cursor on clickable controls and the text cursor in editors. Shortcuts belong
in menus or quiet hints; never require someone to learn them before starting.
Use the live keymap, preserve standard text editing and input composition,
and keep Enter/Space activation tied to the focused control.

Focus stays within the active task and returns to its trigger on dismissal.
Opening a dialog must not send a keystroke to an agent. Preserve drafts and
pending operation receipts; a late response must not reopen a dismissed form
or affect a different pane. Accessible names describe purpose, selection,
value, availability, and result. Hidden native chrome must leave the AX tree.

Motion is optional feedback, never a prerequisite to act. Typing, hover,
selection, and keyboard navigation respond immediately. Small transitions
may clarify a surface change after review; honor Reduce Motion, avoid scaling
live terminal content, and avoid continuous decorative motion outside the
established working-state glyphs.

## Verification and completion

Review at real desktop size in light/dark, narrow windows, 160% text, long
names, empty/loading/error states, and changed live data. Exercise pointer,
keyboard-only navigation, IME composition, draft recovery, and focus return.
Use synthetic data for saved screenshots. Inspect actual renders after
building; passing widget tests alone does not establish visual quality or
physical native IME/VoiceOver behavior.

Track the whole migration in [desktop-ui-migration.md](desktop-ui-migration.md).
Retain relevant behavioral tests while replacing assertions that enforce
retired terminal presentation. Validate shared form/controller coverage where
required. Do not call the whole redesign complete until every listed surface
has been reviewed in the running app and its remaining issues resolved.
