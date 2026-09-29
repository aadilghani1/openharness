# Friendly desktop experiment

Requested on 2026-09-28. Local review branch: `experiment/friendly-desktop`.
This experiment follows the user's new direction for the UI around the terminal,
superseding the flat, fixed-cell dialog presentation for the surfaces below.
It is not included in Desktop 1.2.27 and must not be merged without review.

- Cmd-N and Cmd-P are floating dialogs with the same frame, shadow, backdrop,
  typography, and focus treatment. They remain visibly distinct from the workspace.
- Cmd-N opens a centered composer. Machine, project, and branch are visible
  above the task; agent and model sit inside it. Approvals and an explicit
  worktree toggle remain visible underneath. Profile lives in Options.
- A task is optional. Enter inserts a newline; Cmd-Enter or Start launches.
  The shortcut is remappable. Opening a chooser does not submit the task.
  Escape backs out one level before closing the composer. Clicking outside an
  open chooser closes only that chooser; the next outside click closes the dialog.
  A choice or cancellation returns focus to the originating control. Tab and
  Shift-Tab dismiss a chooser without applying a value and continue form traversal.
- Focus stays inside the active dialog. The task receives initial focus; Tab
  reaches every setting and action. Arrow keys navigate searchable option lists.
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

Validation on 2026-09-29, against the experiment baseline `a26237c9`:

- The full desktop unit/widget suite passed: **4,424 passed, 12 skipped**.
  The native macOS fixture passed all **12 journeys**. Static analysis,
  formatting, and the normal macOS debug build passed.
- Current-source test traces cover **1,809/1,809 changed executable lines**.
  The complete creation form/controller cover **3,541/3,541 lines**; the
  resource-picker gate covers **1,265/1,265 lines**. These are executable-line
  measurements, not a claim of complete branch coverage or every possible
  interaction.
- Independent AI developer reviews exercised creation, nested cancellation,
  mouse/keyboard focus, preview actions, unavailable resources, narrow windows,
  enlarged text, legacy presentation, and full-tab recovery. Findings fixed
  during review include hidden keyboard-selected scopes, stale preview action
  ownership, first-frame action focus, and a moving search editor.
- The native app was visually reviewed for composer typography, chooser
  presentation, draft preservation, search, and previews. Launch submission
  uses fake daemons in tests, and the normal app was rebuilt after running the
  native fixture. The review did not create real agent sessions.

The native fixture injects Flutter keyboard events into the macOS engine.
Physical AppKit IME behavior and VoiceOver were not separately verified.
Linux behavior is covered by widget tests; a Linux native build was not run.
See [the validation record](friendly-desktop-validation.md) for commands and
the interaction suites.
