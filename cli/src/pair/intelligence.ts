/** The collection's background reasoning uses its DSH's observed model, never the voice router. */
import { mkdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs'
import { dirname } from 'node:path'
import { createHash } from 'node:crypto'
import { parseRuntimeProfile, type RuntimeProfile } from '../lib/runtimeProfile.js'
import { runClaudeOneShot, runCodexOneShot, type OneShotOptions } from '../lib/oneshot.js'
import type { PairOneShot } from './triage.js'
import type { StartupProfile } from './startupProfile.js'
import { runCodexMemoryInference } from '../memory/inference.js'
import { runClaudeMemoryInference } from '../memory/claudeInference.js'
import { memoryAccountIdentity } from '../memory/account.js'
import type { MemoryInference, MemoryInferenceRunOptions } from '../memory/learner.js'
import type { MemoryInferenceOptions } from '../memory/inferenceProcess.js'
import { MemoryError } from '../memory/types.js'

export interface CompanionRuntime {
  agentId: string
  sessionId: string | null
  engine: string
  profile: string | null
  stopped: boolean
  codexHome?: string | null
  customProvider?: boolean
  /** Opaque observed account identity, when supplied by the native host. */
  accountKey?: string | null
  startup?: StartupProfile | null
}

export interface IntelligenceStatus {
  state: 'off' | 'unopened' | 'waiting' | 'unsupported' | 'ready'
  agentId?: string
  engine?: string
  model?: string
  effort?: string
  contextKey?: string
}

interface IntelligenceDeps {
  enabled: () => boolean
  current: () => CompanionRuntime | null
  directory: string
  stateFile: string
  run?: (engine: 'claude' | 'codex', options: MemoryInferenceOptions) => Promise<{ text: string }>
  accountIdentity?: (runtime: CompanionRuntime) => Promise<string | null>
}

export class CompanionIntelligence {
  private saved: Record<string, { sessionId: string; profile: string }> | null = null
  private readonly calls = new Set<AbortController>()

  constructor(private readonly deps: IntelligenceDeps) {}

  status(): IntelligenceStatus { return this.target().status }
  async extractionStatus(): Promise<IntelligenceStatus> { return (await this.extractionTarget()).status }
  ready(): boolean { return this.status().state === 'ready' }

  /** Abort on experimental-off/account changes. No worker becomes a discoverable agent. */
  cancel(): void { for (const call of this.calls) call.abort(); this.calls.clear() }

  readonly run: PairOneShot = (prompt, opts) => this.execute(prompt, opts, false)
  readonly extract: MemoryInference['run'] = (prompt, opts) => this.execute(prompt, opts, true)

  private async execute(prompt: string, opts: Parameters<PairOneShot>[1] | MemoryInferenceRunOptions, extraction: boolean): Promise<string | null> {
    // Register before the account lookup: cancel() must cover startup as well as a running child.
    const controller = new AbortController()
    const abort = (): void => controller.abort()
    opts.signal?.addEventListener('abort', abort, { once: true })
    if (opts.signal?.aborted) controller.abort()
    this.calls.add(controller)
    try {
      const target = extraction ? await this.extractionTarget() : this.target()
      if (controller.signal.aborted || !target.profile || !target.runtime || target.status.state !== 'ready') return null
      if (extraction && (!('contextKey' in opts) || opts.contextKey !== target.status.contextKey)) throw new MemoryError('inference_context_changed')
      const { runtime, profile } = target
      const engine = runtime.engine as 'claude' | 'codex'
      const assertAuthorized = (): void => {
        if (controller.signal.aborted) throw new MemoryError('inference_cancelled')
        if ('assertAuthorized' in opts) opts.assertAuthorized?.()
        if (this.target().status.contextKey !== target.runtimeContextKey) throw new MemoryError('inference_context_changed')
      }
      if (extraction) assertAuthorized()
      mkdirSync(this.deps.directory, { recursive: true, mode: 0o700 })
      const options: MemoryInferenceOptions = {
        prompt, cwd: this.deps.directory, model: profile.model,
        ...(profile.effort !== 'auto' ? { effort: profile.effort as OneShotOptions['effort'] } : {}),
        ...(engine === 'codex' && runtime.codexHome ? { codexHome: runtime.codexHome } : {}),
        timeoutMs: opts.timeoutMs, signal: controller.signal,
        ...(extraction ? { assertAuthorized, beforeRun: async () => {
          const current = await this.extractionTarget()
          if (current.status.state !== 'ready' || current.status.contextKey !== target.status.contextKey) throw new MemoryError('inference_context_changed')
        } } : {}),
      }
      const run = this.deps.run ?? ((engine, options) => engine === 'claude' ? extraction ? runClaudeMemoryInference(options) : runClaudeOneShot(options)
        : extraction ? runCodexMemoryInference(options) : runCodexOneShot(options))
      const result = await run(engine, options)
      const current = extraction ? await this.extractionTarget() : this.target()
      // A result from an old model, account, or conversation is never accepted under the new one.
      if (controller.signal.aborted || current.status.state !== 'ready' ||
        current.runtime?.sessionId !== runtime.sessionId || current.profile?.id !== profile.id ||
        (!runtime.sessionId && current.runtime?.startup?.processKey !== runtime.startup?.processKey) ||
        current.runtime?.codexHome !== runtime.codexHome || current.status.contextKey !== target.status.contextKey) return null
      return result.text
    } finally {
      opts.signal?.removeEventListener('abort', abort)
      this.calls.delete(controller)
    }
  }

  private async extractionTarget(): Promise<ReturnType<CompanionIntelligence['target']>> {
    const target = this.target()
    if (target.status.state !== 'ready' || !target.runtime) return target
    const identity = target.runtime.accountKey ?? await (this.deps.accountIdentity ?? memoryAccountIdentity)(target.runtime)
    const current = this.target()
    if (current.status.contextKey !== target.status.contextKey || !identity) return { status: { ...current.status, state: 'waiting' } }
    return { ...target, status: { ...target.status,
      contextKey: createHash('sha256').update(JSON.stringify([target.status.contextKey, identity])).digest('hex') } }
  }

  private target(): { status: IntelligenceStatus; runtimeContextKey?: string; runtime?: CompanionRuntime; profile?: RuntimeProfile } {
    if (!this.deps.enabled()) return { status: { state: 'off' } }
    const runtime = this.deps.current()
    if (!runtime) return { status: { state: 'unopened' } }
    const status: IntelligenceStatus = { state: 'waiting', agentId: runtime.agentId, engine: runtime.engine }
    // Custom provider credentials must not silently fall back to the local subscription.
    if (!['claude', 'codex'].includes(runtime.engine) || runtime.customProvider) return { status: { ...status, state: 'unsupported' } }
    if (!runtime.sessionId && (runtime.stopped || !runtime.startup)) return { status }
    this.load()
    const cached = this.saved![runtime.agentId]
    const value = runtime.sessionId
      ? runtime.profile ?? (runtime.stopped && cached?.sessionId === runtime.sessionId ? cached.profile : null)
      : runtime.startup?.profile
    const profile = parseRuntimeProfile(value)
    const efforts = runtime.engine === 'claude'
      ? ['auto', 'low', 'medium', 'high', 'xhigh', 'max', 'ultracode']
      : ['auto', 'low', 'medium', 'high', 'xhigh', 'max', 'ultra']
    if (!profile || profile.sessionId !== runtime.agentId || profile.engine !== runtime.engine || !efforts.includes(profile.effort)) return { status }
    // Pre-conversation readiness is live evidence, never a durable substitute for a conversation ID.
    if (runtime.sessionId && (cached?.profile !== profile.id || cached.sessionId !== runtime.sessionId)) {
      this.saved![runtime.agentId] = { sessionId: runtime.sessionId, profile: profile.id }
      mkdirSync(dirname(this.deps.stateFile), { recursive: true, mode: 0o700 })
      const tmp = `${this.deps.stateFile}.tmp`
      writeFileSync(tmp, JSON.stringify(this.saved), { mode: 0o600 })
      renameSync(tmp, this.deps.stateFile)
    }
    const contextKey = createHash('sha256').update(JSON.stringify([runtime.agentId, runtime.sessionId,
      runtime.sessionId ? null : runtime.startup?.processKey, runtime.engine, profile.id, runtime.codexHome ?? null, runtime.accountKey ?? null])).digest('hex')
    return { runtime, profile, runtimeContextKey: contextKey, status: { ...status, state: 'ready', model: profile.model, effort: profile.effort, contextKey } }
  }

  private load(): void {
    if (this.saved) return
    this.saved = Object.create(null) as Record<string, { sessionId: string; profile: string }>
    try {
      const raw: unknown = JSON.parse(readFileSync(this.deps.stateFile, 'utf8'))
      if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return
      for (const [id, value] of Object.entries(raw)) {
        if (!value || typeof value !== 'object') continue
        const row = value as { sessionId?: unknown; profile?: unknown }
        if (typeof row.sessionId === 'string' && typeof row.profile === 'string' && parseRuntimeProfile(row.profile)?.sessionId === id) {
          this.saved[id] = { sessionId: row.sessionId, profile: row.profile }
        }
      }
    } catch { /* No selected model has been observed yet. */ }
  }
}
