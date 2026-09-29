# Desktop UI migration and review

Objective: a coherent, welcoming Mac-style application around unchanged terminal
panes. This tracks the complete requested scope, not only the initial composer.
The [design system](desktop-design-system.md) is normative; historical screenshots
and tests do not override it. Remain on `experiment/friendly-desktop`, unmerged.

## Surface inventory

| Surface | Current evidence / work remaining |
| --- | --- |
| Shared type, controls, fields, menus | System typography, semantic colors, 32-point icon controls, stable focus boundaries, Increase Contrast and platform text scaling implemented; terminal scaling stays independent |
| Welcome / New Tab | Shared 680-point composer and recent-session context implemented; inspected in rebuilt app |
| Cmd-N and child choosers | Purpose icons, approval explanations, visible focus, and coding-agent-first order implemented; shared controller retained |
| Cmd-P and resource previews | Modern frame and Harnesses scope implemented; inspected search, scopes, and dismissal in rebuilt app |
| Rename and takeover | Desktop prompt anatomy implemented; safety/IME and focus-return tests pass |
| Stop, delete, restart, fork | Desktop confirmations implemented; long errors scroll independently of fixed actions; synthetic light/dark/narrow renders inspected |
| Sharing | Access/people/options, comments, observer sidebar, and viewer access/error states use desktop surfaces; existing sharing and authentication rules retained |
| Add Phone | Desktop QR/device layout implemented; pairing lifecycle tests and light/dark enlarged-text renders pass |
| Machine recovery/linking | Desktop linking/password layouts implemented; bounded selectable errors, fixed actions, and 32-point reveal controls tested/rendered |
| Notifications | Desktop popup, two-line rows, glyphs, and empty/error states implemented; unchanged event rules tested; live empty popup inspected |
| Branches / pull requests | Desktop lists implemented; colored icons, readable status words, honest load failures, Page Up/Down tested and rendered |
| Settings / customization | Desktop status customization, natural-height controls, error contrast, keyboard focus and passive native footer preview implemented; actual status previews preserve the selected renderer |
| Store | Existing graphical discovery/detail/launch routes retained; ordinary labels, search and counts use system typography; desktop and narrow/enlarged previews inspected |
| Sign-in / setup / boot | Boot/preflight/setup migrated and rendered; installer lifecycle tests pass; sign-in already graphical and scrollable |
| Shortcuts / keyboard practice | Desktop browsing/practice layout implemented and rendered; remapping and scratch terminal retained |
| Teams / ancillary dialogs | Swarm conversation, questions, member controls and Quick Start use desktop typography and controls; polling, answers, learning steps and storage unchanged |
| Layout / move / pane menus | Graphical layout previews, scrollable move list, shared model menu and compact Find options implemented; keyboard navigation and terminal Find sizing retained |
| Daemon panels | Companion settings, pairing, proposal controls and consent use desktop controls; artwork, reveal frames, state and approval gates retained |
| Native tabs / footer / menus | Familiar compact tabs and footer preserved; modals hide native footer/AX actions, with an explicitly passive preview for status customization |
| Linux / browser presentation | Shared light/dark, narrow and enlarged-text fixtures cover responsive behavior; physical Linux/browser platform validation is not claimed |

Legacy/test-only paths (including the old NewAgentDialog entry when
`newHarnessOpensInBox` is disabled) are excluded from the visible migration.
The standalone MachinesManager, old machine-link dialog, and generic
team-creation presenter have no production caller in this tree. They are not
counted as completed user journeys. Shared controls still serve their tests.

## AI review panel

The user requested independent AI perspectives. These are design and engineering
reviews, not claims of human credentials or Apple endorsement.

- Mac design research: checked Apple HIG/WWDC and official excellent-app
  references; recommends hierarchy, visible focus, consistent anatomy, semantic
  light/dark colors, and restrained optional motion. See the research record.
- Product/accessibility review: found value-only composer controls, missing
  approval explanations, misleading All scope, weak focus, and ambiguous recents.
- Frontend review: traced live paths, identified TerminalBox and bespoke
  terminal-cell forms, and found that AppMenuItem ignored its textStyle input.

Address findings in shared components where appropriate. Each surface still
needs rendered and runtime review after its migration. A code review or one
passing screenshot does not establish whole-app completion.

## Verification ledger

Baseline `7782202b`: 4,522 desktop tests passed, 12 skipped; 996 native titlebar
checks; full form/controller executable-line coverage; local debug build opened.
These results precede the broad redesign and must not be attributed to later edits.

### Broad desktop surfaces checkpoint, 2026-09-29

- Full desktop suite: **4,560 passed, 16 skipped**, with fresh line and branch
  coverage. The complete creation controller/form line gate passed.
- Static analysis covers `lib`, `test`, and `integration_test`. The macOS debug
  build and **996 native titlebar checks** passed. The native drag fixture needs
  access to the macOS pasteboard service; its sandboxed run failed the drag
  assertion, then the authorized native run passed without code changes.
- AI review fixes include Tab traversal past prompt wrappers, scrollable and
  selectable long errors with actions kept visible, clear composer-control
  purposes, honest history load failures, readable status words, and paging
  the active PR/branch list.
- Real-font synthetic renders cover light/dark confirmations, sharing, history,
  notifications, setup, shortcuts, and connection forms. Connection forms were
  checked at 720×560 with 1×/2× text and 480×360 with 1.6× text; confirmation
  error layouts include 480×360 at 1.7×.
- The rebuilt app was reopened. Live review checked the New Tab composer,
  recent context, coding-agent-first chooser, search scopes/dismissal, native
  footer coverage, and notification empty state. No real agent was launched.
- Remaining work is explicit in the inventory above. Physical IME and VoiceOver
  have not been verified; this checkpoint does not include a Linux build or a
  repeat of the historical 19-journey native Flutter fixture.

For each new checkpoint record changed surfaces, relevant tests, actual renders,
native runtime checks, reviewer findings, fixes, and unresolved gaps. Test traces
must correspond to the final source. Native keyboard injection does not prove
physical AppKit IME or VoiceOver interaction. No live user data in saved previews.

### Complete desktop presentation pass, 2026-09-29

- Full desktop suite: **4,628 passed, 16 skipped**, with fresh line and branch
  coverage. New Harness covers **3,813/3,813 executable lines** across its
  complete controller and form. This is not a whole-app coverage claim.
- Static analysis of `lib`, `test`, and `integration_test` is clean. The normal
  macOS debug build succeeds. **999 native titlebar checks** pass, including
  passive footer preview containment. The macOS Flutter integration fixture
  passes **19 creation/search journeys**. Its test app is replaced by the normal
  review build afterward.
- Independent frontend and product review found and resolved a scrolling-menu
  focus loop, Find scaling inheritance, observer-header overflow, Add project's
  intrinsic-layout failure, small-window conversation space, stale focus styles,
  and Quick Start's remaining terminal-style app controls. The last guide-strip
  fill adjustment passed its **24-test** guidance/practice rerun.
- Synthetic real-font renders were inspected for the remaining menus, Store,
  layout/move palettes, comments, Swarm conversation, Quick Start, observer
  header, status customization, and companion panels. Cases include both
  appearances, 360–390-point widths, up to 200% text, Increase Contrast, and
  Reduce Motion. Rendering fixtures preserve real approval and stale-response
  guards while substituting data and services.
- Live macOS review checked the creation form and coding-agent-first chooser,
  nested dismissal, full footer coverage, search scope switching, settings,
  status customization's visible but noninteractive footer preview, Store, and
  Quick Start. Existing terminals and tabs restored. No agent was launched,
  sharing changed, account authorized, or companion approval accepted for review.
- The migrated reachable surfaces now follow the shared desktop system.
  Terminal rendering, status artwork, core controllers, and launch/notification
  semantics retain their existing behavior. Physical AppKit IME, VoiceOver,
  and native Linux/browser execution remain separate validation limits; widget
  semantics and injected-key tests do not establish those results.

The experimental branch remains unmerged for the user's visual review.
