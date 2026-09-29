# Friendly desktop experiment

Requested on 2026-09-28. Local review branch: `experiment/friendly-desktop`.
This experiment follows the user's new direction for the UI around the terminal,
superseding the flat, fixed-cell dialog presentation for the surfaces below.
It is not included in Desktop 1.2.27 and must not be merged without review.

- Cmd-N and Cmd-P are floating dialogs with the same frame, shadow, backdrop,
  typography, and focus treatment. The dark backdrop suppresses busy terminal
  content behind them. Keyboard focus uses a quiet fill change without thick
  outlines or changing control dimensions.
- Cmd-N opens a centered, 860-point composer. Agent, Machine, and Repo are
  compact capsule selectors across the top, with the agent's existing brand
  mark and Close at the right. There is
  no visible heading. The always-visible message editor says “What’s next?”;
  New harness is inside its lower-right corner and works without a message.
  Direct Model, Approvals, and Codex Profile controls sit below the composer
  on the left; Worktree on/off and Branch sit on the right, in that order.
  These are small text-only controls. There is no Options disclosure. The Git
  controls stay together on one baseline, moving together below the other
  settings in narrow windows or at larger text sizes. Long branch names
  truncate in the closed control; its tooltip and accessibility label retain
  the complete branch and worktree plan.
- The last explicit approval choice is remembered per agent, including Full
  access when selected. Worktree choices are remembered per machine/project.
  Projects without a saved choice keep Worktree on; agents without a saved
  approval mode keep Auto-approve. Drafts take precedence over these defaults.
- Enter on the initially focused New harness launches without an extra step.
  Nonempty restored messages receive editor focus. The task shortcut focuses
  the editor; the former Options shortcut opens Model directly (Repo for
  Terminal). Terminal keeps the editor read-only and outside keyboard
  traversal while preserving a carried message.
- In the task editor, Enter inserts a newline; Cmd-Enter or New harness launches.
  The shortcut is remappable. Opening a chooser does not submit the task.
  Escape backs out one level before closing the composer. Clicking outside an
  open chooser closes only that chooser; the next outside click closes the dialog.
  A choice or cancellation returns focus to the originating control. Tab and
  Shift-Tab dismiss a chooser without applying a value and continue form traversal.
- Focus stays inside the active dialog. New harness receives initial focus for
  empty drafts; restored tasks receive editor focus. Tab from New harness wraps
  to Agent, then Machine, Repo, message, Model, Approvals, Profile, Worktree,
  Branch, and Close. Shift-Tab reaches Close. Tab reaches each visible control without
  stopping on hidden fields. Arrow keys navigate searchable option lists.
  Existing command identities and shortcut remapping remain available.
- Dismissing Cmd-N or switching to Cmd-P preserves its unsent draft in the same
  machine/project/source-pane context. Another source pane gets its own defaults.
  Cmd-N resumes that draft even after typing a search query; a fresh composer
  uses the query when there is no draft. Explicit create-from-search and Store
  task actions keep their requested text and existing ownership rules.
  Restoration uses the current destination tab and never duplicates a pending
  launch receipt.
- New, Open, and Clone use the selected machine directly. Open Folder invokes
  the native local folder dialog or remote folder browser in one step. Accepting
  returns to the composer; cancelling returns to the Repo list. New and Clone
  prompts offer Change machine. Choosers begin at a focused search field and
  size to their contents, with no visible title, close button, or key legend.
  A back control appears inside search only for nested prompts. Machine rows
  keep names, the current checkmark, and unavailable status; redundant remote
  captions are omitted. Repo paths remain available for disambiguation.
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
- System UI typography is used for controls, selected branches, and task text; paths,
  shortcut hints, workspace bars, and terminal content retain monospace.
- Header selectors use compact capsules; composer settings use quiet text
  controls with a focused fill. The default action carries its live shortcut hint.
  Icon-only toolbar controls and navigation links retain their roles.

Review creation and search with keyboard, mouse, input composition, long text,
light/dark palettes, narrow windows, and unavailable resources. Use synthetic
fixtures for saved previews; never commit live account screenshots.

Validation of the minimal composer iteration on 2026-09-29,
against the experiment baseline `a26237c9`:

- The full desktop unit/widget suite passed: **4,500 passed, 12 skipped**.
  The native macOS fixture passed all **19 journeys**, once each across four
  sequential native processes. App/test analysis and formatting passed.
  The normal macOS debug app was rebuilt after the fixture and opened for review.
- The fresh full-suite trace covers **1,986/1,986 changed executable lines**.
  The complete creation form/controller cover **3,627/3,627 lines**; the
  resource-picker gate covers **1,265/1,265 lines**. These are executable-line
  measurements, not a claim of complete branch coverage or every possible
  interaction. No coverage exclusions or stale traces were used.
- Independent AI developer reviews exercised creation, nested cancellation,
  mouse/keyboard focus, preview actions, unavailable resources, narrow windows,
  enlarged text, legacy presentation, and full-tab recovery. The final pass
  added 26 layout/interaction journeys and a four-round mixed-input sequence.
  It fixed competing focus restoration after folder acceptance, a stale Return
  hint, clipped actions in short folder menus, and search text replacing an
  interrupted draft. Synthetic renders were visually inspected in both themes
  with real fonts and shadows.
- A long native test process encountered background frame throttling in this
  environment. All 19 independent journeys passed in four fresh-process shards
  with unchanged assertions and timeouts. No Flutter lifecycle or frame
  completion was overridden. Launch submission uses fake daemons in tests;
  no real agent sessions were created for validation.

The native fixture injects Flutter keyboard events into the macOS engine.
Physical AppKit IME behavior and VoiceOver were not separately verified.
Linux behavior is covered by widget tests; a Linux native build was not run.
See [the validation record](friendly-desktop-validation.md) for commands and
the interaction suites.
