# Friendly desktop experiment

Requested on 2026-09-28. Local review branch: `experiment/friendly-desktop`.
This experiment follows the user's new direction for the UI around the terminal,
superseding the flat, fixed-cell dialog presentation for the surfaces below.
It is not included in Desktop 1.2.27 and must not be merged without review.

- Cmd-N opens a centered composer. Project, branch, and machine are visible
  above the task; agent and model sit inside it. Approvals and an explicit
  worktree toggle remain visible underneath. Profile lives in Options.
- A task is optional. Enter inserts a newline; Cmd-Enter or Start launches.
  The shortcut is remappable. Opening a chooser does not submit the task.
  Escape backs out of a chooser before closing the composer.
- Configuration uses the existing creation controller and choice navigation.
  Remote machine checks, worktree errors, launch receipts, and installation
  recovery retain their existing behavior. Task text survives configuration
  changes and narrow layouts.
- Cmd-P uses a rounded, compact palette, a native-sized search editor, and
  visible All / Projects / Machines / Models / Store / Commands filters.
  Filters edit the existing searchable prefixes; typing prefixes still works.
  Sessions show their context in the second line. A visible preview toggle
  keeps session history and resource management available, with their existing
  keyboard controls and safety checks.
- System UI typography is used for controls and task text; paths, branches,
  shortcut hints, workspace bars, and terminal content retain monospace.
- Shared FilledButton, OutlinedButton, TextButton, and named workspace actions
  use quiet rounded capsules with a subtle rim, based on the Harness Store
  button. Icon-only toolbar controls and navigation links retain their roles.

Review creation and search with keyboard, mouse, input composition, long text,
light/dark palettes, narrow windows, and unavailable resources. Use synthetic
fixtures for saved previews; never commit live account screenshots.

Validation on the released `805d3deb` base: 306 targeted tests across creation,
search, keyboard dispatch, accessibility, and shared button behavior passed.
The final search presentation adjustment also passed its 52-test regression
run. `flutter analyze --no-pub lib test` and the macOS debug build passed.
The native app was reviewed for composer typography, draft preservation,
search results, and previews; launch submission was verified with a fake
daemon so review did not create real agent sessions.
