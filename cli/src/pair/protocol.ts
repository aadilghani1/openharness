/**
 * The pair brain's shapes (daemons/BRAIN.md), shared by the sensor that runs on every harnessd, the
 * machine-to-machine `pair_*` RPCs, and the brain on the computer you are at.
 *
 * Nothing here is a model or a transport. Two rules live in this file because every layer needs them
 * and they must never drift apart:
 *   - which permission prompts are DENY-CLASS (push, force, rm -rf, deploy, publish, drop, merge): they
 *     never get a `[y]` key and are never recommended or approved automatically;
 *   - which frames are local-only (`daemon_*`, loopback through sendLocal) and which are machine to
 *     machine (`pair_*`, sealed — see lib/e2ee/applicationFrames.ts).
 */

/** What the journal records. `question`/`answered` pair up by requestId. */
export type PairKind = 'start' | 'done' | 'fail' | 'question' | 'answered' | 'recap'

export interface PairJournalEntry {
  /** The journal's lifetime: a new file (or one that could not be read) is a new epoch. */
  epoch: string
  /** Monotonic within an epoch. A reader's cursor is (epoch, seq). */
  seq: number
  at: number
  kind: PairKind
  agentId: string
  name: string
  engine: string
  requestId?: string
  /** The question, the recap, or why a turn failed. Untrusted text from a pane or a model. */
  text?: string
  options?: string[]
  /** The question matches a deny-class prompt (see isDenyClass). Decided here, on the owning machine. */
  deny?: boolean
}

export interface PairQuestion {
  requestId: string
  text: string
  options: string[]
  multi: boolean
  deny: boolean
  since: number
}

/** One harness as the sensor sees it. Everything a `daemon_state` needs, nothing a pane has to be read for. */
export interface PairHarness {
  agentId: string
  name: string
  engine: string
  working: boolean
  question: PairQuestion | null
  /** Why the last turn failed, until the next one starts. */
  failing: string | null
  lastDoneAt: number | null
  recap: string | null
}

export interface PairSnapshot {
  machineId: string
  epoch: string
  seq: number
  /** Bumped on every change, journaled or not — orders a snapshot against the pushes around it. */
  rev: number
  harnesses: PairHarness[]
}

/**
 * One change, pushed to watchers (locally to the brain, remotely as `pair_event`).
 *
 * `baseline` marks a change that is not news: a turn re-read from disk, a question that was already
 * open before this daemon started. The state moves; nothing is journaled and nobody reacts.
 */
export interface PairEvent {
  machineId: string
  rev: number
  harness: PairHarness | null
  agentId: string
  entry?: PairJournalEntry
  baseline?: boolean
  removed?: boolean
}

/** A page of journal. `reset` = the cursor's epoch is gone (start again from these); `truncated` = the
 *  ring dropped entries the cursor had not read yet. */
export interface PairJournalPage {
  epoch: string
  seq: number
  entries: PairJournalEntry[]
  reset?: boolean
  truncated?: boolean
}

/** What backendSocket asks of the sensor for the `pair_*` RPCs and the local `pair` request. */
export interface PairService {
  /** Pairing is on (the account's zoo has a paired daemon). Off, every `pair_*` answers PAIR_OFF. */
  enabled(): boolean
  /** Start pushing events to `connId`; answers the snapshot to begin from. `push` false = gone. */
  watch(connId: string, push: (event: PairEvent) => boolean): PairSnapshot
  unwatch(connId: string): void
  journal(payload: Record<string, unknown>): PairJournalPage
  read(payload: Record<string, unknown>): Record<string, unknown>
  /** The local-only `pair` request (the control interface grows from here, BRAIN.md P4). */
  local(payload: Record<string, unknown>): Promise<Record<string, unknown>>
}

// ── deny class ──────────────────────────────────────────────────────────────────────────────────────

/**
 * Permission prompts that are never approved by a key, a rule or a recommendation: push, force,
 * `rm -rf`, deploy, publish, drop, merge. Matched on the question text AND its options, because a
 * dialog can put the command in either. Word-bounded so "dropdown" or "emergency" do not trip it; a
 * false positive only costs the `[y]` key, a false negative approves a push — so it leans wide.
 */
const DENY_PATTERNS: RegExp[] = [
  /\bpush(ed|es|ing)?\b/i,
  /--force\b|\bforce[- ]?(push|with-lease)?\b|(^|\s)-f(\s|$)/i,
  /\brm\s+(-[a-z]*r[a-z]*f[a-z]*|-[a-z]*f[a-z]*r[a-z]*|-r\s+-f|-f\s+-r|--recursive\s+--force|--force\s+--recursive)\b/i,
  /\bdeploy(s|ed|ing|ment)?\b/i,
  /\bpublish(es|ed|ing)?\b/i,
  /\bdrop\s+(table|database|schema|index|column|collection|view)\b|\bdropdb\b|\bdrop\b(?!down)/i,
  /\bmerge(s|d)?\b/i,
]

export function isDenyClass(question: string, options: string[] = []): boolean {
  const text = [question, ...options].join('\n')
  return DENY_PATTERNS.some((pattern) => pattern.test(text))
}

// ── local frames (loopback only) ────────────────────────────────────────────────────────────────────

export const DAEMON_OUT_TYPES = new Set(['daemon_state', 'daemon_say', 'daemon_unsay', 'daemon_brief', 'daemon_act_result'])
export const DAEMON_IN_TYPES = new Set(['daemon_act', 'daemon_presence'])

export type DaemonMood = 'need' | 'done' | 'fail' | 'back'

export interface DaemonAction {
  /** The key a client binds: `y` approves the recommendation, `n` declines. */
  key: 'y' | 'n'
  label: string
  /** The option label the answer keys in. */
  choice: string
}

export interface DaemonSay {
  id: string
  about: { machineId: string; agentId: string; requestId?: string }
  mood: DaemonMood
  line: string
  actions: DaemonAction[]
  ttlMs: number
}

// ── helpers ─────────────────────────────────────────────────────────────────────────────────────────

/** Printable 7-bit ASCII, one line, bounded — what a status line can draw and a model may not exceed. */
export function statusText(value: string, max: number): string {
  const flat = value.replace(/[\r\n\t]+/g, ' ').replace(/[^\x20-\x7e]/g, '').replace(/\s+/g, ' ').trim()
  return flat.length > max ? `${flat.slice(0, Math.max(0, max - 3)).trimEnd()}...` : flat
}

export function str(value: unknown, max = 200): string {
  return typeof value === 'string' ? value.slice(0, max) : ''
}
