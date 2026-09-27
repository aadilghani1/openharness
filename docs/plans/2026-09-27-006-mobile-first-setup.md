# Mobile first: set up every computer from the phone

September 27, 2026. The phone is where people find Harness. Someone installs the app, and it gets
Harness running on their computers and shows the sessions on them, with nothing to learn. This plan
builds on `2026-09-26-001-mobile-zero-questions.md`. That plan starts with the desktop app already
installed; this one starts with nothing on the computer.

## Today, from a fresh phone

The phone signs in with an email code, then shows four commands to run on the computer
(`mobile/lib/phone/welcome/connect_computer.dart:15-20`). A new person hits nine walls:

1. **Two sign-ins.** The phone uses an email code; the computer uses browser SSO (`harness login`,
   `cli/src/cli.ts:846-932`). Over SSH, you paste a callback URL back by hand.
2. **The phone can't hand anything over.** It can only email the steps to itself (`mailto:`). The
   installer rejects any argument: "no longer accepts a machine token" (`cli/scripts/install.sh:54-64`).
3. **Four commands, in two orders.** The phone says login → password → start; the installer prints
   login → start → password. `harness` isn't on PATH in the same shell (`install.sh:697-724`).
4. **A password to invent.** You type it twice on the computer, then again on the phone, once per
   computer. Wrong guesses lock you out for 5 minutes, doubling up to a day (`e2ee/store.ts:24-25`).
5. **Nothing survives a reboot.** There's no launch agent or service; the daemon runs only until the
   computer restarts, unless the desktop app is open (`cli.ts:6311-6319`).
6. **Linux needs sudo and apt**; other distros fail (`install.sh:386-401`).
7. **The computer shows up late.** The phone polls every 5 s and shows it offline until `start` has run.
8. **Your sessions aren't there.** Plain `claude` and `codex` sessions are invisible. Harness only
   sees tmux sessions it started (`cli/src/lib/tmuxAgentDiscovery.ts:129-148`).
9. **No second computer path.** Each computer repeats everything above.

## The flow

```
 PHONE                                        COMPUTER
 ─────                                        ────────
 1. Your email → 4-digit code (autofilled)
 2. "Set up your computer"
      ┌──────────────────────────────┐
      │ Run this on your computer:   │
      │                              │
      │ curl -fsSL harness.sh/K7QM-  │
      │ 4XPT-9D2W | sh               │
      │                              │
      │ [ Send to my Mac ]  [ Copy ] │   AirDrop, Messages, email, or read it off
      │                              │
      │ ⠋ Waiting for your computer… │
      └──────────────────────────────┘
                                              3. Paste. One command, no questions:
                                                 installs, signs in as you, starts,
                                                 stays on after a reboot, pairs with
                                                 your phone.
 4. "Connected to MacBook Pro"  ◄──────────────  (live, over the relay)
 5. Your sessions on it:
      fix-login        2m   claude
      docs-rewrite     1h   codex
      + New Harness
```

Three steps: sign in, run one command, pick a session. No password or second login, and nothing to
choose on the computer. **Add another computer** in Settings or Find runs the same card with a new
code.

## How one command does it all

The code in the command carries two things:

```
harness.sh/K7QM-4XPT-9D2W   =   K7QM-4XPT         + 9D2W…
                                sign-in part        pairing secret
                                (backend knows it)  (only the phone and the command know it)
```

**Sign-in part.** The phone, already signed in, asks the backend for a one-time setup code
(10-minute TTL, single use). The backend's device-code flow is most of this already
(`backend/src/routes/deviceAuth.ts`, `backend/src/lib/deviceAuth.ts`): here the phone creates and
approves the code in one step, instead of the computer creating it. The CLI redeems it for its own
session. Today an approval returns a machine `apiKey`, but the daemon's socket (`/api/adapter-ws`)
accepts only an SSO token (`backend/src/lib/adapterWs.ts:11-13, 172`). So either redeeming returns
tokens the socket accepts, or the socket also accepts the machine key. **This is the security review.**

**Pairing secret.** A high-entropy code made on the phone that never goes to the backend. The
computer runs the daemon's one-time-code pairing with it: CPace over the code, as the retired web
client did (`cli/src/lib/e2ee/manager.ts:405-568`, `harness pair <code>`). Both ends pin each other's
keys. This keeps the remote password's security property. The backend and relay are treated as
untrusted (`docs/architecture.md:35-41`), and the secret reaches the computer by a path they don't
control: you, carrying the command. The code is used once, and the pairing window closes after 60 s,
or after 10 minutes if we lengthen it for this.

**What the installer adds:** it accepts the setup code again, runs `login --code`, `start` and
`pair`, and installs a launchd agent (macOS) or a systemd user unit (Linux) so the daemon comes back
after a reboot.

## Sessions you already have

After connecting, the phone lists the sessions on that computer, **including ones started outside
Harness**. The session search indexer already reads every engine's transcripts (see
`docs/research/2026-09-26-session-search.md`). Today it indexes only sessions Harness registered. The
changes:

- Index `~/.claude/projects` and `~/.codex/sessions` whole. They show as sessions to resume, not
  running agents.
- Tapping one resumes it in a Harness pane (`claude --resume <id>`, `codex resume <id>`) and opens
  its terminal. The desktop gets the same list.

This is what "set up all their sessions" means on day one: everything you already did with Claude
Code or Codex is there to continue.

## Work

| | Part | Est. |
|---|---|---|
| **1. Phone, now** | Order the four commands as the installer does. Share sheet ("Send to my Mac") instead of `mailto:`. A tap-to-copy single block. Plain-words errors. Refresh the computer list live. | 2 days |
| **2. Backend** | `POST /api/setup-codes` (phone, SSO) → a code. `POST /api/setup-codes/redeem` (CLI, no auth) → a session the daemon's socket accepts. One use, 10-minute TTL, rate-limited, listed and revocable. | 3–4 days + review |
| **3. CLI** | `install.sh <code>`. `harness login --code`. `harness pair` in the installer. A launchd/systemd unit. Output: "Connected. Open Harness on your phone." | 4–5 days |
| **4. Phone** | The setup card above, and the live-code pairing client (port the pairing context from `cli/src/lib/e2ee/core.ts`). "Add another computer." | 4–5 days |
| **5. Sessions** | Index outside sessions; a "Resume" row in Find and after connecting. | 1 week |
| **6. Later** | Sign in with Apple. A QR on the computer for phone number two. One pairing that introduces every computer you own (plan 001, B3). | — |

Parts 2 and 3 are one pull request each and can run in parallel; part 4 follows them. Parts 1 and 5
stand alone.

## The bar

Hand a phone to someone with a Mac who has never heard of Harness. Within three minutes they have
it running and are talking to one of their existing Claude Code sessions from the phone, without
asking anything and without typing a password.

## Decisions for you

1. **Short domain.** `harness.sh/<code>` reads well and is easy to type from the phone. Otherwise
   `harness.autonomous.ai/i/<code>`.
2. **The daemon's credential.** Redeeming a setup code yields either SSO tokens (no socket change)
   or a machine key (the socket learns a second credential, revocable per computer). The first is
   simpler; the second is cleaner.
3. **The remote password.** It stays as the fallback for computers set up by hand. It is dropped
   from the phone path entirely, not only hidden.
4. **Outside sessions.** Index all of them by default, or ask once on the computer ("Show my Claude
   Code and Codex sessions on my phone? Y/n"). They hold code and secrets. They never leave the
   machine except as hits and tails, sealed, which is how search works today.
