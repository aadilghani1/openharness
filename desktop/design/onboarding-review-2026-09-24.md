# Onboarding review · 24 September 2026

Historical proposal. [Open the local interactive concept](review/developer-onboarding.html)
or [all local reviews](review/index.html). The current [workspace design](terminal-workspace.md)
and [dialog rules](terminal-dialogs.md) take precedence for implementation. Findings and
test counts below describe the September 24 review.

Audience: **a developer bringing an existing project**, confirmed in this review. Scope: first launch, first useful session, returning to work, and discovering additional features. Reviewed against `f867ff23`, with the existing local CmdN, launch feedback, toolbar, and pane-closing changes preserved.

## Recommendation

Make the first promise concrete: **open your project, use your coding agent, get something useful done**. Then reveal one relevant capability at a time through real work. A second computer and a local model are optional capabilities; neither should determine whether someone has finished getting started.

Keep the terminal typography, charcoal surfaces, thin borders, keyboard support, and quiet workspace. The main problem is the journey and its defaults, not the visual treatment.

## What improved recently

- The new welcome has clickable shortcuts, persisted progress, and native toolbar discovery indicators (`c9993f3f`, #299).
- Machines distinguishes setting up another computer from receiving existing work, with connection and offline recovery (`02453b8a`, #292).
- New Harness brings the catalog into one form and installs missing harnesses with real installation stages (`f867ff23`, #308).
- New/Open entry is more consistent, model selection is available in the terminal form, and drafts survive adjacent flows (`0c177a85`, #282; `9121ca28`, #300).
- The local changes add visible ASCII launch feedback and fix lingering toolbar selection and empty tabs.

These are useful foundations. Keep them while changing what the first session asks the developer to do.

## Findings, in priority order

### 1. The default destination misses the existing-project audience

The welcome says “start your first harness”; it does not offer “Open your project.” On an empty workspace, the creation entry enables `autoProject`, generating a scratch folder. The developer must discover and change Project to reach their own repository. The project menu also lists Clone Repository before Open Folder and puts recents after those actions.

Evidence: [welcome actions](../lib/widgets/workspace_welcome.dart#L30), [empty-workspace launch](../lib/screens/swarm_screen.dart#L1537), [project construction](../lib/state/new_harness.dart#L443), [project menu](../lib/state/new_harness.dart#L1585).

**Change:** first welcome action is **Open a project**, opening the existing folder chooser through the same New Harness controller. Offer Clone Repository secondarily. Keep New Project available. Reuse an explicitly selected or recent project; do not silently substitute a scratch folder on this path. Preserve the normal CmdN flow for experienced users and Store examples.

### 2. Getting started finishes too early and too late at the same time

A session accepting terminal input marks the first harness milestone complete, before a first task or response. But the whole welcome remains onboarding until *all three* milestones—Harnesses, Machines, Models—are complete. Dismissing Machines and Models does not finish it. Local-model availability affects discovery dots, but not the three fixed welcome rows.

Evidence: [milestone observation](../lib/screens/swarm_screen.dart#L596), [completion and eligibility](../lib/state/workspace_onboarding.dart#L27), [welcome rendering](../lib/widgets/workspace_welcome.dart#L82).

Reproduced in diagnostic widget renders:

- After using a harness and dismissing both optional features, `next == null`, `complete == false`, and both unfinished rows remain on a new tab.
- With no eligible local model, the welcome still asks the person to use one.
- On a receiving computer, state correctly recommends Machines, but the welcome still invites a first harness and omits Open Harness.

**Change:** separate first-session activation from optional feature discovery. Track launch readiness, first submitted task, and first successfully completed turn separately. Completed turn is a measurable proxy; whether the result was useful requires user observation. Do not inspect terminal text to guess success. Engines without reliable turn events must still allow a calm returning workspace. Dismissal and ineligibility remove a discovery invitation without falsely marking the feature used.

### 3. Existing agent readiness should be the shortest path

New Harness chooses an explicit or remembered engine, then the first compatible engine; that fallback does not select based on installed, authenticated readiness. The subscription picker displays account status, but the default subscription option remains selectable. Installation is now well explained; provider authentication still needs a first-run walkthrough on a clean machine.

Evidence: [engine default](../lib/state/new_harness.dart#L618), [subscription option](../lib/state/new_harness.dart#L967).

**Change:** respect an explicit choice first, then a remembered compatible choice. For a first-time developer with no preference, recommend an already usable agent when readiness is known. Keep other agents available. Distinguish “installed,” “sign-in needed,” and “checking”; never infer subscription access from installation alone. On authentication handoff or retry, retain project, branch, and launch draft. If readiness cannot be checked reliably, explain what will happen when starting instead of blocking forever.

Show a concise launch summary: project, agent/account, and where work will happen. Existing Git worktree behavior must be explicit—new worktree versus the selected folder, and its branch. Do not change repository or permission defaults as an incidental onboarding change.

### 4. Feature discovery has no coherent continuation

The main journey only knows Harnesses, Machines, and Models. The useful pane/zoom/command lessons live in a separate `WorkspaceLearning` state and optional keyboard tour. The production welcome does not expose that tour. The Store is present in the toolbar, but the everyday welcome only promotes it after the three onboarding milestones are all completed.

Evidence: [onboarding enum](../lib/state/workspace_onboarding.dart#L8), [keyboard learning](../lib/state/workspace_learning.dart#L8), [everyday welcome](../lib/widgets/workspace_welcome.dart#L50), [quick-start command](../lib/shortcuts/keymap_commands.dart#L426).

**Change:** one discovery policy, contextual invitations, and a permanent “Explore Harness” destination. Existing features stay available from day one. Learning them should feel like gaining another useful tool, with no mandatory tour or all-features completion score.

### 5. Models still requires a manual handoff

The Models introduction explicitly says to choose a model, then select it again in a harness's picker. This is the same boundary that caused confusion in the reported missing-model case; that incident also involved an old CLI capability. A successful model start is not yet a completed coding workflow.

Evidence: [Models introduction](../lib/models/models_panel.dart#L159), [launch capability filter](../lib/state/new_harness.dart#L990).

**Change:** offer **Use in this project** after a compatible model is ready, returning to the preserved launch draft with that exact model selected. If a CLI update is required, place the reason and recovery action there and retain context. Show memory/download requirements before starting a download. Never recommend a model solely because it appears in the catalog.

### 6. Setup copy and validation still describe mandatory sign-in

Environment setup says “then sign in” and “Continue to Harness sign-in.” Desktop bootstrap supports local use without a Harness account. This confuses the Harness account with the coding agent's provider account. One setup test still expects the old sign-in destination and currently fails.

Evidence: [setup copy](../lib/widgets/environment_setup_screen.dart#L209), [ready copy](../lib/widgets/environment_setup_screen.dart#L306), [local-first bootstrap](../lib/state/app_state.dart#L2643), [test expectation](../test/environment_setup_screen_test.dart#L356).

**Change:** “Prepare this computer” → “Open your project.” Introduce Harness sign-in when the person asks for account-dependent functionality. Show provider authentication in the agent context. Update the destination test to exercise the real local workspace.

## Proposed first session

1. **Prepare this computer, if needed.** Explain the missing tools, install after the existing explicit action, show truthful stages, and provide recovery. Already prepared machines go straight to the workspace.
2. **Open your project.** One prominent action, plus Clone Repository and a less prominent New Project route. No role survey. On a computer with existing remote work, prioritize opening that work instead.
3. **Confirm a sensible launch.** Project first, usable agent next, concise readiness and branch/worktree summary. Model, machine, and advanced settings remain accessible. Keep the existing form, draft preservation, and launch progress.
4. **Do the first useful task.** The agent's normal terminal/composer remains primary. Offer optional starters such as “Explain this codebase” or “Find where a feature is implemented.” Selecting one fills a draft; the developer reviews and submits it. Do not require a practice project or automatically run a task.
5. **Return to real work.** Once work exists, the empty workspace offers recent/available harnesses and New Harness. It does not repeat “your first harness” or demand another computer or model.

The companion interactive concept illustrates this sequence with example project content. It is a proposal, not a rendering of shipped behavior. Its simulated readiness and replies do not make external calls.

## How further capabilities become useful

| Context | Invitation | What counts as using it |
| --- | --- | --- |
| Returns to an empty workspace with existing work | “Pick up where you left off” → Open Harness | Existing session opened; handle stopped/offline sessions explicitly |
| Starts a second task while one is active | “Work side by side” → add a pane, explain isolation if needed | Second real task is running in another pane |
| Has two panes and needs more room | “Focus this pane” → zoom shortcut | Pane zoomed, with a visible way back |
| Repeats workspace actions | “Find any command” → command search or optional keyboard tour | Command used; tour is never required |
| Opens Models or explicitly wants local execution | “Run this task locally” → compatible model → Use in this project | Selected model actually used by an agent |
| Asks to work elsewhere, or opens a second computer | “Continue on another computer” → connect/open existing work | Existing remote session opened |
| Deliberately explores another workflow | Relevant Store example with a clear outcome and requirements | Harness launched and a task completed |

At most one contextual invitation at a time, at a natural pause or empty state. No overlay while typing or while an agent is producing output. “Not now” suppresses that invitation for the current context; “Don't show again” persists. Already used features do not get introductory prompts. The permanent exploration destination remains available.

## Implementation order and acceptance criteria

**First: correct the journey.** Separate activation from discovery, respect dismissal/eligibility in the welcome, fix setup copy, and surface Open Harness when work already exists. Verify single-laptop use, no eligible models, skipped features, receiving computers, guest-to-account transition, and restored preferences. Preserve local experience when signing into the same person's account, without leaking another account's progress.

**Second: shorten the project-to-task path.** Route Open a project into the existing controller, add trustworthy readiness, preserve recovery state, and add optional first-task drafts. Verify a prepared developer machine, one missing agent, provider sign-in, offline/slow setup, failed installation and retry, dirty/existing repositories, and clear worktree placement. Keep keyboard and click behavior equivalent, including Shift+Enter and repeated-submit protection.

**Third: build continuing discovery.** Reuse real pane, model, machine, and Store actions under one eligibility/dismissal policy. Add the model-to-project handoff and a permanent learning destination. Verify every invitation leads to the relevant action with context retained, including after restart and unavailable services.

## Evidence and measurement

This review used source inspection, real-font Flutter renders, the recent Git changes, and widget tests. It did not use production funnel data or observe new users; the proposed retention benefits are hypotheses to validate.

- Existing onboarding/setup/learning selection: **42 passed, 1 failed**. The failure is the setup test expecting “Sign-in reached.”
- Three additional temporary diagnostic cases passed, reproducing skipped-feature, unavailable-model, and receiving-computer mismatches. The diagnostic file was removed after the review; it asserted current behavior rather than prescribing that behavior permanently.
- Screenshots in `review/onboarding-2026-09-24/` preserve the welcome and two reproduced mismatch states.
- The interactive concept was checked in Chrome: project entry, ASCII starting state, a starter filling an unsent draft, simulated response, close/reopen, second-task context, and the exploration destination. Layouts were inspected at 736px and 320px viewport widths; JavaScript syntax and evidence links were checked. Provider sign-in and installation in the concept are illustrative, not live integrations.

Existing analytics already measures app opens, provisioning, creation entry, agent creation, and a first message clocked from sign-in or launch. Add the missing project/first-session sequence: entry → project selected → readiness resolved → launch ready → first task → first successful turn → existing work reopened. Measure median and slower-case time to the first completed task, recovery rates, and repeat project use. Track discovery eligibility, exposure, dismissal, action, and actual feature use, using short product codes. Keep prompts, output, repository paths, and machine names out of analytics.

Validate the proposal with developers who bring their own repositories: prepared agent, unprepared agent, provider sign-in needed, a fresh clone, and return after closing the final pane. Observe whether they can explain where work is happening, recover without re-entering context, and return to it unaided. Set numeric activation and retention targets after measuring the baseline; a perfect-looking walkthrough is not evidence of a successful onboarding.
