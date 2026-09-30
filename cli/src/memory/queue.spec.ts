import { mkdtempSync, readFileSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'
import { CodingMemoryStore } from './store.js'
import type { CaptureBatch, LearningLease } from './queue.js'
import type { MemoryAccess, MemoryDraft, SourceEvent } from './types.js'

const access: MemoryAccess = { profileId: 'owner', projectIds: ['project'], includeProfile: false }
const target = { state: 'ready' as const, key: 'collection:codex:account1:selected-model:high' }
let directory: string
let now: number
let store: CodingMemoryStore
const opened: CodingMemoryStore[] = []
function open(): CodingMemoryStore {
  const result = CodingMemoryStore.open({ directory, profileId: 'owner', now: () => now })
  if (!result.ok) throw new Error(result.reason)
  opened.push(result.store)
  return result.store
}
function event(id = 'first', changes: Partial<SourceEvent> = {}): SourceEvent {
  return { id, profileId: 'owner', projectId: 'project', engine: 'claude', sessionId: 'session', nativeEventId: id,
    role: 'user', eligibility: 'coding', observedAt: 9_000, rootIds: [id],
    text: 'For debugging start with a small failing test because it makes review easier.', ...changes }
}
function batch(id = 'first', changes: Partial<CaptureBatch> = {}): CaptureBatch {
  return { streamId: 'stream', engine: 'claude', sessionId: 'session', projectId: 'project', episodeId: `episode_${id}`,
    from: null, to: id, events: [event(id)], boundary: 'complete', ...changes }
}
function proposal(source = event(), changes: Partial<MemoryDraft> = {}): MemoryDraft {
  return { kind: 'working_preference', facet: 'debugging', assertionType: 'stated_preference', scope: { profileId: 'owner', projectId: 'project' },
    claim: 'For debugging, start with a small failing test.', rationale: 'It makes review easier.',
    futureAction: 'Start with a small failing test.', applicability: { taskType: 'debugging' }, exceptions: [], retrievalCues: ['bug', 'test'],
    evidenceClass: 'user_stated', evidence: [{ sourceEventId: source.id, quote: source.text, paths: ['/claim', '/rationale', '/futureAction', '/applicability', '/exceptions', '/validity'] }],
    conflictKey: 'debugging_order', validity: { validFrom: null, validUntil: null, recheckWhen: [] }, ...changes }
}
function claim(handle = store): LearningLease {
  const result = handle.learning.claim(target)
  if (result.state !== 'claimed') throw new Error(result.state)
  return result.lease
}
beforeEach(() => {
  now = 10_000
  directory = mkdtempSync(join(tmpdir(), 'memory-queue-'))
  store = open()
  store.registerProject('project')
  store.setControls({ learn: true, recall: true })
})
afterEach(() => { for (const handle of opened.splice(0)) handle.close(); rmSync(directory, { recursive: true, force: true }) })

describe('durable coding episode capture', () => {
  it('captures the first user turn before an assistant reply and resumes after reopen', () => {
    store.learning.capture(batch('first', { boundary: 'open' }))
    expect(store.learning.claim(target).state).toBe('idle')
    store.close()
    store = open()
    expect(store.learning.cursor('stream')).toBe('first')
    expect(store.learning.capture(batch('first', { boundary: 'open' })).disposition).toBe('duplicate')
    store.learning.capture(batch('end', { from: 'first', episodeId: 'episode_first', events: [], boundary: 'complete' }))
    const lease = claim()
    expect(lease.sources.map(source => source.id)).toEqual(['first'])
    const result = store.learning.finish(lease, [proposal()], target)
    expect(result.state).toBe('learned')
    expect(store.learning.status().jobs.learned).toBe(1)
    expect(store.list(access)).toHaveLength(1)
    expect(store.learning.claim(target).state).toBe('idle')
  })

  it('rolls back sources, cursor, and jobs together when any input is ineligible', () => {
    expect(() => store.learning.capture(batch('bad', { events: [event('good'), event('private', { eligibility: 'private' })] })))
      .toThrow('source_ineligible')
    expect(store.learning.cursor('stream')).toBeNull()
    expect(store.source('good', access)).toBeNull()
    expect(store.learning.status().capturedStreams).toBe(0)
    expect(store.learning.status().jobs).toEqual({})
  })

  it('does not acknowledge an out-of-order cursor or broaden episode ownership', () => {
    store.learning.capture(batch())
    expect(() => store.learning.capture(batch('second', { from: 'missing' }))).toThrow('cursor_conflict')
    expect(store.learning.cursor('stream')).toBe('first')
    expect(store.source('second', access)).toBeNull()
    expect(() => store.learning.capture(batch('second', { from: 'first', events: [event('foreign', { projectId: null })] }))).toThrow('episode_scope')
    expect(store.learning.cursor('stream')).toBe('first')
  })

  it('preserves incomplete source status without pretending an extraction found no memory', () => {
    store.learning.capture(batch('partial', { boundary: 'incomplete' }))
    expect(store.learning.claim(target).state).toBe('idle')
    expect(store.learning.status().jobs.source_incomplete).toBe(1)
    expect(store.learning.status().jobs.no_useful_memory).toBeUndefined()
    store.learning.capture(batch('completed', { from: 'partial', episodeId: 'episode_partial', events: [] }))
    const lease = claim()
    expect(store.learning.finish(lease, [], target).state).toBe('no_useful_memory')
  })
})

describe('model availability, leases, and idempotent publication', () => {
  it('cancels private work and rejects late extraction, including episodes with derived private roots', () => {
    store.learning.capture(batch())
    const lease = claim()
    const parent = store.propose(proposal(), access).record
    const derived = event('echo', { sessionId: 'public_session', role: 'derived', rootIds: ['first'],
      derivedFrom: [{ memoryId: parent.id, revision: 1 }] })
    store.learning.capture(batch('echo', { streamId: 'another_stream', sessionId: 'public_session', events: [derived] }))
    store.setSessionIncluded('claude', 'session', false)
    expect(store.learning.status().jobs.cancelled).toBe(2)
    expect(store.learning.finish(lease, [proposal()], target)).toEqual({ state: 'stale', reason: 'lease_changed' })
    expect(store.learning.claim(target).state).toBe('idle')
    expect(() => store.learning.capture(batch('private', { from: 'first', events: [] }))).toThrow('source_ineligible')
    expect(() => store.learning.checkpoint({ streamId: 'stream', engine: 'claude', sessionId: 'session', projectId: 'project',
      from: 'first', to: 'private', generation: store.controls().generation })).toThrow('source_ineligible')
  })

  it('retains observations when the selected model is unavailable and resumes without fallback', () => {
    store.learning.capture(batch())
    expect(store.learning.claim({ state: 'unsupported' }).state).toBe('waiting_for_model')
    expect(store.learning.status().callsLastHour).toBe(0)
    store.close()
    store = open()
    expect(store.learning.status().jobs.waiting_for_model).toBe(1)
    now += 60_000
    expect(claim().sources).toHaveLength(1)
  })

  it('leases at most one episode per project and recovers an expired process without accepting its late result', () => {
    store.learning.capture(batch())
    store.learning.capture(batch('second', { from: 'first' }))
    const first = claim()
    const other = open()
    expect(other.learning.claim(target).state).toBe('idle')
    now = first.until + 1
    const recovered = claim(other)
    expect(recovered.jobId).toBe(first.jobId)
    expect(recovered.token).not.toBe(first.token)
    expect(store.learning.finish(first, [proposal()], target).state).toBe('stale')
    expect(other.learning.finish(recovered, [proposal()], target).state).toBe('learned')
    expect(store.learning.finish(recovered, [proposal()], target).state).toBe('stale')
    expect(store.list(access)).toHaveLength(1)
  })

  it('rejects a completed result after the model/account or capture controls change', () => {
    store.learning.capture(batch())
    const lease = claim()
    expect(store.learning.finish(lease, [proposal()], { ...target, key: 'new-account' }).state).toBe('stale')
    expect(store.list(access)).toEqual([])
    const fresh = claim()
    store.setControls({ learn: false, recall: true })
    expect(store.learning.finish(fresh, [proposal()], target).state).toBe('stale')
    expect(store.learning.claim(target).state).toBe('learning_off')
    store.setControls({ learn: true, recall: true })
    expect(store.learning.finish(claim(), [proposal()], target).state).toBe('learned')
  })

  it('reserves the rolling inference budget durably and preserves deferred sources and foreground priority', () => {
    let previous: string | null = null
    for (let index = 0; index < 7; index++) {
      const id = `source_${index}`
      store.learning.capture(batch(id, { from: previous }))
      previous = id
    }
    expect(store.learning.claim({ ...target, foregroundBusy: true }).state).toBe('foreground_busy')
    for (let index = 0; index < 6; index++) expect(store.learning.finish(claim(), [], target).state).toBe('no_useful_memory')
    store.close()
    store = open()
    expect(store.learning.claim(target).state).toBe('budget_deferred')
    expect(store.learning.status().callsLastHour).toBe(6)
    expect(store.learning.status().jobs.budget_deferred).toBe(1)
    expect(store.learning.cursor('stream')).toBe('source_6')
    now += 3_600_001
    expect(claim().sources.map(source => source.id)).toEqual(['source_6'])
  })

  it('publishes a proposal batch atomically and rejects evidence outside the captured episode', () => {
    store.learning.capture(batch())
    store.ingest(event('unrelated'))
    const lease = claim()
    const result = store.learning.finish(lease, [proposal(), proposal(event('unrelated'), { conflictKey: 'other' })], target)
    expect(result).toEqual({ state: 'failed', reason: 'episode_evidence' })
    expect(store.list(access)).toEqual([])
    expect(store.learning.status().jobs.failed).toBe(1)
    expect(store.source('first', access)).not.toBeNull()
  })

  it('cancels jobs and late model output when their supporting memory is forgotten', () => {
    const unique = 'forgotten_queued_lemur'
    const source = event('first', { text: `For debugging use ${unique}.` })
    store.learning.capture(batch('first', { events: [source] }))
    const lease = claim()
    const record = store.propose(proposal(source, { claim: source.text }), access).record
    store.forget(record.id, 1, access)
    expect(store.learning.finish(lease, [proposal(source)], target)).toEqual({ state: 'stale', reason: 'lease_changed' })
    expect(store.learning.status().jobs.cancelled).toBe(1)
    expect(store.source('first', access)).toBeNull()
    expect(readFileSync(join(directory, 'memory.sqlite')).includes(Buffer.from(unique))).toBe(false)
    expect(store.learning.capture(batch('replayed', { from: 'first', events: [source] })).state).toBe('cancelled')
  })
})
