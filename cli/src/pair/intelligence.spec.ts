import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { existsSync, mkdtempSync, readFileSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { CompanionIntelligence, type CompanionRuntime } from './intelligence.js'
import { encodeRuntimeProfile } from '../lib/runtimeProfile.js'
import type { OneShotOptions } from '../lib/oneshot.js'

let directory: string
beforeEach(() => { directory = mkdtempSync(join(tmpdir(), 'collection-model-')) })
afterEach(() => { rmSync(directory, { recursive: true, force: true }) })

function world() {
  let enabled = true
  let runtime: CompanionRuntime | null = { agentId: 'collection', sessionId: 'session-1', engine: 'claude', stopped: false,
    profile: encodeRuntimeProfile({ sessionId: 'collection', engine: 'claude', model: 'opus', effort: 'high' }) }
  const run = vi.fn<(engine: 'claude' | 'codex', options: OneShotOptions) => Promise<{ text: string }>>(async () => ({ text: '{"lesson":null}' }))
  const deps = { enabled: () => enabled, current: () => runtime, run, directory, stateFile: join(directory, 'model.json') }
  return { brain: new CompanionIntelligence(deps), deps, run,
    off: () => { enabled = false }, set: (next: CompanionRuntime | null) => { runtime = next }, get: () => runtime! }
}

describe('the collection DSH supplies its intelligence', () => {
  it('inherits the exact observed engine, model, effort and changes with the model picker', async () => {
    const w = world()
    expect(w.brain.status()).toMatchObject({ state: 'ready', model: 'opus', effort: 'high' })
    await w.brain.run('review evidence', { timeoutMs: 1000, signal: new AbortController().signal })
    expect(w.run).toHaveBeenLastCalledWith('claude', expect.objectContaining({ model: 'opus', effort: 'high', prompt: 'review evidence' }))
    w.set({ ...w.get(), engine: 'codex', codexHome: '/profiles/collection', profile: encodeRuntimeProfile({ sessionId: 'collection', engine: 'codex', model: 'gpt-test', effort: 'xhigh' }) })
    await w.brain.run('more evidence', { timeoutMs: 1000, signal: new AbortController().signal })
    expect(w.run).toHaveBeenLastCalledWith('codex', expect.objectContaining({ model: 'gpt-test', effort: 'xhigh', codexHome: '/profiles/collection' }))
  })

  it('keeps an observed profile across idle pause and daemon restart, only for the same conversation', () => {
    const w = world()
    w.brain.status()
    w.set({ ...w.get(), stopped: true, profile: null })
    expect(new CompanionIntelligence(w.deps).status()).toMatchObject({ state: 'ready', model: 'opus' })
    w.set({ ...w.get(), sessionId: 'another-conversation' })
    expect(new CompanionIntelligence(w.deps).status().state).toBe('waiting')
    expect(readFileSync(w.deps.stateFile, 'utf8')).not.toContain('prompt')
  })

  it('can review before the first message with live startup evidence, without persisting a fake conversation', async () => {
    const w = world()
    const startup = { processKey: 'live-process-1', profile: w.get().profile! }
    w.set({ ...w.get(), sessionId: '', profile: null, startup })
    expect(w.brain.status()).toMatchObject({ state: 'ready', model: 'opus' })
    expect(await w.brain.run('evidence', { timeoutMs: 1000, signal: new AbortController().signal })).toBe('{"lesson":null}')
    expect(existsSync(w.deps.stateFile)).toBe(false)
    w.set({ ...w.get(), stopped: true })
    expect(new CompanionIntelligence(w.deps).status().state).toBe('waiting')
    w.set({ ...w.get(), stopped: false, startup: null })
    expect(w.brain.status().state).toBe('waiting')
  })

  it('rejects an unbound review result from a replaced process even with the same agent and model', async () => {
    const w = world(), startup = { processKey: 'live-process-1', profile: w.get().profile! }
    w.set({ ...w.get(), sessionId: '', profile: null, startup })
    let finish!: (result: { text: string }) => void
    w.run.mockImplementation(() => new Promise(resolve => { finish = resolve }))
    const result = w.brain.run('evidence', { timeoutMs: 1000, signal: new AbortController().signal })
    w.set({ ...w.get(), startup: { ...startup, processKey: 'live-process-2' } })
    finish({ text: 'old answer' })
    expect(await result).toBeNull()
  })

  it('does not guess a model from another agent, setup, unsupported credentials, or a missing DSH', async () => {
    const w = world()
    w.set({ ...w.get(), profile: encodeRuntimeProfile({ sessionId: 'other-agent', engine: 'claude', model: 'haiku', effort: 'low' }) })
    expect(w.brain.status().state).toBe('waiting')
    w.set({ ...w.get(), sessionId: null })
    expect(await w.brain.run('x', { timeoutMs: 100, signal: new AbortController().signal })).toBeNull()
    w.set({ ...w.get(), sessionId: 'session-1', customProvider: true })
    expect(w.brain.status().state).toBe('unsupported')
    w.set(null)
    expect(w.brain.status().state).toBe('unopened')
    w.off()
    expect(w.brain.status().state).toBe('off')
    expect(w.run).not.toHaveBeenCalled()
  })

  it('does not apply a result after the collection is turned off or its model changes', async () => {
    const w = world()
    let resolve!: (result: { text: string }) => void
    w.run.mockImplementation(() => new Promise(done => { resolve = done }))
    const result = w.brain.run('evidence', { timeoutMs: 1000, signal: new AbortController().signal })
    w.off(); w.brain.cancel()
    resolve({ text: 'old answer' })
    expect(await result).toBeNull()
    expect(w.run.mock.calls[0]?.[1]?.signal?.aborted).toBe(true)
  })

  it('binds extraction to the selected runtime and rejects a changed observed account', async () => {
    const w = world()
    w.set({ ...w.get(), accountKey: 'first-account' })
    const before = w.brain.status().contextKey
    let finish!: (result: { text: string }) => void
    w.run.mockImplementation(() => new Promise(resolve => { finish = resolve }))
    const contextKey = (await w.brain.extractionStatus()).contextKey!
    const pending = w.brain.extract('coding evidence only', { timeoutMs: 1000, signal: new AbortController().signal, contextKey })
    await vi.waitFor(() => expect(w.run).toHaveBeenCalledWith('claude', expect.objectContaining({ prompt: 'coding evidence only', model: 'opus', effort: 'high' })))
    w.set({ ...w.get(), accountKey: 'second-account' })
    expect(w.brain.status().contextKey).not.toBe(before)
    finish({ text: 'result from the previous account' })
    expect(await pending).toBeNull()
  })

  it('rechecks native account metadata after extraction, including a new login at the same path', async () => {
    const w = world()
    let account: string | null = 'native-account-1'
    const brain = new CompanionIntelligence({ ...w.deps, accountIdentity: async () => account })
    const before = (await brain.extractionStatus()).contextKey
    let finish!: (result: { text: string }) => void
    w.run.mockImplementation(() => new Promise(resolve => { finish = resolve }))
    const pending = brain.extract('evidence', { timeoutMs: 1000, signal: new AbortController().signal, contextKey: before! })
    await vi.waitFor(() => expect(w.run).toHaveBeenCalledOnce())
    account = 'native-account-2'
    expect((await brain.extractionStatus()).contextKey).not.toBe(before)
    finish({ text: 'answer from old account' })
    expect(await pending).toBeNull()
    account = null
    expect((await brain.extractionStatus()).state).toBe('waiting')
    expect(await brain.extract('evidence', { timeoutMs: 1000, signal: new AbortController().signal, contextKey: before! })).toBeNull()
    expect(w.run).toHaveBeenCalledOnce()
  })

  it('cancels while the native account lookup is pending without launching extraction', async () => {
    const w = world()
    let finish!: (value: string) => void
    const account = new Promise<string>(resolve => { finish = resolve })
    const brain = new CompanionIntelligence({ ...w.deps,
      accountIdentity: () => account })
    const pending = brain.extract('synthetic evidence', { timeoutMs: 1000, signal: new AbortController().signal, contextKey: 'cancelled-before-binding' })
    brain.cancel()
    finish('account-before-cancellation')
    expect(await pending).toBeNull()
    expect(w.run).not.toHaveBeenCalled()
  })

  it('does not send a leased prompt after the selected extraction context changes', async () => {
    const w = world()
    w.set({ ...w.get(), accountKey: 'first-account' })
    const contextKey = (await w.brain.extractionStatus()).contextKey!
    w.set({ ...w.get(), accountKey: 'replacement-account' })
    const options = { timeoutMs: 1000, signal: new AbortController().signal, contextKey }
    await expect(w.brain.extract('synthetic evidence from the original lease', options)).rejects.toThrow('inference_context_changed')
    expect(w.run).not.toHaveBeenCalled()
  })
})
