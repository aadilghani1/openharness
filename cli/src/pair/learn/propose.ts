/**
 * PROPOSE, and the person's answer (daemons/LEARNING.md). The paired daemon's learner, in every harnessd:
 * it keeps the signals this machine noticed, distills them while nothing is working (or after an hour
 * regardless), and when you are at this computer says ONE line for a pending lesson:
 *
 *   [y/n/s] teach your agents "run-migrations-safely"? you corrected codex.
 *
 *   y  approve: the lesson moves to skills/ (or notes/) with one commit, is published (publish.ts), the
 *      daemon gets the credit in the journal (`learned`), and it says so.
 *   n  skip: gone, and its hash and signal are remembered so it is never proposed again.
 *   s  show: the lesson's text in a `daemon_brief` frame, with [y/n] still working for a minute.
 *
 * When it may speak: at most ONE lesson proposal an hour; never while a `need` line is showing; never
 * about the pane you are looking at; never at autonomy `watch`; only while you are here. An unanswered
 * proposal stays in daemon_state `asks` for ten minutes and comes back after a day. Nothing is taught
 * without a yes: a key on the line, or `harness pair lessons approve <id>` confirmed at a terminal.
 */
import type { Autonomy } from '../floor.js'
import { DISPLAY_MS, keysPrefix } from '../voice.js'
import { statusText, str, type DaemonAction, type DaemonMood, type DaemonSay } from '../protocol.js'
import type { Distilled } from './distill.js'
import { findProject, publishNote, unpublishNote } from './publish.js'
import { NO_GIT_NOTE, type LessonRecord, type LessonStore } from './store.js'
import type { Signal } from './types.js'

export const LESSON_PROPOSAL_GAP_MS = 60 * 60_000
export const LESSON_REPROPOSE_MS = 24 * 60 * 60_000
export const LESSON_ASK_TTL_MS = 10 * 60_000
export const LESSON_SHOW_KEYS_MS = 60_000
export const DISTILL_EVERY_MS = 10 * 60_000
export const DISTILL_BATCH = 3
export const SIGNAL_QUEUE_MAX = 20
export const SIGNAL_MAX_WAIT_MS = 60 * 60_000

type Result = Record<string, unknown>
const fail = (error: string, detail?: string): Result => ({ ok: false, error, ...(detail ? { detail } : {}) })

const TEACH: DaemonAction = { key: 'y', label: 'teach', choice: 'y' }
const SKIP: DaemonAction = { key: 'n', label: 'skip', choice: 'n' }
const SHOW: DaemonAction = { key: 's', label: 'show', choice: 's' }

export interface LearnerDeps {
  store: LessonStore
  distiller: { distill: (signal: Signal) => Promise<Distilled> }
  pairedDaemon: () => string | null
  autonomy: () => Autonomy
  voice: { say: (say: DaemonSay) => boolean; unsay: (id: string, reason: string) => boolean; showing: (mood: DaemonMood) => boolean }
  /** Loopback only (backendSocket.sendLocal). */
  sendLocal: (frame: Record<string, unknown>) => void
  /** A person is at this computer and the brain is thinking. */
  present: () => boolean
  /** The person is looking at this harness (on this machine) right now. */
  focused: (agentId: string) => boolean
  /** Something on this machine is working: distilling waits for a quiet moment. */
  busy?: () => boolean
  /** The folders harnesses run in: a note's project is found among them by its hash. */
  projects: () => string[]
  /** The zoo's credit: a journal entry `learned` with the daemon's id (pair/sensor.ts learned). */
  learned?: (entry: { daemon: string; lesson: LessonRecord }) => void
  /**
   * TODO(zoo): bond xp for the daemon that found the lesson. The backend has no op for it yet; cli.ts
   * leaves this a no-op hook, and the journal entry above is the record a later op can count from.
   */
  credit?: (daemonId: string, lesson: LessonRecord) => void
  machineId: () => string
  /** daemon_state `asks` changed. */
  changed?: () => void
  /** This computer's home folder, shown as `~`. */
  home?: string | null
  now: () => number
  log?: (line: string) => void
}

interface Live { id: string; lessonId: string; at: number; until: number }

export class PairLearner {
  private readonly queue: Signal[] = []
  private live: Live | null = null
  private lastDistill = -Infinity
  private ticking = false
  private seq = 0

  constructor(private readonly deps: LearnerDeps) {}

  // ── notice → distill ──────────────────────────────────────────────────────────────────────────────

  /** A signal this machine noticed (signals.ts). Kept until a quiet moment; nothing happens at once. */
  signal(signal: Signal): void {
    if (!this.deps.pairedDaemon()) return
    if (this.queue.some((s) => s.key === signal.key)) return
    this.queue.push(signal)
    if (this.queue.length > SIGNAL_QUEUE_MAX) this.queue.shift()
  }

  get queued(): number { return this.queue.length }

  /** Distill a batch when it is quiet, then maybe propose. Called on a timer; safe to call any time. */
  async tick(): Promise<void> {
    if (this.ticking) return
    this.ticking = true
    try {
      await this.distillBatch()
      this.propose()
    } finally {
      this.ticking = false
    }
  }

  private async distillBatch(): Promise<void> {
    const daemon = this.deps.pairedDaemon()
    const now = this.deps.now()
    if (!daemon || !this.queue.length || now - this.lastDistill < DISTILL_EVERY_MS) return
    const waited = now - this.queue[0]!.at
    if (this.deps.busy?.() && waited < SIGNAL_MAX_WAIT_MS) return
    this.lastDistill = now
    for (const signal of this.queue.splice(0, DISTILL_BATCH)) {
      const result = await this.deps.distiller.distill(signal).catch((): Distilled => ({ lesson: null, why: 'failed' }))
      if (!result.lesson) { this.deps.log?.(`[learn] ${signal.kind} · nothing (${result.why}${result.refusal ? `: ${result.refusal}` : ''})`); continue }
      const added = this.deps.store.add({ lesson: result.lesson, signal, learnedBy: daemon, source: result.source })
      this.deps.log?.(`[learn] ${signal.kind} · ${added.ok ? `pending ${added.record.id} "${added.record.name}"` : added.error}`)
    }
  }

  // ── propose ───────────────────────────────────────────────────────────────────────────────────────

  /** Say one line for a pending lesson, if every rule allows it now. True when it went out. */
  propose(): boolean {
    const now = this.deps.now()
    const daemon = this.deps.pairedDaemon()
    if (!daemon || this.deps.autonomy() === 'watch' || !this.deps.present()) return false
    if (this.current()) return false
    const last = this.deps.store.lastProposedAt()
    if (last !== null && now - last < LESSON_PROPOSAL_GAP_MS) return false
    if (this.deps.voice.showing('need')) return false
    const lesson = this.deps.store.pending().find((r) => {
      const at = this.deps.store.proposedAt(r.id)
      return (at === null || now - at >= LESSON_REPROPOSE_MS) && !r.from.some((f) => this.deps.focused(f.agentId))
    })
    if (!lesson) return false
    const id = `lesson:${lesson.id}:${++this.seq}`
    const said = this.deps.voice.say({
      id, about: { machineId: this.deps.machineId(), agentId: lesson.from[0]?.agentId ?? '' }, mood: 'ask',
      line: this.line(lesson), actions: [TEACH, SKIP, SHOW], ttlMs: DISPLAY_MS,
    })
    if (!said) return false
    this.deps.store.markProposed(lesson.id, now)
    this.live = { id, lessonId: lesson.id, at: now, until: now + LESSON_ASK_TTL_MS }
    this.deps.changed?.()
    return true
  }

  /** `[y/n/s] teach your agents "name"? you corrected codex.` */
  line(lesson: LessonRecord): string {
    const engines = [...new Set(lesson.from.map((f) => f.engine))]
    const who = engines.length > 1 ? `${engines.slice(0, -1).join(', ')} and ${engines[engines.length - 1]}` : engines[0] ?? 'an agent'
    const where = lesson.projectName ?? 'this project'
    const why = lesson.signal.kind === 'correction' ? `you corrected ${who}.`
      : lesson.signal.kind === 'repeat-failure' ? `${who} hit the same failure.`
        : `the same steps, ${new Set(lesson.from.map((f) => `${f.agentId}:${f.session}:${f.turn}`)).size} times in ${where}.`
    const what = lesson.kind === 'skill' ? `teach your agents "${lesson.name}"?` : `add a note to ${where}'s AGENTS.md?`
    return statusText(`${keysPrefix([TEACH, SKIP, SHOW])}${what} ${why}`, 140)
  }

  private current(): Live | null {
    if (this.live && this.deps.now() >= this.live.until) this.live = null
    if (this.live && !this.deps.store.pending().some((r) => r.id === this.live!.lessonId)) this.live = null
    return this.live
  }

  // ── the brain's proposals interface ───────────────────────────────────────────────────────────────

  owns(id: string): boolean { return id.startsWith('lesson:') }

  /** For daemon_state `asks`: the one lesson waiting for a key, while it waits. */
  pending(): Array<{ id: string; line: string; actions: DaemonAction[] }> {
    const live = this.current()
    const lesson = live ? this.deps.store.pending().find((r) => r.id === live.lessonId) : null
    return live && lesson ? [{ id: live.id, line: this.line(lesson), actions: [TEACH, SKIP, SHOW] }] : []
  }

  /** A key on the line (daemon_act): y teach, n skip, s show. Always answers. */
  async act(id: string, choice: string): Promise<Result> {
    const live = this.current()
    if (!live || live.id !== id) return fail('GONE')
    const key = [TEACH, SKIP, SHOW].find((a) => a.key === choice || a.choice === choice || a.label === choice)?.key
    if (!key) return fail('NOT_OFFERED')
    if (key === 's') return this.show(live)
    if (key === 'y' && this.deps.autonomy() === 'watch') return fail('AUTONOMY_WATCH')
    this.live = null
    this.deps.voice.unsay(id, key === 'y' ? 'answered' : 'declined')
    this.deps.changed?.()
    return key === 'y' ? this.approve(live.lessonId, 'key') : this.skip(live.lessonId)
  }

  private show(live: Live): Result {
    const lesson = this.deps.store.pending().find((r) => r.id === live.lessonId)
    if (!lesson) return fail('GONE')
    const text = this.deps.store.text(lesson)
    // The keys keep working while the person reads it.
    live.until = Math.max(live.until, this.deps.now() + LESSON_SHOW_KEYS_MS)
    const keys = [TEACH, SKIP]
    this.deps.sendLocal({ type: 'daemon_brief', payload: {
      desk: 'local', line: statusText(`lesson "${lesson.name}", pending`, 140),
      items: [{ id: live.id, kind: 'lesson', machineId: this.deps.machineId(), line: statusText(`${keysPrefix(keys)}${this.line(lesson).replace(/^\[[a-z/]+\]\s*/, '')}`, 140), actions: keys, text }],
    } })
    return { ok: true, shown: true, lesson: text }
  }

  // ── what a key and the CLI both do ────────────────────────────────────────────────────────────────

  /**
   * Approve a pending lesson (or, for an approved note, publish it again — `create` makes an AGENTS.md when
   * the project has none, because the person asked for exactly that). Credits the daemon that found it.
   */
  approve(id: string, by: 'key' | 'cli', opts: { create?: boolean } = {}): Result {
    const already = this.deps.store.approved().find((r) => r.id === id)
    let record: LessonRecord
    let commit: string | null = null
    let note: string | undefined
    if (already) {
      if (already.kind !== 'note') return fail('NOT_PENDING', `lesson ${id} is approved`)
      record = already
    } else {
      const approved = this.deps.store.approve(id, by)
      if (!approved.ok) return approved
      record = approved.record
      commit = approved.commit
      note = approved.note
      this.deps.learned?.({ daemon: record.learnedBy, lesson: record })
      this.deps.credit?.(record.learnedBy, record)
      if (this.live?.lessonId === id) { this.deps.voice.unsay(this.live.id, 'answered'); this.live = null; this.deps.changed?.() }
    }
    const published = this.publish(record, opts)
    const where = record.projectName ?? 'the project'
    const said = record.kind === 'skill' ? `learned "${record.name}". harness sessions on every engine will load it.`
      : published.ok ? `noted in ${where}'s ${String(published.file).split('/').pop()}.`
        : `kept "${record.name}". ${where} has no AGENTS.md: harness pair lessons approve ${record.id} --create writes one.`
    if (by === 'key' || this.deps.present()) {
      this.deps.voice.say({ id: `learned:${record.id}:${++this.seq}`, about: { machineId: this.deps.machineId(), agentId: '' }, mood: 'say', line: statusText(said, 140), actions: [], ttlMs: DISPLAY_MS })
    }
    return {
      ok: true, id: record.id, learned: record.name, kind: record.kind, commit, line: said,
      published: record.kind === 'skill' ? { via: 'runtime', dir: this.tilde(this.deps.store.skillsDir) } : published,
      ...(note ? { note } : {}),
    }
  }

  private publish(record: LessonRecord, opts: { create?: boolean }): Result {
    if (record.kind !== 'note') return { ok: true, via: 'runtime' }
    const project = findProject(record.project, this.deps.projects())
    if (!project) return fail('PROJECT_UNKNOWN', 'no harness here runs in that project now; approve it again from one that does')
    const result = publishNote(project, record, opts)
    return result.ok ? { ok: true, file: this.tilde(result.file), ...(result.created ? { created: true } : {}) } : { ...result }
  }

  skip(id: string): Result {
    const skipped = this.deps.store.skip(id)
    if (!skipped.ok) return skipped
    if (this.live?.lessonId === id) { this.deps.voice.unsay(this.live.id, 'declined'); this.live = null; this.deps.changed?.() }
    return { ok: true, id, skipped: skipped.record.name }
  }

  /** `git revert` of the lesson's commit, and unpublished: its note taken out of the project's block. */
  revert(id: string): Result {
    const reverted = this.deps.store.revert(id)
    if (!reverted.ok) return reverted
    let unpublished: Result = { via: 'runtime' }
    if (reverted.record.kind === 'note') {
      const project = findProject(reverted.record.project, this.deps.projects())
      const result = project ? unpublishNote(project, id) : { ok: true as const, file: null }
      unpublished = result.ok ? { file: result.file ? this.tilde(result.file) : null } : { ...result }
    }
    return { ok: true, id, reverted: reverted.record.name, commit: reverted.commit, unpublished, ...(reverted.note ? { note: reverted.note } : {}) }
  }

  // ── `harness pair lessons [list|show|approve|skip|revert]` ────────────────────────────────────────

  async local(payload: Record<string, unknown>): Promise<Result> {
    const action = str(payload.action, 20) || 'list'
    const id = str(payload.id, 40)
    const store = this.deps.store
    if (action === 'list') {
      return {
        ok: true, root: this.tilde(store.root), git: store.git, ...(store.git ? {} : { note: NO_GIT_NOTE }),
        lessons: store.list().map((r) => this.summary(r)),
      }
    }
    if (!id) return fail('MISSING_ID', `lessons ${action} needs a lesson id (harness pair lessons list)`)
    switch (action) {
      case 'show': {
        const record = store.get(id)
        return record ? { ok: true, lesson: this.summary(record), text: store.text(record) } : fail('NOT_FOUND', `no lesson ${id}`)
      }
      case 'approve':
        // The CLI asks at a terminal and says so; a caller that did not is not the person saying yes.
        if (payload.confirmed !== true) return fail('CONFIRM', 'approve asks you at a terminal, or press [y] on the daemon\'s line')
        return this.approve(id, 'cli', { create: payload.create === true })
      case 'skip': return this.skip(id)
      case 'revert': return this.revert(id)
      default: return fail('UNKNOWN_ACTION', `lessons has no "${action}" (list, show, approve, skip, revert)`)
    }
  }

  private summary(r: LessonRecord): Result {
    return {
      id: r.id, kind: r.kind, name: r.name, status: r.status, description: r.description, learnedBy: r.learnedBy,
      signal: r.signal.kind, project: r.projectName, source: r.source, created: new Date(r.created).toISOString(),
      ...(r.approved ? { approved: r.approved } : {}), ...(r.commit ? { commit: r.commit } : {}),
      from: r.from.map((f) => `${f.engine}@${f.machine} turn ${f.turn}`),
    }
  }

  private tilde(path: string): string {
    const home = this.deps.home?.replace(/\/+$/, '')
    return home && (path === home || path.startsWith(`${home}/`)) ? `~${path.slice(home.length)}` : path
  }
}

/** The brain takes one set of proposals: the control interface's (`ask:`) and the learner's (`lesson:`). */
export function joinProposals(...sources: Array<{ owns: (id: string) => boolean; act: (id: string, choice: string) => Promise<Result>; pending: () => Array<{ id: string; line: string; actions: DaemonAction[] }> }>) {
  return {
    owns: (id: string): boolean => sources.some((source) => source.owns(id)),
    act: (id: string, choice: string): Promise<Result> => sources.find((source) => source.owns(id))?.act(id, choice) ?? Promise.resolve(fail('GONE')),
    pending: (): Array<{ id: string; line: string; actions: DaemonAction[] }> => sources.flatMap((source) => source.pending()),
  }
}
