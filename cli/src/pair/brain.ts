/**
 * The pair brain: the half that thinks, run by the harnessd of the computer you are at — the one with a
 * window or `hn` attached (daemons/BRAIN.md). Every other daemon only senses.
 *
 * It keeps the fleet (pair/fleet.ts) while a client is attached, triages every NEW question (tier 0
 * template, tier 1 one small model call: pair/triage.ts), speaks through the rate-limited voice
 * (pair/voice.ts), and turns a key the person pressed (`daemon_act`) into an answer on the machine that
 * owns the harness.
 *
 * Local frames only, and only through `sendLocal`/`sendLocalTo`:
 *   out  daemon_state { pair, needs[], working, failing[], machines[] }   (on change, and to a new client)
 *        daemon_say / daemon_unsay                                         (pair/voice.ts)
 *        daemon_brief { desk, line, items[] }                              (on return, pair/brief.ts)
 *        daemon_act_result { requestId, id, ok, error? }                   (to the client that acted)
 *   in   daemon_act { requestId, id, choice }, daemon_presence { active, awayMs, pair?, desk? }
 *
 * Baselines are never news: a snapshot from a machine (re)connecting, a replay, a question already open
 * when this daemon started. Only a journal entry that arrives live makes it speak.
 */
import type { PairFleet, FleetChange, FleetHarness } from './fleet.js'
import type { PairTriage, TriageResult } from './triage.js'
import { backLine, doneLine, failLine, type PairVoice } from './voice.js'
import { briefNeedsModel, briefPrompt, composeBrief, parseBrief } from './brief.js'
import { str, type DaemonAction, type PairJournalEntry } from './protocol.js'

export const NEED_TTL_MS = 30 * 60_000
export const SAY_TTL_MS = 30_000
/** How long a finished turn waits for its recap before the line goes without it. */
export const DONE_RECAP_WAIT_MS = 1_500
/** An absence this long is a return worth a brief (daemons/README.md: `back` after 15 minutes). */
export const BRIEF_AWAY_MS = 15 * 60_000
/** Each machine's journal gets this long to answer before it is named as unreachable. */
export const BRIEF_JOURNAL_MS = 3_000
const STATE_DEBOUNCE_MS = 150

export type AnswerResult = { ok: boolean; error?: string; detail?: string }

export interface PairBrainDeps {
  /** This machine's sensor: the switch, and which daemon is paired. */
  pairing: { enabled: () => boolean; pairedDaemon: () => string | null }
  fleet: PairFleet
  triage: PairTriage
  voice: PairVoice
  /** Loopback only (backendSocket.sendLocal / sendLocalTo): never `send()`, which uploads. */
  sendLocal: (frame: Record<string, unknown>) => void
  sendLocalTo: (connId: string, frame: Record<string, unknown>) => boolean
  /**
   * Key an answer into a question on THIS machine: the owner's floor (pair/owner.ts), then
   * AskQuestionController, which types nothing unless the dialog on screen is still `requestId`
   * (STALE_QUESTION otherwise). The brain has already checked the question is the one the person saw.
   */
  answer: (input: { agentId: string; requestId: string; choice: string }) => Promise<AnswerResult>
  /** The control interface's proposals (pair/control.ts): a key on one of its lines is its to run. */
  proposals?: { owns: (id: string) => boolean; act: (id: string, choice: string) => Promise<Record<string, unknown>> }
  /** A guest's window says which daemon its local zoo pairs (daemon_presence.pair). */
  onGuestPair?: (daemonId: string | null) => void
  /** The brain started or stopped thinking (cli.ts keeps the router's worker warm while it does). */
  onActiveChanged?: (active: boolean) => void
  now: () => number
}

interface Presence { active: boolean; at: number }

/** The desk a client that names none is at: this computer. */
const LOCAL_DESK = 'local'

export class PairBrain {
  private readonly clients = new Set<string>()
  private readonly presence = new Map<string, Presence>()
  private active = false
  private stateTimer: ReturnType<typeof setTimeout> | null = null
  private lastState = ''
  /** `${machineId}\0${requestId}` → the live need line about it, so the state can carry its keys. */
  private readonly needSays = new Map<string, { id: string; result: TriageResult }>()
  private readonly doneWaits = new Map<string, { timer: ReturnType<typeof setTimeout>; change: FleetChange; entry: PairJournalEntry }>()
  /**
   * When this daemon started. A restart is a baseline, not a return: an absence that began before it
   * (a window reconnecting because the daemon restarted under it) is never briefed.
   */
  private readonly startedAt: number
  /** Per desk: when the person was last seen leaving (presence went inactive, or the last client left). */
  private readonly departed = new Map<string, number>()
  /** Per desk: when it was last briefed — the cursor that stops a second client repeating the brief. */
  private readonly cursors = new Map<string, number>()

  constructor(private readonly deps: PairBrainDeps) {
    this.startedAt = deps.now()
  }

  get isActive(): boolean { return this.active }

  // ── who is here ───────────────────────────────────────────────────────────────────────────────────

  clientAttached(connId: string): void {
    const first = this.clients.size === 0
    this.clients.add(connId)
    this.refresh()
    if (this.active) this.deps.sendLocalTo(connId, { type: 'daemon_state', payload: this.state() })
    // Nobody was here and now somebody is: a reconnect after long enough is a return.
    const left = this.departed.get(LOCAL_DESK)
    if (first && left !== undefined) {
      this.departed.delete(LOCAL_DESK)
      this.returned(LOCAL_DESK, this.deps.now() - left)
    }
  }

  clientDetached(connId: string): void {
    this.clients.delete(connId)
    this.presence.delete(connId)
    if (this.clients.size === 0 && !this.departed.has(LOCAL_DESK)) this.departed.set(LOCAL_DESK, this.deps.now())
    this.refresh()
  }

  /** `daemon_presence { active, awayMs, pair?, desk? }` from a window or `hn`. */
  onPresence(connId: string, payload: Record<string, unknown>): void {
    if ('pair' in payload) this.deps.onGuestPair?.(typeof payload.pair === 'string' ? payload.pair : null)
    if (typeof payload.active !== 'boolean') return
    const now = this.deps.now()
    this.presence.set(connId, { active: payload.active, at: now })
    const desk = str(payload.desk, 64) || LOCAL_DESK
    if (!payload.active) {
      if (!this.departed.has(desk)) this.departed.set(desk, now)
      return
    }
    // Back. The client's own measure of the absence counts (it knows about an idle keyboard this
    // daemon never sees), and so does a departure this daemon watched happen; the longer wins.
    const left = this.departed.get(desk)
    this.departed.delete(desk)
    const reported = typeof payload.awayMs === 'number' && Number.isFinite(payload.awayMs) ? Math.max(0, payload.awayMs) : 0
    this.returned(desk, Math.max(reported, left !== undefined ? now - left : 0))
  }

  /** A return: brief it if it was long enough, began after this daemon did, and this desk was not just briefed. */
  private returned(desk: string, awayMs: number): void {
    const now = this.deps.now()
    if (!this.active || awayMs < BRIEF_AWAY_MS) return
    if (now - awayMs < this.startedAt) return
    const cursor = this.cursors.get(desk) ?? this.startedAt
    if (now - cursor < BRIEF_AWAY_MS) return
    this.cursors.set(desk, now)
    void this.brief(desk, Math.max(now - awayMs, cursor), awayMs)
  }

  /**
   * Gather every machine's journal since the person left (3 s each), say the back line, then send the
   * items — rewritten by one model call only when there are 3+, a failure or a question.
   */
  private async brief(desk: string, since: number, awayMs: number): Promise<void> {
    const daemonId = this.deps.pairing.pairedDaemon()
    if (!daemonId) return
    const journals = await this.deps.fleet.journals(since, BRIEF_JOURNAL_MS)
    if (!this.active) return
    const now = this.deps.now()
    const { facts, items } = composeBrief({
      journals, harnesses: this.deps.fleet.harnesses(), machines: this.deps.fleet.machines(), awayMs, now,
    })
    const line = backLine(daemonId, facts)
    this.deps.voice.say({
      id: `back:${desk}:${now}`, mood: 'back', line, actions: [], ttlMs: SAY_TTL_MS,
      about: { machineId: this.deps.fleet.machines()[0]?.machineId ?? '', agentId: '' },
    })
    if (!items.length) return
    let written = items
    const triage = this.deps.triage
    if (briefNeedsModel(facts, items) && this.present() && triage.hasModel() && triage.takeCall()) {
      const { text } = await triage.ask(briefPrompt(daemonId, line, items))
      const lines = text ? parseBrief(text, items) : null
      if (lines) written = items.map((item) => ({ ...item, line: lines.get(item.id) ?? item.line }))
    }
    if (!this.active) return
    this.deps.sendLocal({ type: 'daemon_brief', payload: { desk, line, items: written } })
  }

  /** The person is at this computer: a client says so, or one is attached and has never said otherwise. */
  present(): boolean {
    for (const connId of this.clients) {
      const seen = this.presence.get(connId)
      if (!seen || seen.active) return true
    }
    return false
  }

  /** Pairing or the set of clients changed: start or stop thinking. */
  refresh(): void {
    const should = this.deps.pairing.enabled() && this.clients.size > 0
    if (should === this.active) return
    this.active = should
    this.deps.onActiveChanged?.(should)
    if (should) {
      this.deps.fleet.start()
    } else {
      this.deps.fleet.stop()
      for (const wait of this.doneWaits.values()) clearTimeout(wait.timer)
      this.doneWaits.clear()
      this.needSays.clear()
      if (this.stateTimer) { clearTimeout(this.stateTimer); this.stateTimer = null }
      // Pairing went off with a client still attached: tell it once, so it falls back to roster lines.
      if (this.clients.size > 0) this.sendState(true)
    }
  }

  // ── what the fleet reports ────────────────────────────────────────────────────────────────────────

  onFleetChange(change: FleetChange): void {
    if (!this.active) return
    this.scheduleState()
    const event = change.event
    if (!event) return
    if (event.removed || !event.harness) {
      this.deps.voice.unsayAbout(change.machineId, event.agentId, 'gone')
      return
    }
    // A question that is no longer on the harness — however we learned it — takes its line with it.
    for (const [key, need] of [...this.needSays]) {
      const [machineId, requestId] = key.split('\u0000')
      if (machineId !== change.machineId) continue
      const say = this.deps.voice.get(need.id)
      if (say?.about.agentId === event.agentId && event.harness.question?.requestId !== requestId) {
        this.needSays.delete(key)
        this.deps.voice.unsay(need.id, 'answered')
      }
    }
    if (event.baseline || !event.entry) return
    const entry = event.entry
    switch (entry.kind) {
      case 'question': void this.need(change, entry); return
      case 'answered':
        this.deps.voice.unsayAbout(change.machineId, event.agentId, 'answered', entry.requestId)
        this.needSays.delete(`${change.machineId}\u0000${entry.requestId}`)
        return
      case 'done': this.done(change, entry); return
      case 'recap': this.flushDone(`${change.machineId}\u0000${event.agentId}`, entry.text); return
      case 'fail': this.fail(change, entry); return
      default: return
    }
  }

  private who(h: FleetHarness | { local: boolean; machine: string; harness: { name: string } }): string {
    return h.local ? h.harness.name : `${h.harness.name}@${h.machine}`
  }

  private async need(change: FleetChange, entry: PairJournalEntry): Promise<void> {
    const daemonId = this.deps.pairing.pairedDaemon()
    const harness = change.event?.harness
    const question = harness?.question
    if (!daemonId || !harness || !question || question.requestId !== entry.requestId) return
    const waiting = this.deps.fleet.harnesses().filter((h) => h.harness.question)
    const index = Math.max(1, waiting.findIndex((h) => h.machineId === change.machineId && h.harness.agentId === harness.agentId) + 1)
    const result = await this.deps.triage.triage({
      daemonId, machineId: change.machineId, who: this.who({ local: change.local, machine: change.machine, harness }),
      engine: harness.engine, question, present: this.present(), index, count: Math.max(1, waiting.length),
    })
    // Answered while it was being thought about: nothing to say any more.
    const still = this.deps.fleet.find(change.machineId, harness.agentId)
    if (!this.active || still?.harness.question?.requestId !== question.requestId) return
    const id = `need:${change.machineId}:${entry.epoch}:${entry.seq}`
    this.needSays.set(`${change.machineId}\u0000${question.requestId}`, { id, result })
    this.deps.voice.say({
      id, mood: 'need', line: result.line, actions: result.actions, ttlMs: NEED_TTL_MS,
      about: { machineId: change.machineId, agentId: harness.agentId, requestId: question.requestId },
    })
    this.scheduleState()
  }

  private done(change: FleetChange, entry: PairJournalEntry): void {
    const harness = change.event?.harness
    if (!harness || entry.text === 'interrupted') return
    this.deps.voice.unsayAbout(change.machineId, harness.agentId, 'done')
    // The recap is written after the turn ends; wait a moment for it so the line says what was done.
    const key = `${change.machineId}\u0000${harness.agentId}`
    const prior = this.doneWaits.get(key)
    if (prior) clearTimeout(prior.timer)
    this.doneWaits.set(key, { change, entry, timer: setTimeout(() => this.flushDone(key, null), DONE_RECAP_WAIT_MS) })
  }

  private flushDone(key: string, recap: string | null | undefined): void {
    const wait = this.doneWaits.get(key)
    if (!wait) return
    clearTimeout(wait.timer)
    this.doneWaits.delete(key)
    const daemonId = this.deps.pairing.pairedDaemon()
    const harness = wait.change.event?.harness
    if (!daemonId || !harness || !this.active) return
    this.deps.voice.say({
      id: `done:${wait.change.machineId}:${wait.entry.epoch}:${wait.entry.seq}`, mood: 'done', actions: [], ttlMs: SAY_TTL_MS,
      line: doneLine(daemonId, { who: this.who({ local: wait.change.local, machine: wait.change.machine, harness }), recap: recap ?? null }),
      about: { machineId: wait.change.machineId, agentId: harness.agentId },
    })
  }

  private fail(change: FleetChange, entry: PairJournalEntry): void {
    const daemonId = this.deps.pairing.pairedDaemon()
    const harness = change.event?.harness
    if (!daemonId || !harness) return
    this.deps.voice.say({
      id: `fail:${change.machineId}:${entry.epoch}:${entry.seq}`, mood: 'fail', actions: [], ttlMs: SAY_TTL_MS,
      line: failLine(daemonId, { who: this.who({ local: change.local, machine: change.machine, harness }), reason: entry.text ?? '' }),
      about: { machineId: change.machineId, agentId: harness.agentId },
    })
  }

  // ── one key ───────────────────────────────────────────────────────────────────────────────────────

  /**
   * `daemon_act { requestId, id, choice }`: the person pressed a key on a line. Answered on the machine
   * that owns the harness, and only if the question on it is STILL the one the line was about — a key
   * pressed a moment late must not land on the next dialog. Always replies.
   */
  async onAct(payload: Record<string, unknown>, send: (frame: Record<string, unknown>) => void): Promise<void> {
    const requestId = str(payload.requestId, 120)
    const id = str(payload.id, 200)
    const choice = str(payload.choice, 200)
    const reply = (fields: Record<string, unknown>): void => {
      send({ type: 'daemon_act_result', payload: { requestId, id, ...fields } })
    }
    if (!this.active) { reply({ ok: false, error: 'PAIR_OFF' }); return }
    const proposals = this.deps.proposals
    if (proposals?.owns(id)) {
      const result = await proposals.act(id, choice).catch((err): Record<string, unknown> => ({ ok: false, error: err instanceof Error ? err.message.slice(0, 60) : 'FAILED' }))
      reply({ ok: result.ok === true, ...(typeof result.error === 'string' ? { error: result.error } : {}), ...(typeof result.detail === 'string' ? { detail: result.detail } : {}),
        ...(Array.isArray(result.results) ? { results: result.results } : {}) })
      return
    }
    const say = this.deps.voice.get(id)
    if (!say || !say.about.requestId) { reply({ ok: false, error: 'GONE' }); return }
    const action: DaemonAction | undefined = say.actions.find((a) => a.choice === choice || a.key === choice)
    if (!action) { reply({ ok: false, error: 'NOT_OFFERED' }); return }
    const target = this.deps.fleet.find(say.about.machineId, say.about.agentId)
    const question = target?.harness.question
    if (!target || !question || question.requestId !== say.about.requestId) {
      this.deps.voice.unsay(id, 'stale')
      reply({ ok: false, error: 'STALE_QUESTION' })
      return
    }
    // The floor, again, here: a deny-class prompt is never approved from a key, whatever a client sends.
    if (question.deny && action.key === 'y') { reply({ ok: false, error: 'DENY_CLASS' }); return }
    let result: AnswerResult
    try {
      result = target.local
        ? await this.deps.answer({ agentId: target.harness.agentId, requestId: question.requestId, choice: action.choice })
        : await this.remoteAnswer(target, question.requestId, action.choice)
    } catch (err) {
      result = { ok: false, error: err instanceof Error ? err.message.slice(0, 60) : 'FAILED' }
    }
    if (result.ok) this.deps.voice.unsay(id, 'answered')
    // The dialog on screen was not the one the line was about: nothing was typed, and the line's keys
    // can never work again. The next watch of that harness says what is on screen now.
    else if (result.error === 'STALE_QUESTION') this.deps.voice.unsay(id, 'stale')
    reply({ ok: result.ok, machineId: target.machineId, ...(result.error ? { error: result.error } : {}), ...(result.detail ? { detail: result.detail } : {}) })
  }

  private async remoteAnswer(target: FleetHarness, requestId: string, choice: string): Promise<AnswerResult> {
    const result = await this.deps.fleet.request(target.machineId, 'pair_answer', {
      agentId: target.harness.agentId, requestId, expectRequestId: requestId, choice, by: 'key',
    })
    if (typeof result.error === 'string') return { ok: false, error: result.error, ...(typeof result.detail === 'string' ? { detail: result.detail } : {}) }
    return { ok: result.ok === true }
  }

  // ── daemon_state ──────────────────────────────────────────────────────────────────────────────────

  state(): Record<string, unknown> {
    const daemonId = this.deps.pairing.pairedDaemon()
    if (!this.active || !daemonId) return { pair: null, needs: [], working: 0, failing: [], machines: [] }
    const harnesses = this.deps.fleet.harnesses()
    const needs = harnesses
      .filter((h) => h.harness.question)
      .sort((a, b) => a.harness.question!.since - b.harness.question!.since)
      .map((h) => {
        const q = h.harness.question!
        const said = this.needSays.get(`${h.machineId}\u0000${q.requestId}`)
        const live = said && this.deps.voice.get(said.id)
        return {
          machineId: h.machineId, machine: h.machine, agentId: h.harness.agentId, name: h.harness.name, engine: h.harness.engine,
          requestId: q.requestId, question: q.text, options: q.options, deny: q.deny, since: q.since,
          ...(live ? { id: said.id, line: said.result.line, actions: said.result.actions } : {}),
        }
      })
    return {
      pair: daemonId,
      needs,
      working: harnesses.filter((h) => h.harness.working && !h.harness.question).length,
      failing: harnesses.filter((h) => h.harness.failing).map((h) => ({
        machineId: h.machineId, machine: h.machine, agentId: h.harness.agentId, name: h.harness.name, reason: h.harness.failing,
      })),
      machines: this.deps.fleet.machines(),
    }
  }

  private scheduleState(): void {
    if (this.stateTimer) return
    this.stateTimer = setTimeout(() => { this.stateTimer = null; this.sendState() }, STATE_DEBOUNCE_MS)
  }

  private sendState(force = false): void {
    const payload = this.state()
    const text = JSON.stringify(payload)
    if (!force && text === this.lastState) return
    this.lastState = text
    this.deps.sendLocal({ type: 'daemon_state', payload })
  }
}
