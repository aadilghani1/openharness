import { mkdtempSync, rmSync } from 'node:fs'
import { appendFile, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { afterEach, beforeEach, expect, it, vi, type Mock } from 'vitest'
import { CodingMemoryRuntime, type MemoryHostContext, type MemoryHostSession } from './runtime.js'
import { CodingMemoryStore } from './store.js'
import { QUEUE_OPERATIONS, type Arguments, type MemoryPort, type Operation, type Result } from './operations.js'
import type { ProjectContext } from './project.js'
import type { MemoryInference } from './learner.js'
import type { InferenceTarget } from './queue.js'
import type { MemoryDraft, SourceEvent } from './types.js'

let directory: string, runtime: CodingMemoryRuntime, now: number, context: MemoryHostContext
let sessions: MemoryHostSession[], inference: MemoryInference, target: InferenceTarget
let locate: Mock<(workspace: string) => Promise<ProjectContext>>
let create: Mock<(profileId: string) => MemoryPort & { close(): Promise<void> }>
let intercept: ((operation: Operation, value: unknown) => Promise<void>) | undefined
const stores = new Map<string, CodingMemoryStore>()
const opened: CodingMemoryStore[] = []
function open(profileId: string): CodingMemoryStore {
  const result = CodingMemoryStore.open({ directory: join(directory, profileId), profileId, now: () => now })
  if (!result.ok) throw new Error(result.reason)
  opened.push(result.store)
  return result.store
}
function deferred<T>() {
  let resolve!: (value: T) => void
  const promise = new Promise<T>(done => { resolve = done })
  return { promise, resolve }
}
const preference = 'I prefer small coding changes.'
function lines(text = preference, id = 'first'): string {
  return JSON.stringify({ type: 'user', uuid: id, timestamp: new Date(now + 1).toISOString(), message: { content: text } }) + '\n'
    + JSON.stringify({ type: 'assistant', uuid: `${id}_reply`, timestamp: new Date(now + 2).toISOString(),
      message: { content: [{ type: 'text', text: 'Understood.' }], stop_reason: 'end_turn' } }) + '\n'
}
function proposal(source: SourceEvent): MemoryDraft {
  return { kind: 'working_preference', facet: 'changes', assertionType: 'stated_preference',
    scope: { profileId: source.profileId, projectId: source.projectId! }, claim: preference, rationale: null,
    futureAction: 'Keep coding changes small.', applicability: {}, exceptions: [], retrievalCues: ['coding', 'changes'],
    evidenceClass: 'user_stated', evidence: [{ sourceEventId: source.id, quote: preference, paths: ['/claim', '/futureAction', '/applicability'] }],
    conflictKey: 'change_size', validity: { validFrom: null, validUntil: null, recheckWhen: [] } }
}
async function learn(): Promise<void> {
  await runtime.tick()
  await writeFile(sessions[0].transcriptPath, lines())
  now += 20_000
  await runtime.tick()
  await vi.waitFor(() => expect(runtime.status().learning?.state).toBe('learned'), { interval: 5 })
}

beforeEach(() => {
  directory = mkdtempSync(join(tmpdir(), 'memory-runtime-'))
  now = 1_000
  context = { experimental: true, watching: true, profileId: 'owner_a' }
  sessions = [{ agentId: 'agent', engine: 'claude', sessionId: 'native', workspace: '/authorized/project',
    transcriptPath: join(directory, 'conversation.jsonl'), busy: false, coding: true }]
  target = { state: 'ready', key: 'selected' }
  inference = { target: vi.fn(async () => target), run: vi.fn(async prompt => {
    const sources = JSON.parse(prompt.split('Captured episode: ')[1]) as SourceEvent[]
    return JSON.stringify({ proposals: [proposal(sources.find(source => source.role === 'user')!)] })
  }) }
  locate = vi.fn(async workspace => ({ locator: { kind: 'directory' as const, path: workspace }, workspacePath: workspace, branchRef: null, revision: null }))
  create = vi.fn((profileId: string) => {
    const store = open(profileId)
    stores.set(profileId, store)
    return { async request<K extends Operation>(operation: K, args: Arguments<K>): Promise<Result<K>> {
      const receiver = (QUEUE_OPERATIONS as readonly string[]).includes(operation) ? store.learning : store
      const value = (receiver as unknown as Record<string, (...args: unknown[]) => unknown>)[operation].apply(receiver, args) as Result<K>
      await intercept?.(operation, value)
      return value
    }, async close() { store.close() } }
  })
  runtime = new CodingMemoryRuntime({ directory, context: () => context, sessions: () => sessions, inference, locate, create, now: () => now })
})
afterEach(async () => {
  intercept = undefined
  await runtime.close()
  for (const store of opened.splice(0)) store.close()
  stores.clear()
  rmSync(directory, { recursive: true, force: true })
})

it('opens no store and invokes no model while experimental, watching consent or identity is absent', async () => {
  context.experimental = false
  await runtime.tick()
  expect(runtime.status().state).toBe('off')
  context.experimental = true; context.watching = false
  await runtime.tick()
  expect(runtime.status().state).toBe('off')
  context.watching = true; context.profileId = null
  await runtime.tick()
  expect(runtime.status().state).toBe('waiting_for_identity')
  expect(create).not.toHaveBeenCalled()
  expect(inference.run).not.toHaveBeenCalled()
})

it('captures from the first eligible turn while waiting for the selected model, then learns and recalls across engines', async () => {
  target = { state: 'waiting' }
  await runtime.tick()
  await writeFile(sessions[0].transcriptPath, lines())
  now += 20_000
  await runtime.tick()
  await vi.waitFor(() => expect(runtime.status().learning?.state).toBe('waiting_for_model'), { interval: 5 })
  expect(stores.get('owner_a')!.learning.status().jobs.waiting_for_model).toBe(1)
  expect(inference.run).not.toHaveBeenCalled()
  target = { state: 'ready', key: 'selected' }
  now += 60_000
  await runtime.tick()
  await vi.waitFor(() => expect(runtime.status().learning?.state).toBe('learned'), { interval: 5 })
  sessions.push({ ...sessions[0], agentId: 'codex', engine: 'codex', sessionId: 'codex_native', transcriptPath: join(directory, 'codex.jsonl') })
  expect((await runtime.recall('codex', { query: 'coding changes' })).items[0].claim).toBe(preference)
  expect((await runtime.recall('unregistered_agent', { query: 'coding changes' })).status).toBe('denied')
})

it('never captures an unclassified general-domain DSH and does not resolve its workspace', async () => {
  sessions[0].coding = false
  await writeFile(sessions[0].transcriptPath, lines('Unrelated personal context.'))
  now += 20_000
  await runtime.tick()
  expect(stores.get('owner_a')!.learning.status().capturedStreams).toBe(0)
  expect(locate).not.toHaveBeenCalled()
  expect((await runtime.recall('agent', { query: 'coding' })).status).toBe('denied')
})

it('waits for quiet and cancels background inference when foreground activity resumes', async () => {
  const running = deferred<string>()
  inference.run = vi.fn(() => running.promise)
  await runtime.tick()
  await writeFile(sessions[0].transcriptPath, lines())
  sessions[0].busy = true
  now += 20_000
  await runtime.tick()
  expect(inference.run).not.toHaveBeenCalled()
  sessions[0].busy = false
  now += 14_999
  await runtime.tick()
  expect(inference.run).not.toHaveBeenCalled()
  now++
  await runtime.tick()
  await vi.waitFor(() => expect(inference.run).toHaveBeenCalledTimes(1), { interval: 5 })
  const signal = vi.mocked(inference.run).mock.calls[0][1].signal
  runtime.activity()
  expect(signal.aborted).toBe(true)
  running.resolve(JSON.stringify({ proposals: [] }))
  await vi.waitFor(() => expect(runtime.status().learning?.reason).toBe('inference_cancelled'), { interval: 5 })
})

it('preserves separate learning/recall preferences through off/on and account switches', async () => {
  await runtime.tick()
  await runtime.configure({ learn: false, recall: true })
  context.experimental = false
  await runtime.tick()
  expect(runtime.status().state).toBe('off')
  context.experimental = true
  await runtime.tick()
  expect(runtime.status().preferences).toEqual({ learn: false, recall: true })
  expect(stores.get('owner_a')!.controls()).toMatchObject({ learn: false, recall: true })
  context.profileId = 'owner_b'
  await runtime.tick()
  expect(runtime.status().preferences).toEqual({ learn: true, recall: true })
  context.profileId = 'owner_a'
  await runtime.tick()
  expect(runtime.status().preferences).toEqual({ learn: false, recall: true })
})

it('starts a fresh capture boundary after an account change instead of copying another owner’s history', async () => {
  target = { state: 'waiting' }
  await runtime.tick()
  await writeFile(sessions[0].transcriptPath, lines('Owner A work.', 'a'))
  await runtime.tick()
  now += 1_000
  context.profileId = 'owner_b'
  await runtime.tick()
  expect(stores.get('owner_b')!.learning.status().jobs).toEqual({})
  await appendFile(sessions[0].transcriptPath, lines('Owner B work.', 'b'))
  await runtime.tick()
  const b = stores.get('owner_b')!.learning.claim({ state: 'ready', key: 'selected' })
  expect(b.state === 'claimed' ? b.lease.sources.map(source => source.text) : b.state).toEqual(['Owner B work.', 'Understood.'])
  now += 1_000
  context.profileId = 'owner_a'
  await runtime.tick()
  expect(stores.get('owner_a')!.learning.status().jobs).toEqual({ queued: 1 })
})

it('rejects a late extraction after ownership changes, even when the provider ignores cancellation', async () => {
  const running = deferred<string>()
  inference.run = vi.fn(() => running.promise)
  await runtime.tick()
  await writeFile(sessions[0].transcriptPath, lines())
  now += 20_000
  await runtime.tick()
  await vi.waitFor(() => expect(inference.run).toHaveBeenCalledOnce(), { interval: 5 })
  context.profileId = 'owner_b'
  await runtime.tick()
  running.resolve(JSON.stringify({ proposals: [] }))
  const previous = open('owner_a')
  expect(previous.controls()).toMatchObject({ learn: false, recall: false })
  expect(previous.learning.status().jobs.no_useful_memory).toBeUndefined()
  expect(stores.get('owner_b')!.learning.status().jobs.no_useful_memory).toBeUndefined()
})

it('withholds recall if the session becomes private while the packet is being read', async () => {
  await learn()
  const delivered = deferred<void>(), release = deferred<void>()
  intercept = async operation => { if (operation === 'recall') { delivered.resolve(); await release.promise } }
  const recall = runtime.recall('agent', { query: 'coding changes' })
  await delivered.promise
  await runtime.setSessionIncluded('agent', false)
  release.resolve()
  expect((await recall).status).toBe('denied')
  intercept = undefined
  expect((await runtime.recall('agent', { query: 'coding changes' })).items).toEqual([])
})

it('withholds a completed packet if the native session rotates before delivery', async () => {
  await learn()
  intercept = async operation => { if (operation === 'recall') sessions = [{ ...sessions[0], sessionId: 'rotated' }] }
  expect((await runtime.recall('agent', { query: 'coding changes' })).status).toBe('denied')
})

it('closes cleanly if consent changes while the store is still initializing', async () => {
  const waiting = deferred<void>(), release = deferred<void>()
  intercept = async operation => { if (operation === 'preferences') { waiting.resolve(); await release.promise } }
  const tick = runtime.tick()
  await waiting.promise
  context.watching = false
  const closing = runtime.close()
  release.resolve()
  await Promise.all([tick, closing])
  expect(runtime.status().state).toBe('off')
  expect(open('owner_a').controls()).toMatchObject({ learn: false, recall: false })
})

it('stops its host timer when paused and resumes with the saved user preferences', async () => {
  const timer = vi.spyOn(globalThis, 'setInterval')
  const clear = vi.spyOn(globalThis, 'clearInterval')
  try {
    runtime.start()
    await runtime.tick()
    await runtime.configure({ learn: false, recall: true })
    const handle = timer.mock.results[0].value as ReturnType<typeof setInterval>
    await runtime.pause()
    expect(clear).toHaveBeenCalledWith(handle)
    expect(open('owner_a').controls()).toMatchObject({ learn: false, recall: false })
    runtime.start()
    await runtime.tick()
    expect(runtime.status().preferences).toEqual({ learn: false, recall: true })
  } finally { timer.mockRestore(); clear.mockRestore() }
})
