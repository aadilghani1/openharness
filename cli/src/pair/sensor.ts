/**
 * PairSensor — the model-free half of the pair brain, run by EVERY harnessd for its own harnesses
 * (daemons/BRAIN.md, "sense everywhere, think where you are").
 *
 * It follows three things the daemon already knows: turns starting and ending (emitSessionEvents, with
 * its `replay` and `subagent` flags), questions on a pane (QuestionWatcher onQuestion/onQuestionGone)
 * and recaps (CommanderMirror onSummary). From them it keeps each harness's state, journals what is
 * news (pair/journal.ts), and pushes every change to whoever watches: the brain on this computer, and
 * other machines' brains over sealed `pair_watch`.
 *
 * What is NOT news, and therefore moves the state without a journal line or a reaction:
 *   - a replay: a turn re-read from disk or resumed at attach;
 *   - a question that was already open before this daemon started (the journal says so).
 * What is never watched at all: sub-agents (an Orchestrator specialist nobody asked to hear from),
 * terminals (a shell is not an agent), and the pair harness itself.
 *
 * Off unless the account's zoo has a paired daemon. Off, it records nothing and answers PAIR_OFF.
 */
import type { ShapedQuestion } from '../lib/askQuestion.js'
import type { PairJournal } from './journal.js'
import {
  isDenyClass, statusText, str,
  type PairAction, type PairActor, type PairEvent, type PairHarness, type PairJournalEntry, type PairJournalPage,
  type PairService, type PairSnapshot,
} from './protocol.js'

export interface PairSubject {
  name: string
  engine: string
  /** Why this agent is not watched, if it is not. */
  excluded?: 'terminal' | 'pair' | 'subagent' | null
}

export interface PairSensorDeps {
  machineId: () => string
  journal: PairJournal
  /** Who an agent is right now; null when it is gone. */
  describe: (agentId: string) => PairSubject | null
  now?: () => number
  /** Pairing turned on or off — cli.ts re-gates the question watcher and the recap on it. */
  onEnabledChanged?: (on: boolean) => void
}

type EntryFields = Omit<PairJournalEntry, 'epoch' | 'seq' | 'at' | 'agentId' | 'name' | 'engine'>

export class PairSensor implements PairService {
  private on = false
  private daemonId: string | null = null
  private readonly harnesses = new Map<string, PairHarness>()
  private rev = 0
  private readonly watchers = new Map<string, (event: PairEvent) => boolean>()
  private readonly listeners = new Set<(event: PairEvent) => void>()
  /** Questions open when this daemon started (journaled, never answered). Seeing one again is a baseline. */
  private readonly carried: Set<string>
  private readonly now: () => number

  constructor(private readonly deps: PairSensorDeps) {
    this.now = deps.now ?? Date.now
    this.carried = new Set(deps.journal.openQuestions().keys())
  }

  // ── the switch ────────────────────────────────────────────────────────────────────────────────────

  /** The paired daemon's roster id, or null when nothing is paired (pairing off). */
  setPair(daemonId: string | null): void {
    this.daemonId = daemonId
    const on = daemonId !== null
    if (on === this.on) return
    this.on = on
    if (!on) {
      // Nothing about a harness survives pairing being switched off: the next time it is on, state is
      // rebuilt from what happens, and the brain on the other end is told PAIR_OFF on its next request.
      this.harnesses.clear()
      this.watchers.clear()
    }
    console.log(`[pair] sensor ${on ? `on · paired with ${daemonId}` : 'off · nothing paired'}`)
    this.deps.onEnabledChanged?.(on)
  }

  enabled(): boolean { return this.on }
  pairedDaemon(): string | null { return this.daemonId }

  // ── inputs ────────────────────────────────────────────────────────────────────────────────────────

  turnStarted(agentId: string, opts: { replay?: boolean; subagent?: boolean } = {}): void {
    const h = this.admit(agentId, opts.subagent)
    if (!h) return
    h.working = true
    h.failing = null
    this.change(h, opts.replay ? null : { kind: 'start' }, opts.replay)
  }

  turnEnded(agentId: string, opts: { replay?: boolean; subagent?: boolean; aborted?: boolean } = {}): void {
    const h = this.admit(agentId, opts.subagent)
    if (!h) return
    // Two sources close every turn (the transcript and the Stop hook). The second finds it closed.
    if (!h.working && !opts.replay) return
    h.working = false
    h.lastDoneAt = this.now()
    this.change(h, opts.replay ? null : { kind: 'done', ...(opts.aborted ? { text: 'interrupted' } : {}) }, opts.replay)
  }

  question(agentId: string, requestId: string, shaped: ShapedQuestion[]): void {
    const h = this.admit(agentId)
    if (!h || !requestId) return
    // The watcher re-announces an open question to a device that (re)joins: same id, not a new ask.
    if (h.question?.requestId === requestId) return
    const first = shaped[0]
    const text = statusText(first?.q ?? '', 500)
    const options = (first?.options ?? []).map((option) => statusText(option, 120)).slice(0, 12)
    const deny = isDenyClass(first?.q ?? '', first?.options ?? [])
    h.question = { requestId, text, options, multi: first?.multi === true, deny, since: this.now() }
    const baseline = this.carried.delete(requestId)
    this.change(h, baseline ? null : { kind: 'question', requestId, text, options, deny }, baseline)
  }

  questionGone(agentId: string, requestId: string): void {
    const h = this.harnesses.get(agentId)
    if (!this.on || !h || h.question?.requestId !== requestId) return
    h.question = null
    this.change(h, { kind: 'answered', requestId })
  }

  recap(agentId: string, recap: string): void {
    const h = this.admit(agentId)
    const text = statusText(recap, 300)
    if (!h || !text || h.recap === text) return
    h.recap = text
    this.change(h, { kind: 'recap', text })
  }

  /** The harness failed to start, or its engine went away mid-work. Once per distinct reason. */
  failed(agentId: string, reason: string): void {
    const h = this.admit(agentId)
    const text = statusText(reason, 200) || 'failed'
    if (!h || h.failing === text) return
    h.failing = text
    h.working = false
    this.change(h, { kind: 'fail', text })
  }

  /**
   * Something the daemon did to a harness on this machine (pair/owner.ts): EVERY action is journaled,
   * whoever asked for it. Pushed like any change, so the brain can report what a rule or the pair did.
   * A harness that is no longer live (it was just paused) is journaled under the name it had and pushed
   * as gone.
   */
  acted(subject: { agentId: string; name: string; engine: string },
    fields: { by: PairActor; action: PairAction; text: string; requestId?: string }): PairJournalEntry | null {
    if (!this.on || !subject.agentId) return null
    const text = statusText(fields.text, 300)
    const entryFields = { kind: 'act' as const, by: fields.by, action: fields.action, text, ...(fields.requestId ? { requestId: fields.requestId } : {}) }
    const h = this.harnesses.get(subject.agentId) ?? this.admit(subject.agentId)
    if (h) return this.change(h, entryFields)
    const entry = this.deps.journal.append({
      at: this.now(), agentId: subject.agentId, name: statusText(subject.name, 80) || subject.agentId.slice(0, 8), engine: subject.engine, ...entryFields,
    })
    this.rev++
    this.emit({ machineId: this.deps.machineId(), rev: this.rev, agentId: subject.agentId, harness: null, removed: true, entry })
    return entry
  }

  /** One harness's state, or null when it is not watched. */
  harness(agentId: string): PairHarness | null {
    const h = this.harnesses.get(agentId)
    return h ? copy(h) : null
  }

  removed(agentId: string): void {
    if (!this.harnesses.delete(agentId)) return
    this.rev++
    this.emit({ machineId: this.deps.machineId(), rev: this.rev, agentId, harness: null, removed: true })
  }

  // ── outputs ───────────────────────────────────────────────────────────────────────────────────────

  snapshot(): PairSnapshot {
    return {
      machineId: this.deps.machineId(),
      epoch: this.deps.journal.epoch,
      seq: this.deps.journal.seq,
      rev: this.rev,
      harnesses: [...this.harnesses.values()].map(copy),
    }
  }

  /** The brain on this computer. Same events a remote watcher gets, without the wire. */
  subscribe(listener: (event: PairEvent) => void): () => void {
    this.listeners.add(listener)
    return () => { this.listeners.delete(listener) }
  }

  // ── PairService: what another machine's brain (sealed) and this computer (`pair`) may ask ────────

  watch(connId: string, push: (event: PairEvent) => boolean): PairSnapshot {
    this.watchers.set(connId, push)
    return this.snapshot()
  }

  unwatch(connId: string): void {
    this.watchers.delete(connId)
  }

  journal(payload: Record<string, unknown>): PairJournalPage {
    const num = (value: unknown): number | undefined => typeof value === 'number' && Number.isFinite(value) ? value : undefined
    return this.deps.journal.since({
      ...(typeof payload.epoch === 'string' ? { epoch: payload.epoch } : {}),
      ...(num(payload.seq) !== undefined ? { seq: num(payload.seq) } : {}),
      ...(num(payload.at) !== undefined ? { at: num(payload.at) } : {}),
      ...(num(payload.limit) !== undefined ? { limit: num(payload.limit) } : {}),
    })
  }

  read(payload: Record<string, unknown>): Record<string, unknown> {
    const agentId = str(payload.agentId)
    const h = agentId ? this.harnesses.get(agentId) : undefined
    return h ? { harness: copy(h) } : { error: 'NOT_FOUND' }
  }

  /** The loopback `pair` request. Read verbs only until the control interface (BRAIN.md P4). */
  async local(payload: Record<string, unknown>): Promise<Record<string, unknown>> {
    const verb = str(payload.verb, 40) || 'status'
    switch (verb) {
      case 'status':
        return { on: this.on, pair: this.daemonId, machineId: this.deps.machineId(), epoch: this.deps.journal.epoch, seq: this.deps.journal.seq }
      case 'list':
        return this.on ? { snapshot: this.snapshot() } : { error: 'PAIR_OFF' }
      case 'journal':
        return { ...this.journal(payload) }
      case 'read':
        return this.read(payload)
      default:
        return { error: 'UNKNOWN_VERB', detail: `pair has no verb "${verb}"` }
    }
  }

  // ── internals ─────────────────────────────────────────────────────────────────────────────────────

  private admit(agentId: string, subagent?: boolean): PairHarness | null {
    if (!this.on || !agentId) return null
    const subject = this.deps.describe(agentId)
    if (!subject || subject.excluded || subagent) {
      // A tile that turned into a terminal, or became a specialist, stops being reported.
      if (this.harnesses.has(agentId) && (!subject || subject.excluded)) this.removed(agentId)
      return null
    }
    let h = this.harnesses.get(agentId)
    if (!h) {
      h = { agentId, name: subject.name, engine: subject.engine, working: false, question: null, failing: null, lastDoneAt: null, recap: null }
      this.harnesses.set(agentId, h)
    }
    h.name = statusText(subject.name, 80) || agentId.slice(0, 8)
    h.engine = subject.engine
    return h
  }

  private change(h: PairHarness, fields: EntryFields | null, baseline = false): PairJournalEntry | null {
    this.rev++
    const entry = fields
      ? this.deps.journal.append({ at: this.now(), agentId: h.agentId, name: h.name, engine: h.engine, ...fields })
      : undefined
    this.emit({
      machineId: this.deps.machineId(),
      rev: this.rev,
      agentId: h.agentId,
      harness: copy(h),
      ...(entry ? { entry } : {}),
      ...(baseline ? { baseline: true } : {}),
    })
    return entry ?? null
  }

  private emit(event: PairEvent): void {
    for (const listener of [...this.listeners]) {
      try { listener(event) } catch (err) { console.warn(`[pair] listener failed: ${err instanceof Error ? err.message : String(err)}`) }
    }
    for (const [connId, push] of [...this.watchers]) {
      let delivered = false
      try { delivered = push(event) } catch { delivered = false }
      if (!delivered) this.watchers.delete(connId)
    }
  }
}

function copy(h: PairHarness): PairHarness {
  return { ...h, question: h.question ? { ...h.question, options: [...h.question.options] } : null }
}
