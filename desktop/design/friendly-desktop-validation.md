# Friendly desktop validation

The polished checkpoint `e888bda8` was validated on 2026-09-29 on
`experiment/friendly-desktop`, against `a26237c9`. This remains an unmerged
experiment for local review. The compact iteration below adds the team feedback.

## Polished checkpoint results

| Check | Result |
| --- | --- |
| Full desktop unit/widget suite | 4,424 passed; 12 skipped |
| Native macOS interaction fixture | 12 passed |
| Dart analysis | No issues |
| Formatting | 62 changed Dart files checked; no changes needed |
| Normal macOS debug build | Passed; opened for review |
| Changed executable-line coverage | 1,809 / 1,809 (100%) |
| Complete creation form and controller | 3,541 / 3,541 (100%) |
| Resource picker coverage gate | 1,265 / 1,265 (100%) |

Coverage combines real test traces from the final source. Modules edited after
the broad coverage run were replaced with fresh traces; obsolete line offsets
were not combined. No coverage exclusions were added. The measurements cover
executable lines, not every branch or possible input.

## Interaction review

The added suites exercise keyboard and mouse behavior through rendered widgets
with fake application state and daemon responses:

- `desktop_dialog_interaction_test.dart`: initial focus, traversal, custom
  shortcuts, composition ownership, nested cancellation, outside clicks, draft
  restoration, repeat submission, source-pane ownership, and dialog switching.
- `desktop_new_harness_edge_test.dart`: creation errors, configuration changes,
  terminal/task compatibility, and narrow layouts.
- `desktop_search_polish_test.dart` and `desktop_final_ux_test.dart`: search
  toolbar, scope selection, prefixes, focus, enlarged/narrow layouts, disposal,
  and repeated reopening. Keyboard-selected scopes stay visible after resizing.
- `desktop_search_edges_test.dart`: model availability, inventory updates,
  failed/repeated actions, API editing, preview ownership, polling, and recovery.
- `desktop_resource_forms_edge_test.dart`: native machine/API configuration,
  keyboard behavior, asynchronous responses, and errors.
- `desktop_remote_folder_picker_test.dart`: path entry, browsing, pagination,
  keyboard shortcuts, input composition, refresh, failure, retry, and disposal.
- `desktop_preview_compatibility_test.dart`: dated search matches, external
  conversation warnings, legacy keyboard activation, empty-result recovery,
  preview scrolling, Store history, and recovery from a full destination tab.

Independent AI developers reviewed synthetic user journeys and rendered
screens. Their findings led to fixes for hidden selected scopes, stale preview
callbacks, immediate action focus, clipping, and editor movement. Native visual
review checked the floating frames and shadows, typography, option lists,
search results, and previews. The finished normal app is left on Cmd-N.

## Reproduction

Run from `desktop/` with the repository's Flutter/Dart toolchain:

```sh
flutter test --no-pub --reporter expanded
dart analyze lib test integration_test/friendly_desktop_e2e_test.dart
flutter test --no-pub --coverage
node tool/check_new_harness_coverage.mjs coverage/lcov.info
node tool/check_resource_picker_coverage.mjs coverage/lcov.info
python3 tool/check_portability_coverage.py --base a26237c9 --lcov desktop/coverage/lcov.info
```

On macOS, run the isolated native fixture, then restore the normal review app:

```sh
FLUTTER_TEST=1 flutter test -d macos --no-pub --dart-define=HARNESS_TEST=true integration_test/friendly_desktop_e2e_test.dart --reporter expanded
flutter build macos --debug --no-pub --target lib/main.dart --dart-define=HARNESS_ANALYTICS_DISABLED=true
```

Native tests inject Flutter keys and use fake daemons. They do not establish
physical AppKit IME or VoiceOver behavior. Linux widget variants passed; no
Linux native build was performed. Live-account review remained read-only, and
live screenshots are not repository fixtures.

## Compact launch iteration

Final validation on 2026-09-29, against `a26237c9`:

| Check | Result |
| --- | --- |
| Full desktop unit/widget suite | 4,471 passed; 12 skipped |
| Native macOS interaction fixture | 19 passed |
| Dart analysis | No issues |
| Formatting | 12 changed Dart files checked |
| Normal macOS debug build | Passed; compact Cmd-N opened for review |
| Changed executable-line coverage | 1,973 / 1,973 (100%) |
| Complete creation form and controller | 3,645 / 3,645 (100%) |
| Resource picker coverage gate | 1,265 / 1,265 (100%) |

All three coverage gates passed using the single final full-suite trace from
the current source. No earlier traces or coverage exclusions were needed.
These are executable-line measurements, not exhaustive branch or input coverage.

The team review identified two needs: immediate keyboard launch and discoverable
controls. Empty-task Cmd-N now opens at 560 points wide with Start focused.
Machine is in the header; Project and Agent remain the main fields. Approvals
and Worktree stay directly accessible. Add task reveals the composer; Options
reveals Branch, Model, and Profile in the same dialog. Restored tasks remain
visible, and empty task editors can be collapsed.

The last explicit approval selection is saved per agent. Worktree is saved per
machine/project. The existing preference files are extended without changing
their paths or replacing agent/project recents. Unsupported stored approval
modes are ignored, storage failures retain the in-memory choice, and pending or
restored drafts keep their reviewed values. Automatic retry recovery does not
replace an explicit worktree preference.

Independent test drives added 23 compact interaction journeys and 24 preference
scenarios. They found and verified fixes for an invisible Tab stop, loss of
focus after a failed launch, disabled-Start keyboard recovery, late preference
repainting, and a draft whose resolved worktree choice was not snapshotted.
The macOS fixture now includes seven compact journeys alongside the existing
12 composer/search journeys; all 19 passed. The fixture uses fake app state and
daemons, including when Return submits a launch.

Synthetic visual review covered compact and expanded layouts, both themes,
600-point windows, and 160% text size. The normal app is rebuilt after the native
fixture, with the compact Cmd-N left open for review. Physical AppKit IME and
VoiceOver remain outside this validation.
