# Harness Monitor

The dock opens one reusable Harness Monitor tab. Its DSH viewer starts as a full-width session table;
**Ask assistant** reveals its OpenCode terminal beside it. No prompt is submitted when the table opens.

The default columns are Harness, Status, Agent, Machine, Project, Branch, CPU %, RAM, Tokens and Last
active, followed by **Open** and **×**. Headers sort; drag their separators to resize. Columns offers
Model, PID, Harness ID, Conversation ID and Folder. Search covers metadata. Names and actions remain visible while
scrolling horizontally. Refreshes preserve selection, controls, column widths and scroll. Arrow keys
select and Enter opens. Engine images are copied from the desktop's existing icon assets; status marks
and the reduced-motion-aware spinner follow its notification/tab/pane activity marks.

Open navigates to an existing session or resumes stopped work through the app's receipt coordinator.
× stops the owning daemon's validated process, retaining history and the saved DSH/runtime settings.
The daemon reports whether resume restores a conversation, a shell or a fresh conversation. Remote
machines use the same paired bridge and lifecycle APIs. Cached offline rows remain visible with disabled
actions. Unknown readings show a dash. Older daemons need updating for activity and resource readings.

CPU uses the daemon's shared process sampler, measuring interval use; multiple cores can
exceed 100%. RAM is subtree resident memory and can double-count shared pages. Token counts are the
owning daemon's conversation ledger. Last active is conversation activity, never file mtime.

**Cleanup…** previews the current policy and requires an explicit apply. Working, waiting, pinned,
offline and unknown-activity sessions are protected and rechecked at execution. There is no automatic
cleanup timer. The same tools are available to the assistant as `$HPS_CLI` (`toolchain/hps --help`).
Rules/pins remain in `~/.config/harness/policy.jsonc`; receipts are under `~/.harness/monitor/`.

OpenCode defaults both `model` and `small_model` to
`opencode/muse-spark-1.3-contributor-free`. [OpenCode Zen](https://opencode.ai/docs/zen/) currently lists
this as a limited-time free offer. **Contributor permits Meta to train on prompts and responses.**
The first assistant choice discloses this and offers choosing another model with `/models`. Zen login
may be needed. There is no automatic paid fallback. Existing sessions retain their saved runtime and
model configuration; changing the package default does not retarget them.

`npm test` runs with isolated policy/state fixtures. Browser review: `node test/preview.mjs` serves
synthetic sessions and records simulated actions; it cannot touch real harnesses.

## Credit and stewardship

Built by Autonomous for Harness, MIT. See [LICENSE](LICENSE). Process identity and lifecycle belong to
the Harness CLI; the table, cleanup proposals and `hps` live in this package. Engine artwork is reused
from the desktop; attribution is included beside the copied icons.
