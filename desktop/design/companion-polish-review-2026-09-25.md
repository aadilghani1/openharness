# Companion polish review — 2026-09-25

Historical review and verification record. [Open the local reviews](review/index.html)
for the early creature and egg concepts; the later daemon design lives on the `daemons`
branch. Test counts below describe this review, not a fresh run of the current branch.

Three independent AI reviewers examined the terminal workflow, companion
behavior, and ASCII layout. This was source, test, and synthetic UI review;
it was not recruited-developer research or a conversion study.

The existing welcome and Cmd-N form stay intact. Hatching still requires a
finished first task, a connection to another computer, and a finished result
from a user-chosen non-coding Store harness. Local models remain optional.

## Findings applied

| Finding | Result |
| --- | --- |
| “Run” and “Try” did not explain what counts. | The selected discovery visibly explains its completion requirement. |
| Enter did nothing when the panel first opened. | Focus the next discovery or hatch action; arrows and j/k select a discovery. |
| Dismissed suggestions could send hatch guidance to optional Models. | Required discoveries have their own next-step selection. |
| The notification's Hatch action only toggled the panel. | It now hatches directly. Progress appears beside the egg and preserves existing work errors and input focus. |
| Ready depended on color and animation. | The shell stays cracked when ready, including under Reduce Motion. |
| Discoveries did not immediately affect the egg. | Each newly earned step gets one brief response. Restores and background updates do not replay it. |
| The egg was passive before completion. | Knocking gives a short, throttled rustle without changing progress. |
| The reveal lacked anticipation. | A bounded 1.8-second split-shell reveal ends with a blink; identity is saved once and accessible labels preserve the surprise. |
| Small-talk expectations and accessibility were unclear. | Ready-made replies are disclosed beside the prompt; replies use live regions, and quiet mode exposes its checked state. |
| Narrow layouts truncated the useful labels. | Compact titles, discovery labels, and actions fit large text; full descriptions remain available. |

## Verification

- 120 relevant Flutter tests passed after updating the compact-title expectation.
- 578 native titlebar and window-layout checks passed.
- Targeted analyzer reported no issues.
- Six production-widget captures used real fonts, including a 320px window
  with 22pt text. Light app chrome was checked with supported terminal palettes.
- An isolated native preview verified Enter, j/k guidance, knocking, all three
  discovery reactions, ready-state activation, the reveal, and a typed reply.
  This preview used memory-only state and did not reset the user's progress.

The next external validation should be real first-time developers reaching a
useful result and connecting a second computer. These checks establish behavior
and layout, not a claim that every user will complete onboarding.

## Approved nest progression

After reviewing the shell shapes, the user chose a consistent nest that reveals
signs of life: `\_O_/` → `~\_O_/~` → `\_.._/` → `\_o.o_/`.
Each earned discovery now has a persistent silhouette. Peeking eyes blink,
the ready face blinks and smiles, and the species stays hidden until the reveal.
This supersedes the cracked-shell treatment above. The follow-up passed 50
relevant Flutter tests, 644 native layout checks, targeted analysis, and a
local release build. Seven real-font captures cover all four resting stages.

## Event-driven motion

The follow-up removes periodic egg gestures, adult blinks, clock-boundary timers,
and companion-specific keyboard/pointer activity tracking. Existing task,
discovery, foreground, and direct interaction events drive finite reactions.
Discoveries take priority; completed turns have a timestamp-only twenty-second
cooldown with no queue. A fifteen-minute absence earns one welcome-back gesture.
Idle does not infer that a person stopped working; sleep is an explicit nap.

An independent AI behavior review caught a background-chat reply that could
remain pinned and a repeated nap that reused its old wake timer. Both were fixed
with regression coverage. An idle simulation verifies no further timer callbacks
or notifications across twenty-four hours after each reaction settles.

Headless debug controller benchmark on this development machine, 30 batches of
5,000 events per case, using the production clock and per-machine counters:

| Machines | Unchanged event, median | Completion during cooldown, median |
| --- | --- | --- |
| 1 | 0.27 µs | 0.33 µs |
| 10 | 0.63 µs | 0.70 µs |
| 100 | 4.37 µs | 4.53 µs |

Neither path emitted a notification during measurement. These timings cover the
controller checks, not gathering workspace state, native drawing, network work,
or overall app latency. Run `test/benchmarks/companion_benchmark.dart` explicitly
to reproduce; timing is reported, not used as a hardware-dependent pass threshold.

Final verification: 55 companion behavior, onboarding, and render tests passed;
all three benchmark cases passed; targeted analysis reported no issues. The
macOS release build succeeded in `build/macos-companion-polish`, and its local
ad hoc signature passed deep/strict verification after resealing the bundle.
The running app was not restarted; it still uses the earlier build.
