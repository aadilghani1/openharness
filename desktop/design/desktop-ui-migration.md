# Desktop UI migration and review

Objective: a coherent, welcoming Mac-style application around unchanged terminal
panes. This tracks the complete requested scope, not only the initial composer.
The [design system](desktop-design-system.md) is normative; historical screenshots
and tests do not override it. Remain on `experiment/friendly-desktop`, unmerged.

## Surface inventory

| Surface | Current evidence / work remaining |
| --- | --- |
| Shared type, controls, fields, menus | System typography, semantic colors, and stable button focus boundaries implemented; small icon controls and Increase Contrast overrides remain |
| Welcome / New Tab | Shared 680-point composer and recent-session context implemented; inspected in rebuilt app |
| Cmd-N and child choosers | Purpose icons, approval explanations, visible focus, and coding-agent-first order implemented; shared controller retained |
| Cmd-P and resource previews | Modern frame and Harnesses scope implemented; inspected search, scopes, and dismissal in rebuilt app |
| Rename and takeover | Desktop prompt anatomy implemented; safety/IME and focus-return tests pass |
| Stop, delete, restart, fork | Desktop confirmations implemented; long errors scroll independently of fixed actions; synthetic light/dark/narrow renders inspected |
| Sharing | Access/people/options dialog migrated and rendered; embedded comments and observer sidebar remain |
| Add Phone | Desktop QR/device layout implemented; pairing lifecycle tests and light/dark enlarged-text renders pass |
| Machine recovery/linking | Desktop linking/password layouts implemented; bounded selectable errors, fixed actions, and 32-point reveal controls tested/rendered |
| Notifications | Desktop popup, two-line rows, glyphs, and empty/error states implemented; unchanged event rules tested; live empty popup inspected |
| Branches / pull requests | Desktop lists implemented; colored icons, readable status words, honest load failures, Page Up/Down tested and rendered |
| Settings / customization | Graphical settings audited; Customize Status, small icon controls, and robot-error text color remain |
| Store | Existing graphical discovery/detail/launch routes audited; remaining ordinary monospace labels and small controls need cleanup |
| Sign-in / setup / boot | Boot/preflight/setup migrated and rendered; installer lifecycle tests pass; sign-in already graphical and scrollable |
| Shortcuts / keyboard practice | Desktop browsing/practice layout implemented and rendered; remapping and scratch terminal retained |
| Teams / ancillary dialogs | Live Swarm conversation remains terminal-styled; generic team-creation presenter currently has no production caller |
| Layout / move / pane menus | Compact Find options and shared menu shell remain; normal footer model menu already uses modern resource picker |
| Native tabs / footer / menus | Preserve familiar placement and compact tabs; audit font, sizing, state, hover and AX consistency |
| Linux / browser presentation | Shared behavior remains; verify responsive widgets and identify platform-only gaps explicitly |

Legacy/test-only paths (including the old NewAgentDialog entry when
`newHarnessOpensInBox` is disabled) must be labeled as such in reviews. Do not
count an unused widget migration as completion of a visible user journey.

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

Completion requires every reachable non-pane surface above to follow the design
system, verified core behavior unchanged, and concrete evidence for both visual
quality and interaction. Until then keep the overall goal active.
