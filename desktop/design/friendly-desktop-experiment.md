# Friendly desktop experiment

Requested on 2026-09-28. Local review branch: `experiment/friendly-desktop`.
This experiment follows the user's new direction for the UI around the terminal,
superseding the flat, fixed-cell dialog presentation for the surfaces below.
It is not included in Desktop 1.2.27 and must not be merged without review.

- Cmd-N and Cmd-P are floating dialogs with the same frame, shadow, backdrop,
  typography, and focus treatment. They remain visibly distinct from the workspace.
- Cmd-N opens a compact, centered launch form with Start focused. Machine
  appears in the header; Project and Agent are the two main fields. Approvals
  and the worktree toggle are directly accessible. Branch, Model, and Profile
  live under Options; a quiet summary shows their current values when collapsed.
- The last explicit approval choice is remembered per agent, including Full
  access when selected. Worktree choices are remembered per machine/project.
  Projects without a saved choice keep Worktree on; agents without a saved
  approval mode keep Auto-approve. Drafts take precedence over these defaults.
- Enter on the initially focused Start launches without an extra step. Add task
  expands the same dialog and focuses its multiline editor; Options expands
  settings without opening an empty task. Nonempty restored tasks are always
  visible. Only an empty task can be collapsed, returning focus to Add task.
- In the task editor, Enter inserts a newline; Cmd-Enter or Start launches.
  The shortcut is remappable. Opening a chooser does not submit the task.
  Escape backs out one level before closing the composer. Clicking outside an
  open chooser closes only that chooser; the next outside click closes the dialog.
  A choice or cancellation returns focus to the originating control. Tab and
  Shift-Tab dismiss a chooser without applying a value and continue form traversal.
- Focus stays inside the active dialog. Start receives initial focus for empty
  drafts; restored tasks receive editor focus. Tab from Start wraps to Machine;
  Shift-Tab reaches Close. Tab reaches every visible setting and action without
  stopping on hidden fields. Arrow keys navigate searchable option lists.
  Existing command identities and shortcut remapping remain available.
- Dismissing Cmd-N or switching to Cmd-P preserves its unsent draft in the same
  machine/project/source-pane context. Another source pane gets its own defaults.
  Explicit Store products/tasks retain their existing ownership rules. Restoration
  uses the current destination tab and never duplicates a pending launch receipt.
- New, Open, and Clone use the selected machine directly. Each prompt offers
  Change machine. Choosers use native-style search fields, icons, checkmarks,
  readable descriptions, and system typography, including nested folder picking.
- Configuration uses the existing creation controller and choice navigation.
  Remote machine checks, worktree errors, launch receipts, and installation
  recovery retain their existing behavior. Task text survives configuration
  changes and narrow layouts.
- Cmd-P uses a rounded, compact palette, a native-sized search editor, and
  visible All / Machines / Projects / Models / Store / Commands filters.
  Filters edit the existing searchable prefixes; typing prefixes still works.
  Sessions show their context in the second line. A visible preview toggle
  keeps session history and resource management available, with their existing
  keyboard controls and safety checks. Tab traverses the toolbar, segmented
  scopes, and preview actions; Up/Down navigates results. Escape returns from
  management controls to search before dismissing the dialog.
- System UI typography is used for controls and task text; paths, branches,
  shortcut hints, workspace bars, and terminal content retain monospace.
- Dialog controls use compact rounded rectangles with a subtle rim and an
  explicit focus ring. The default action carries its live shortcut hint.
  Icon-only toolbar controls and navigation links retain their roles.

Review creation and search with keyboard, mouse, input composition, long text,
light/dark palettes, narrow windows, and unavailable resources. Use synthetic
fixtures for saved previews; never commit live account screenshots.

Validation of the compact launch iteration on 2026-09-29,
against the experiment baseline `a26237c9`:

- The full desktop unit/widget suite passed: **4,471 passed, 12 skipped**.
  The native macOS fixture passed all **19 journeys**. Static analysis,
  formatting, and the normal macOS debug build passed.
- The current-source full-suite trace covers **1,973/1,973 changed executable lines**.
  The complete creation form/controller cover **3,645/3,645 lines**; the
  resource-picker gate covers **1,265/1,265 lines**. These are executable-line
  measurements, not a claim of complete branch coverage or every possible
  interaction.
- Independent AI developer reviews exercised creation, nested cancellation,
  mouse/keyboard focus, preview actions, unavailable resources, narrow windows,
  enlarged text, legacy presentation, and full-tab recovery. Findings fixed
  during review include hidden keyboard-selected scopes, stale preview action
  ownership, first-frame action focus, a moving search editor, disabled-Start
  keyboard recovery, late preference repainting, and draft preference ownership.
- The native app was visually reviewed for composer typography, chooser
  presentation, draft preservation, search, and previews. Launch submission
  uses fake daemons in tests, and the normal app was rebuilt after running the
  native fixture. The review did not create real agent sessions.

The native fixture injects Flutter keyboard events into the macOS engine.
Physical AppKit IME behavior and VoiceOver were not separately verified.
Linux behavior is covered by widget tests; a Linux native build was not run.
See [the validation record](friendly-desktop-validation.md) for commands and
the interaction suites.
