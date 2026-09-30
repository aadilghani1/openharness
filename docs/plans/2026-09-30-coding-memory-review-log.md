# Coding memory: sequential review and implementation

Status: in progress, 2026-09-30. The objective remains a thoroughly reviewed, useful coding memory system across agent frameworks. Passing an isolated core suite does not establish completion or perfection.

These reviews are performed by Codex using the published principles collected in the [historical council](2026-09-30-coding-memory-council.md) and [modern practitioner study](../research/2026-09-30-modern-coding-memory.md). They are not personal participation, simulated quotations, or endorsements by the named programmers. Each perspective produces a concrete question, a change or open requirement, and evidence needed to close it. Review again after integration, not just after the design document.

## Authoritative starting state

The preceding examples-only answer made no implementation progress. This turn rechecked the worktree and fast-forwarded the design branch from `5e2d026a9` to the already-fetched `origin/main` at `21793ef8d`. Existing research files were preserved. The current runtime has `LessonStore`, narrow signal learning, explicit conversation lookback, and `CompanionIntelligence`; it did not contain the proposed memory service.

The new code is in `cli/src/memory/`. It is an isolated library and is not yet wired into the installed daemon, agent hooks, or desktop viewer. No personal conversations have been ingested into it during development.

## Review sequence: round one

| Order / perspective | Our review question and finding | Change and remaining evidence |
| --- | --- | --- |
| 1. Peter Naur | Can another agent recover why a choice made sense, including its limits? A bare lesson string loses this. | The record carries rationale, conditions, exceptions, source spans, and revision. Live handoff and faithful extraction remain unverified. |
| 2. Edsger Dijkstra | Which properties are established, and which merely asserted? A model could otherwise manufacture evidence metadata. | Admission requires actual source IDs/spans and checks verification against the captured source. Tests reject invented verification and assistant success claims. This proves structural checks, not semantic faithfulness of every paraphrase. |
| 3. Barbara Liskov | Do both host adapters preserve the same contract? | The core has a framework-neutral record and recall packet. Real Claude/Codex context delivery and resumed-session behavior remain required. |
| 4. Jeannette Wing | Does information retain its scope and meaning through composition? | Access and topic dependency checks prevent profile/project widening; tool-quoted user text cannot become user evidence. Adapter and extraction adversarial tests remain required. |
| 5. David Parnas | Can storage, extraction, and delivery change independently? | Types, admission, and storage are separate modules. Durable learning and engine adapters are the next boundaries to implement. |
| 6. Donald Knuth | Can the user understand a memory without reading a database row? | Claims, rationale, conditions, and evidence are explicit. The actual readable viewer and evidence navigation remain pending. |
| 7. Dennis Ritchie | Is the service small enough to compose with existing agents? | Local SQLite and narrow operations form the core. CLI/MCP integration remains pending; no new external database service was added. |
| 8. Ken Thompson | Can behavior be inspected and reproduced with small tools? | Disk persistence and reopen tests exercise the actual SQLite store. A runnable cross-framework demonstration and export/diagnostic commands remain pending. |
| 9. Kent Beck | Does feedback expose an actual failure before it is declared fixed? | The second pass produced four failing behavior tests, then repaired conflict resolution, topic revision continuity, stale-generation commits, and dependent-note deletion. |
| 10. Rich Hickey | Are identity, revision, and current applicability separate? | Memory IDs persist across CAS revisions. Topic invalidation now keeps content-free revision metadata, so regeneration cannot reuse a revision number. |
| 11. Margaret Hamilton | Can learning or storage failure disrupt coding? | Missing SQLite returns a typed unavailable result; lock waits are bounded. Worker isolation, durable leases/recovery, and foreground recall deadlines remain pending. |
| 12. Bret Victor | Can the user see why behavior changed and correct it? | The core exposes records, history, evidence, correction, and forgetting. The DSH interaction and visual review remain pending. |
| 13. Peter Steinberger | Does memory point to current workspace authority instead of duplicating it? | Reference details retain evidence and conditions. Resource discovery, revision checks, and host-loaded status still need executable integration tests. |
| 14. Andrej Karpathy | Can a failed experiment win because a placeholder looks like a good score? Can generated synthesis reinforce itself? | Failed runs normalize to null scores; comparisons require recorded conditions. Derived source lineage and topic dependencies prevent treating their records as independent user evidence. Actual evaluator comparison and notebook generation remain pending. |
| 15. Jeff Dean | Does collaboration change with the task while acceptance stays explicit? | Conditional recall and temporary-state labels preserve that distinction. Real matched tasks, performance measurement, and interaction evaluation remain pending. |
| 16. Mitchell Hashimoto | Does a repeated mistake improve the workspace, or merely produce more reminders? | Canonical references and negative knowledge are in the model. The feedback path that proposes a meaningful helper/test change remains pending. |
| 17. Simon Willison | Is a remembered capability tied to something that actually ran? | Verification carries an artifact, revision, environment, coverage, and limits. Native execution receipts and reusable-example applicability remain pending. |
| 18. Addy Osmani | Do requirements survive task steps and agent switches? | The design carries task contracts and scoped decisions. Complete episode capture and end-to-end acceptance tests remain pending. |
| 19. Charity Majors | Does production evidence refer to this change, environment, and observation window? | Operational verification has distinct fields. Real operational adapters and tests against wrong-build attribution remain pending. |

## Round two: executable findings

The first 19 store tests passed. Additional tests then demonstrated four failures before fixes:

1. A correction could not safely resolve a conflicting peer. Resolution now checks every supplied peer revision and updates the group transactionally.
2. Invalidating a topic deleted its revision history marker. Invalid pages now retain scope and revision metadata with their content cleared; regeneration compares the expected revision.
3. A topic generation started before learning was toggled could commit afterward. Topic publication now checks the control generation as well as parent revisions.
4. Forgetting a parent left a generated dependent memory. Sources now record explicit memory dependencies; deletion follows that graph, purges owned derivatives, and retains only evidence spans used by unrelated surviving records.

Subsequent checks added field-level evidence coverage, failed-run normalization, validity-window checks for current topics, and preservation of exceptions/verification limits in recall packets.

Validation at the end of round two: 30 tests in `src/memory` and the existing SQLite/guard regression subset (46 tests) passed. CLI TypeScript checking passed. These were isolated core checks, not a native agent benchmark or a completed rollout.

## Round three: correction, continuous intake, and responsiveness

Two new tests failed before fixes: a generated dependent record remained current after its parent was corrected, and a broad surviving evidence quote could retain forgotten content. Corrections now invalidate current descendants and reject stale derived evidence. Forgetting follows overlapping source spans conservatively as well as explicit derivation links; unrelated records with disjoint evidence spans survive. Explicit user corrections work with automatic learning off, while ordinary ingestion remains gated.

Source access preserves task/branch boundaries, and derived topic statements carry their parents' conditions, exceptions, and validity. Project identity resolves Git worktrees through their common directory, generates opaque persistent IDs, and permits explicit unused aliases. Matching remotes do not merge unrelated projects.

The durable queue commits source events, episode state, and capture cursors atomically. Tests cover first-message capture before an assistant reply, replay, process restart, incomplete inputs, excluded/private source rollback, selected-model outages, per-project leases, expired-worker recovery, model/account/control changes, atomic proposal batches, and forgetting during inference. Inference reservations persist a six-call rolling hourly budget. A successful empty extraction has a different state from model unavailability or missing sources.

SQLite now runs through a bundled worker with a typed internal operation contract. Real worker tests exercise capture, recall, restart, scope checks, and forgetting. A blocked-worker test verifies that recall times out while the parent remains responsive. This establishes the deadline mechanism, not the 10,000-record latency gate.

Round-three checkpoint: 53 memory tests passed. TypeScript passed at the 50-test checkpoint. Subsequent validation and implementation status are recorded below.

## Round four: evidence-based self-improvement

The user's overnight direction makes continuous learning and improvement explicit. The architecture now separates evolving knowledge, contextual usefulness, and versioned system-quality experiments. New corroboration tests add independent evidence from another framework to an existing meaning without duplicating or rewriting it. Repeated input and generated echoes add no independent confirmation. Old confirmations do not transfer to a corrected meaning, and forgetting also purges corroborating sources.

The primary-source research refresh inspected the author abstracts/version histories for [ACE v3](https://arxiv.org/abs/2510.04618v3), [LongMemEval v2](https://arxiv.org/abs/2410.10813v2), [RoMeRL v3](https://arxiv.org/abs/2608.02508v3), and [EDV v1](https://arxiv.org/abs/2606.24428v1). Their findings motivate granular updates, temporal/abstention evaluation, careful credit assignment, and separate verification. Their benchmark results are not claimed for Harness. Full methodological comparison and reproduction are still open.

## Open implementation and review work

The full [architecture](2026-09-30-tim-memory.md) and its [64 synthetic scenarios](2026-09-30-tim-memory-cases.json) remain the requirement set. The synthetic scenarios are not equivalent to the executable core tests or to the separate held-out evaluation.

- Connect the tested project identity resolver to authenticated host sessions.
- Connect the tested native reader and learning loop to live host sessions. Bind coding-domain eligibility, private conversations, project exclusions, fork boundaries, and profile ownership before enabling automatic capture.
- Schedule the tested restricted inference adapters through the collection DSH and expose unavailable/unsupported model states. Exercise actual account switching and native invocation in that host path.
- Add quiet-period batching and bounded evidence/backlog retention; incomplete or oversized episodes currently remain explicit gaps rather than being silently summarized.
- Validate the extraction process and faithful field-level support with real models. Structural source checks alone cannot establish this.
- Integrate the measured worker recall path and its deadline into live callers; measure actual received context and hook latency.
- Implement authenticated CLI/MCP operations, receipts, and pinned Claude/Codex lifecycle adapters. Verify actual received context, not just hook output.
- Build the three Memories views inside the existing DSH viewer while retaining the real agent terminal on the right.
- Integrate notebook synthesis, correction/forget invalidation of owned exports/caches, and diagnostics for previously delivered native context.
- Preserve approved lessons and native memory, with versioned migration, rollback, and experimental controls.
- Exercise the three real coding workflows in both framework directions, matched preferences, no-recall/conflict cases, baselines, and the architecture's held-out and performance gates.

## Integration discovery requiring follow-up

The existing Claude one-shot process disables built-in tools and MCP loading. The Codex process currently uses a read-only sandbox and ignores user config/rules, which does not by itself establish zero tool availability. Before using it for the new learner, certify a supported restricted inference configuration against the installed release and preserve the selected account/model. Do not infer tool removal from a sandbox label or silently switch providers. [Official configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference), [approval and sandbox behavior](https://learn.chatgpt.com/docs/agent-approvals-security).

A local mock-server probe of installed Codex 0.159.0, using synthetic input, a fake key, and the `gpt-5.4` model identifier, disabled execution/app/browser/plugin/agent features. The outgoing catalog contained only `request_user_input`. A synthetic call to that tool returned an error item without interactive input; a synthetic `exec_command` request was refused and created no marker file. This is evidence for that tested configuration, not a universal no-tools claim or a live-model test. The restricted adapter and its failure tests are now implemented; host integration remains pending. Probe source: `.scratch/memory-implementation-20260930/tool-catalog-probe.mjs` (development-only, not a shipped artifact).

The store uses ordinary-page secure deletion plus FTS5 secure deletion, and avoids a persistent WAL. This protects the owned current database/index; it does not erase OS snapshots, independent exports, or already-delivered native transcripts. [SQLite FTS5 deletion behavior](https://www.sqlite.org/fts5.html#the_secure_delete_configuration_option).

## Round five: native capture, bounded inference, and measured retrieval

The selected-model extraction loop now claims a durable lease, supplies bounded evidence and existing drafts, validates JSON, and rechecks the current target before publication. Tests distinguish no useful memory from an outage, reject fabricated quotes and publication fields, coalesce ticks, stop hung providers, and cancel even when a provider ignores its abort signal. Unknown rationales can remain null. Proposed future actions, exceptions, and validity conditions now require evidence coverage as well as the main claim; structural coverage still does not prove semantic entailment.

Native capture reads registered Claude/Codex JSONL files independently of UI previews. Sources and byte cursors commit together. Tests cover the first user message before a reply, restart, partial UTF-8 writes, consent/pause boundaries, in-place rewrites, bounded oversized-record handling, quiet closure, project reassignment refusal, and a host-provided fork boundary. Pasted code and block quotes are reference data, and tool output never acquires user authorship. No native tool output is promoted to verified test evidence merely because it was captured: typed execution verification still needs its own adapter. General-domain filtering, complete fork/import lineage, and private-session controls must be bound by the host before rollout.

`CompanionIntelligence.extract` uses fresh, bounded native processes and checks observed login identity before and after inference. The original `run` path remains available for existing lessons. Codex 0.159.0 and Claude Code 2.1.285 are the initially tested releases; unknown releases wait rather than select another model. A separate local mock probe of Claude with an isolated config, fake token, and `claude-opus-4-6` reported an empty outgoing tool catalog. A forced unlisted Bash call created no marker. Process tests reject tool availability/attempts, error results, unexpected protocols, and oversized output, and preserve Unicode across pipe chunks. These are protocol/configuration checks, not real-model quality tests. The restriction flags are documented in the [official Claude CLI reference](https://code.claude.com/docs/en/cli-reference).

The 10,000-record benchmark initially missed the warm p95 target: 196.6 ms. SQLite selected the scope index first and repeated the FTS scan for each scoped row. Driving the join from FTS once reduced it to 12.7 ms. A second review found that inapplicable or expired rows could consume all 120 candidate slots. Conditions, exceptions, validity, and exclusions now filter before that cap; a regression with 125 newer unusable matches still finds the older applicable memory. Typed scalar/array condition tests pass. With those filters, warm p95 is 15.9 ms, new-worker p95 is 42.3 ms, and no request timed out among 310. This is one synthetic local dataset, not a relevance evaluation; “cold” does not mean a cleared OS disk cache. [Reproducible measurements](../research/2026-09-30-memory-performance.json); runner: `cli/scripts/memory-benchmark.ts`.

Latest checkpoint: **112 memory/companion tests plus 46 existing SQLite/guard regression tests passed** (158 total). CLI TypeScript checking, release bundling, and the bundled version smoke check passed. No installed app or daemon was replaced, no personal conversations were ingested, and no real provider model was called by these probes. The code remains an unshipped integration foundation; live delivery, the viewer, retention, native execution receipts, faithful extraction, and held-out behavioral evaluation remain open.
