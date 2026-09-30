/** Local host lifecycle. Session authority and coding eligibility must come from the daemon. */
import { join } from 'node:path'
import { digest } from './admission.js'
import { NativeMemoryCapture, type CaptureOutcome } from './capture.js'
import { MemoryClient } from './client.js'
import { MemoryLearner, type LearningOutcome, type MemoryInference } from './learner.js'
import { locateProject, type ProjectContext } from './project.js'
import type { Arguments, MemoryPort, Operation, Result } from './operations.js'
import type { MemoryPreferences } from './store.js'
import { MemoryError, type RecallPacket, type RecallRequest } from './types.js'

export interface MemoryHostContext {
  experimental: boolean
  watching: boolean
  /** An authenticated Harness owner or an isolated local guest, never a model account or avatar. */
  profileId: string | null
}
export interface MemoryHostSession {
  agentId: string
  engine: 'claude' | 'codex'
  sessionId: string
  workspace: string
  transcriptPath: string
  busy: boolean
  /** Positive host classification is required; a general-domain DSH is not implicitly coding. */
  coding: boolean
  liveFrom?: number
}
interface Connection extends MemoryPort { close(): Promise<void> }
interface RuntimeDeps {
  directory: string
  context(): MemoryHostContext
  sessions(): MemoryHostSession[]
  inference: MemoryInference
  create?: (profileId: string) => Connection
  locate?: (workspace: string) => Promise<ProjectContext>
  now?: () => number
  quietMs?: number
}
interface ActiveProfile {
  id: string; connection: Connection; port: MemoryPort; capture: NativeMemoryCapture; learner: MemoryLearner
  preferences: MemoryPreferences; projects: Map<string, { projectId: string; checkedAt: number }>
  learning: Promise<LearningOutcome> | null; learningStatus: LearningOutcome | null; captureStatus: CaptureOutcome | null
  maintainedAt: number
  ready: boolean
}
export interface MemoryRuntimeStatus {
  state: 'off' | 'waiting_for_identity' | 'ready' | 'unavailable'
  preferences?: MemoryPreferences
  learning?: LearningOutcome | null
  capture?: CaptureOutcome | null
  reason?: string
}

/** Capture remains active while the selected model is unavailable. Inference waits for quiet. */
export class CodingMemoryRuntime {
  private active: ActiveProfile | null = null
  private running: Promise<void> | null = null
  private timer: NodeJS.Timeout | null = null
  private stopped = false
  private offset = 0
  private lastActivityAt: number
  private failure: string | null = null
  private readonly now: () => number

  constructor(private readonly deps: RuntimeDeps) {
    this.now = deps.now ?? Date.now
    this.lastActivityAt = this.now()
  }

  start(): void {
    if (this.stopped || this.timer) return
    this.timer = setInterval(() => { void this.tick() }, 2_000)
    this.timer.unref()
    void this.tick()
  }

  /** Call on actual foreground activity, not periodic discovery/model metadata updates. */
  activity(): void { this.lastActivityAt = this.now(); this.active?.learner.cancel() }

  tick(): Promise<void> {
    if (this.active && !this.authorized(this.active)) this.active.learner.cancel()
    if (this.running) return this.running
    if (this.stopped) return Promise.resolve()
    this.running = this.update().catch(error => { this.failure = reason(error) }).finally(() => { this.running = null })
    return this.running
  }

  status(): MemoryRuntimeStatus {
    const context = this.deps.context()
    if (this.stopped || !context.experimental || !context.watching) return { state: 'off' }
    if (!context.profileId) return { state: 'waiting_for_identity' }
    if (!this.active?.ready || !this.authorized(this.active)) return { state: 'unavailable', reason: this.failure ?? 'starting' }
    return { state: this.failure ? 'unavailable' : 'ready', ...(this.failure ? { reason: this.failure } : {}),
      preferences: { ...this.active.preferences }, learning: this.active.learningStatus, capture: this.active.captureStatus }
  }

  /** Only the authenticated host's explicit user settings handler calls this method. */
  async configure(value: MemoryPreferences): Promise<void> {
    if (typeof value.learn !== 'boolean' || typeof value.recall !== 'boolean') throw new MemoryError('invalid_input')
    const active = this.requireActive()
    active.preferences = { learn: value.learn, recall: value.recall }
    if (!value.learn) active.learner.cancel()
    await active.port.request('setPreferences', [active.preferences])
  }

  async setSessionIncluded(agentId: string, included: boolean): Promise<void> {
    const active = this.requireActive()
    const session = this.session(agentId)
    if (!session) throw new MemoryError('session_unavailable')
    if (!included) active.learner.cancel()
    await active.port.request('setSessionIncluded', [session.engine, session.sessionId, included])
  }

  async setProjectIncluded(agentId: string, included: boolean): Promise<void> {
    const active = this.requireActive()
    const session = this.session(agentId)
    const project = session && active.projects.get(session.workspace)
    if (!project) throw new MemoryError('project_unavailable')
    if (!included) active.learner.cancel()
    await active.port.request('setProjectIncluded', [project.projectId, included])
  }

  /** Callers identify their process-owned agent; they never supply profile or project authority. */
  async recall(agentId: string, request: RecallRequest): Promise<RecallPacket> {
    const deadline = performance.now() + 200
    const remaining = (): number => Math.max(1, deadline - performance.now())
    try {
      const active = this.requireActive()
      if (!active.preferences.recall) return empty('off')
      const session = this.session(agentId)
      if (!session) return empty('denied')
      // Recall must not wait for Git or SQLite startup on the user's input path. Background capture
      // primes the identity cache; the first unprimed request safely gets no additional context.
      const project = active.projects.get(session.workspace)
      if (!project || this.now() - project.checkedAt > 60_000) return empty('unavailable')
      const policy = await active.port.request('capturePolicy', [project.projectId, session.engine, session.sessionId], 50)
      if (!policy.included) return empty('denied')
      const packet = await active.port.request('recall', [request,
        { profileId: active.id, projectIds: [project.projectId], includeProfile: true }], remaining())
      const current = await active.port.request('capturePolicy', [project.projectId, session.engine, session.sessionId], remaining())
      if (performance.now() >= deadline) return empty('timeout')
      if (!current.included || current.generation !== policy.generation || !active.preferences.recall || !this.sameSession(session)) return empty('denied')
      return packet
    } catch (error) { return empty(error instanceof MemoryError && error.code === 'memory_deadline' ? 'timeout' : 'unavailable') }
  }

  async close(): Promise<void> {
    this.stopped = true
    if (this.timer) clearInterval(this.timer)
    this.timer = null
    this.active?.learner.cancel()
    await this.running
    await this.detach()
  }

  /** Stops the host timer while the experiment is off; start() may resume this instance later. */
  async pause(): Promise<void> {
    if (this.timer) clearInterval(this.timer)
    this.timer = null
    this.active?.learner.cancel()
    await this.running
    await this.detach()
  }

  private authorized(active: ActiveProfile): boolean {
    const context = this.deps.context()
    return !this.stopped && context.experimental && context.watching && context.profileId === active.id
  }

  private requireActive(): ActiveProfile {
    if (!this.active?.ready || !this.authorized(this.active)) throw new MemoryError('memory_unavailable')
    return this.active
  }

  private session(agentId: string): MemoryHostSession | undefined {
    return this.deps.sessions().find(session => session.agentId === agentId && session.coding && session.sessionId)
  }

  private sameSession(session: MemoryHostSession): boolean {
    const current = this.session(session.agentId)
    return !!current && current.engine === session.engine && current.sessionId === session.sessionId
      && current.workspace === session.workspace && current.transcriptPath === session.transcriptPath && current.liveFrom === session.liveFrom
  }

  private async detach(): Promise<void> {
    const old = this.active
    this.active = null
    if (!old) return
    old.learner.cancel()
    // Set effective controls off without overwriting the owner's requested preferences. Already
    // posted learning results fail their generation check; late calls also fail the bound port.
    await old.connection.request('setControls', [{ learn: false, recall: false }]).catch(() => {})
    await old.connection.close()
  }

  private async update(): Promise<void> {
    if (this.active && !this.authorized(this.active)) await this.detach()
    const context = this.deps.context()
    if (this.stopped || !context.experimental || !context.watching || !context.profileId) return
    if (!/^[A-Za-z0-9_.:-]{1,200}$/.test(context.profileId)) throw new MemoryError('invalid_profile')
    if (!this.active) {
      const profileId = context.profileId
      const connection = this.deps.create?.(profileId)
        ?? new MemoryClient({ directory: join(this.deps.directory, digest(['profile', profileId])), profileId })
      const host = this
      const port: MemoryPort = { async request<K extends Operation>(operation: K, args: Arguments<K>, timeoutMs?: number): Promise<Result<K>> {
        if (host.active !== active || !host.authorized(active)) throw new MemoryError('owner_changed')
        const result = await connection.request(operation, args, timeoutMs)
        if (host.active !== active || !host.authorized(active)) throw new MemoryError('owner_changed')
        return result
      } }
      const active: ActiveProfile = { id: profileId, connection, port, projects: new Map(), learning: null, learningStatus: null,
        captureStatus: null, maintainedAt: -Infinity, ready: false, preferences: { learn: false, recall: false },
        capture: new NativeMemoryCapture(port, this.now), learner: new MemoryLearner(port, this.deps.inference) }
      this.active = active
      try {
        // A new daemon lifetime does not backfill conversations from when this host was absent.
        await active.port.request('setControls', [{ learn: false, recall: false }])
        active.preferences = await active.port.request('preferences', [])
        await active.port.request('setControls', [active.preferences])
        active.ready = true
      } catch (error) { await this.detach(); throw error }
    }
    const active = this.requireActive()
    this.failure = null
    if (this.now() - active.maintainedAt >= 60_000) {
      await active.port.request('maintain', [])
      active.maintainedAt = this.now()
    }
    const sessions = this.deps.sessions().filter(session => session.coding && session.sessionId)
    if (sessions.some(session => session.busy)) this.activity()
    // Bound per-tick filesystem work and share turns among concurrent sessions.
    const count = Math.min(8, sessions.length)
    for (let index = 0; index < count; index++) {
      const session = sessions[(this.offset + index) % sessions.length]
      try {
        let project = active.projects.get(session.workspace)
        if (!project || this.now() - project.checkedAt > 60_000) {
          const located = await (this.deps.locate ?? locateProject)(session.workspace)
          if (!this.sameSession(session)) continue
          const projectId = await active.port.request('projectForLocator', [located.locator])
          project = { projectId, checkedAt: this.now() }
          active.projects.set(session.workspace, project)
          if (active.projects.size > 128) active.projects.delete(active.projects.keys().next().value!)
        }
        if (!this.sameSession(session)) continue
        if (active.preferences.learn) active.captureStatus = await active.capture.poll({ ...session,
          profileId: active.id, projectId: project.projectId })
      } catch (error) { active.captureStatus = { state: 'unavailable', sources: 0, reason: reason(error) } }
    }
    this.offset = sessions.length ? (this.offset + count) % sessions.length : 0
    if (!this.authorized(active) || !active.preferences.learn || active.learning
      || this.now() - this.lastActivityAt < (this.deps.quietMs ?? 15_000)) return
    active.learning = active.learner.tick()
    void active.learning.then(outcome => { if (this.active === active) active.learningStatus = outcome })
      .catch(error => { if (this.active === active) active.learningStatus = { state: 'failed', reason: reason(error) } })
      .finally(() => { active.learning = null })
  }
}

function reason(error: unknown): string { return error instanceof MemoryError ? error.code : 'memory_unavailable' }
function empty(status: RecallPacket['status']): RecallPacket { return { status, items: [], text: '', estimatedTokens: 0 } }
