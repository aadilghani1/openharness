# Mobile: zero questions

September 26, 2026. A review of the phone app (1.0.0 build 45) and the plan to rebuild it around one
rule: **open the app and have no questions.**

## What a new person meets today

From a fresh install to the first agent, on the happy path, the phone requires:

1. **Sign in** — "Sign in with the email of your Autonomous account." Nothing says what Autonomous
   is, there is no sign-up, and the app never says it needs a computer. Switch to Mail for a 4-digit
   code.
2. **A notification prompt**, the instant sign-in ends, before anything has been shown.
3. **Machines** — every computer reads "Needs its password". Nothing says what password or where it
   is set (on the desktop: Machines ▸ Set password, which is not set by default). With no computer,
   "No machines yet" is a dead end: no button, no link, and the list never refreshes, so a computer
   set up afterwards does not appear until the app is relaunched.
4. **Link** — "This computer isn't linked to X yet. Enter the remote password…". Walk to the
   computer. Errors quote CLI commands (`harness start`, `harness remote-password set`); progress
   shows raw protocol names (`deriving_key`).
5. **New Harness** — a desktop form: machine, four project sources, branch, worktree, 14 engines,
   Codex profiles, five approval modes.
6. **A terminal**, with no way back to a list and no sign of which other agent needs you.

Prerequisites nobody is told about: Harness installed on a Mac or Linux computer, signed in with the
same email (not as a guest), running and awake, with a remote password set.

After that the app is **11 screens, 19 sheets and dialogs, ~120 controls, 13 gestures and ~30
concepts** (harness, agent, engine, machine, link, remote password, desk tab, worktree, approvals,
take control, Live/Attaching/Resyncing…, `>` `#` `@` `?` search modes, usage windows…). Most of it
is the desktop carried onto a phone. The one question a phone is for — *what needs me?* — has no
screen: the tab bar that counted waiting agents is hidden (`phone_shell.dart:28`), and the
terminal header's dot shows connection state, not "needs you".

## The target

A phone is a **remote for the agents on your computer**. It does three things:

1. Shows what needs you.
2. Lets you answer — voice first.
3. Starts a new one.

Everything else stays on the computer.

### First launch: one screen, one action

```
┌─────────────────────────────┐
│                             │
│   [ live camera viewfinder ]│
│                             │
│  Scan the code on your      │
│  computer                   │
│                             │
│  In Harness on your Mac,    │
│  click  Phone               │
│                             │
│  No Harness on your         │
│  computer yet?  Get it →    │
└─────────────────────────────┘
```

Scan → "Connected to your MacBook" → the inbox. No email, no code, no password, no machine list.
"Get it →" opens the share sheet with the download link, so it can be sent to the computer.

The computer side is one button: **Phone** in the desktop app (and a step in desktop onboarding)
shows a QR code. The same QR is a universal link: a camera that scans it without the app installed
lands on the App Store page.

### After: three screens

- **Inbox** (home). Every agent as a row, **needs you** on top, in words: *Needs you · Working ·
  Done*. One tap opens it. A mic button answers the top one.
- **Agent.** The agent's output, a big mic, a keyboard button. Approve/deny when it asks. That is
  the whole control surface; `esc`/`tab`/arrows only appear while the agent is asking a question.
- **New.** One field: *"What should it do?"* Starts Claude Code in the folder you used last, with
  the current auto-approve default. "Other folder" is the only visible option.

Settings is a sheet off the inbox with four rows: your computers (with *Add a computer*, which scans
again), voice language, sign out, version.

**Words:** *computer* (never "machine"), the agent's own name for the thing working ("Claude Code ·
fix the login bug"), *needs you*. No "link", "remote password", "desk", "tab", "worktree",
"engine", "take control", or connection states unless something is actually broken.

## The plan

Three tracks. Track A can ship this week on its own; B and C together deliver the target.

### A. Stop the bleeding — phone only, days

Ship on the current app while B and C are built:

- A first screen that says what this is and what you need: *"Harness on your phone runs the agents
  on your computer. Get Harness on your Mac first."* with a share button for the link.
- Sign-in copy: *"Your email"* / *"We'll email you a code"* — drop "Autonomous account". Confirm what
  the account API does with an unknown email; if it does not create the account, say so in one line
  with the sign-up link.
- "No computers yet" gets a button (share the download link) and refreshes itself every few seconds
  while it is on screen.
- Link page: say where the password is — *"On your computer: Harness ▸ Machines ▸ Set password"* —
  autofocus the field, and replace raw stage names and CLI commands in errors with plain sentences.
- Ask for notifications the first time an agent finishes, not at sign-in.
- Fix copy written for the desktop: "Connecting this window to the local Harness service",
  "This computer isn't linked", "Your previous harness will reconnect".

### B. One scan instead of sign-in and a password — phone + desktop + backend

**B1. The QR links the computer (no protocol change).** The daemon still has the live-code pairing
the retired web client used (`e2e_pair_intent` → CPace, `cli/src/lib/e2ee/manager.ts:405`). The
desktop generates a high-entropy one-time code and shows it as a QR with the machine id and key
fingerprint. The phone scans, sends the pair intent; the desktop sees it pending and completes the
pairing with the same code. Work: a scanner on the phone and a port of the pairing context from
`cli/src/lib/e2ee/core.ts`; a QR and a "waiting for your phone" state on the desktop; optionally, let
the desktop arm the code so the daemon answers the intent without polling. **Removes the remote
password from the phone path entirely.** Estimate: 1–1.5 weeks.

Until B2 lands, the QR also carries the account email: the phone pre-fills it and sends the code
itself, so first run is *scan → type 4 digits (autofilled from Mail) → inbox*.

**B2. The QR signs the phone in too.** The backend issues no tokens of its own today — every route
checks an Autonomous token (`backend/src/routes/auth.ts:47`, `backend/src/lib/ssoAuth.ts`). Add a
phone handoff: the signed-in desktop asks the backend for a single-use code (2-minute TTL, modelled
on `backend/src/lib/deviceAuth.ts`), puts it in the QR, and the phone redeems it for a phone-scoped
token that the relay, the REST middleware and refresh all accept, revocable per phone from the
desktop. First run becomes *scan → inbox*. Estimate: 2 weeks plus a security review; it touches every
auth path.

A cheaper route to B2 exists if auth.autonomous.ai offers a token exchange or device grant — check
first.

**B3. One scan, every computer.** A desktop that already trusts other computers introduces the phone
to them, so a person with two Macs scans once. New protocol; after B1/B2, only if people ask.

### C. Rebuild the signed-in app — phone only, 2–3 weeks, parallel with B

- Build Inbox, Agent, New and the Settings sheet as above, on the existing state, WS, E2EE and
  terminal code (`lib/state`, `lib/ws`, `lib/e2ee`, `lib/terminal` stay).
- "Needs you" comes from the attention/unread signals the app already computes
  (`phone/agent_index.dart`), promoted to the home screen and the notification.
- Take control happens implicitly on the first keystroke or voice send; no band, no button.
- **Delete from the phone:** desk tabs and their panel/strip/sheets; the `>` `#` `@` `?` command
  palette and two of the three searches (keep one plain filter on the inbox once there are more than
  ~8 agents); branch/worktree/engine/profile/approval pickers and the remote folder browser; Usage
  and Stats; terminal font/size/colors and palette; Rename (long-press); machine administration
  beyond "Add a computer" and "Remove"; the hidden tab shell, `AgentsPage`, `MachineSwipeHost`, the
  Model sheet and hold-to-talk. Most of `lib/phone/` (94 files, ~25k lines) goes.

### Targets

| | Today | Target |
|---|---|---|
| Steps from install to inbox | sign in + code + find machine + password + link | **scan** |
| Things to type | email, code, password | nothing |
| Screens / sheets | 11 / 19 | 3 / 1 |
| Concepts named | ~30 | 3: computer, agent, needs you |
| Taps to answer the agent that needs you | 2–5, after finding it | 1 (tap the row, or the mic on the inbox) |

**The test:** hand the phone to someone who has Harness on their Mac and has never seen the app. They
reach a working agent and answer it without asking anything. Run it before each TestFlight build.

## Decisions for you

1. **B2 or B1+email.** B2 (scan signs you in) is the only way to zero typing; it is two weeks and a
   security review on every auth path. B1 with a pre-filled email ships sooner and costs 4 digits.
2. **Word for a session on the phone.** The app and desktop say "Harness" for one session ("New
   Harness", "Stop Harness"). On the phone this plan uses the agent's own name and *New* instead,
   so a new person meets one word — Harness — as the app. Keep, or align the phone with the desktop?
3. **No computer at all.** The backend has cloud machines (`self`/`managed` in
   `backend/src/services/MachineService.ts`) that the phone filters out. A "Try it in the cloud" path
   would answer "I don't have Harness on my computer" in-app; it is out of scope here and needs its
   own look.
4. **App Review.** Reviewers cannot scan a QR. A hidden demo account or a canned demo agent is
   needed for submission either way.
