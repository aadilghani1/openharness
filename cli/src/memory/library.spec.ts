import { mkdtempSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { afterEach, beforeEach, expect, it } from 'vitest'
import { CodingMemoryStore } from './store.js'
import type { MemoryDraft, MemoryRecord, MemoryScope, SourceEvent } from './types.js'
import type { MemoryCorrection } from './library.js'

let directory: string, store: CodingMemoryStore
beforeEach(() => {
  directory = mkdtempSync(join(tmpdir(), 'memory-library-'))
  const opened = CodingMemoryStore.open({ directory, profileId: 'owner', now: () => 1000 })
  if (!opened.ok) throw new Error(opened.reason)
  store = opened.store
  store.setControls({ learn: true, recall: true })
})
afterEach(() => { store.close(); rmSync(directory, { recursive: true, force: true }) })

function learn(id: string, scope: MemoryScope = { profileId: 'owner', projectId: 'project' }): MemoryRecord {
  if (scope.projectId) store.registerProject(scope.projectId)
  const claim = `For coding task ${id}, I prefer a small reproducer.`
  const source: SourceEvent = { id, profileId: 'owner', projectId: scope.projectId ?? null, taskId: scope.taskId, branchId: scope.branchId,
    role: 'user', engine: 'claude', sessionId: id, nativeEventId: id, rootIds: [id], eligibility: 'coding', observedAt: 900,
    text: `${claim}\nUnrelated private conversation must never appear in the library detail.` }
  store.ingest(source)
  const draft: MemoryDraft = { kind: 'working_preference', facet: 'debugging', assertionType: 'stated_preference', scope, claim,
    rationale: null, futureAction: 'Begin with a reproducer.', applicability: {}, exceptions: [], retrievalCues: ['reproducer'],
    conflictKey: id, evidenceClass: 'user_stated', evidence: [{ sourceEventId: id, quote: claim, paths: ['/claim', '/futureAction', '/applicability'] }],
    validity: { validFrom: null, validUntil: null, recheckWhen: [] } }
  return store.propose(draft, { profileId: 'owner', projectIds: scope.projectId ? [scope.projectId] : [], includeProfile: true,
    taskId: scope.taskId, branchId: scope.branchId }).record
}
function fields(record: MemoryRecord): MemoryCorrection {
  const { claim, rationale, futureAction, applicability, exceptions, retrievalCues, validity } = record
  return { claim, rationale, futureAction, applicability, exceptions, retrievalCues, validity }
}

it('paginates all owner scopes without granting that access to ordinary agents', () => {
  const personal = learn('personal', { profileId: 'owner' })
  const task = learn('task', { profileId: 'owner', projectId: 'project', taskId: 'task' })
  const branch = learn('branch', { profileId: 'owner', projectId: 'second', branchId: 'branch' })
  const page = store.libraryPage('owner', { limit: 2 })
  expect(page.items.map(item => item.id)).toEqual([branch.id, task.id])
  expect(page.items[0]).not.toHaveProperty('evidence')
  expect(store.libraryPage('owner', { limit: 2, cursor: page.nextCursor! }).items.map(item => item.id)).toEqual([personal.id])
  expect(store.libraryPage('owner', { scope: 'personal' }).items.map(item => item.id)).toEqual([personal.id])
  expect(store.libraryPage('owner', { projectId: 'project' }).items.map(item => item.id)).toEqual([task.id])
  expect(store.list({ profileId: 'owner', projectIds: ['project'], includeProfile: false })).toEqual([])
  expect(() => store.libraryPage('other')).toThrow('scope_denied')
  expect(() => store.libraryDetail('other', task.id)).toThrow('scope_denied')
})

it('applies privacy before page limits and returns only retained evidence spans', () => {
  const record = learn('visible')
  learn('hidden')
  store.setSessionIncluded('claude', 'hidden', false)
  expect(store.libraryPage('owner', { limit: 1 }).items.map(item => item.id)).toEqual([record.id])
  const detail = store.libraryDetail('owner', record.id)!
  expect(detail.sources).toEqual([{ id: 'visible', engine: 'claude', sessionId: 'visible', role: 'user', observedAt: 900 }])
  expect(JSON.stringify(detail)).not.toContain('Unrelated private')
  store.setProjectIncluded('project', false)
  expect(store.libraryPage('owner').items).toEqual([])
  expect(store.libraryDetail('owner', record.id)).toBeNull()
  // Privacy must not prevent the owner from deleting a known record.
  const preview = store.libraryPreview('owner', { kind: 'forget', id: record.id, revision: 1 })
  expect(store.libraryApply('owner', preview.command, preview.version, false).deletedIds).toContain(record.id)
})

it('rejects stale, malformed, foreign-owner and differently filtered cursors', () => {
  const first = learn('first'); learn('second')
  const page = store.libraryPage('owner', { limit: 1 })
  expect(() => store.libraryPage('owner', { cursor: 'garbage' })).toThrow('invalid_cursor')
  expect(() => store.libraryPage('owner', { cursor: page.nextCursor!, scope: 'personal' })).toThrow('invalid_cursor')
  const cursor = JSON.parse(Buffer.from(page.nextCursor!, 'base64url').toString())
  expect(() => store.libraryPage('owner', { cursor: Buffer.from(JSON.stringify({ ...cursor, owner: 'other' })).toString('base64url') })).toThrow('invalid_cursor')
  store.libraryCorrect('owner', first.id, 1, { ...fields(first), claim: 'I prefer a minimal failing test.' })
  expect(() => store.libraryPage('owner', { cursor: page.nextCursor! })).toThrow('page_changed')
})

it('validates a concrete correction without saving a revision or invented user event', () => {
  const record = learn('one', { profileId: 'owner', projectId: 'project', taskId: 'task', branchId: 'branch' })
  const version = store.libraryPage('owner').version
  const command = { kind: 'correct' as const, id: record.id, revision: 1, fields: { ...fields(record), claim: 'I prefer a focused regression test.' } }
  const preview = store.libraryPreview('owner', command)
  expect(preview.effects.record).toMatchObject({ claim: command.fields.claim, revision: 2, scope: record.scope })
  expect(store.libraryDetail('owner', record.id)!.record).toEqual(record)
  expect(store.libraryPage('owner').version).toEqual(version)
  store.setControls({ learn: false, recall: false })
  const current = store.libraryPreview('owner', command)
  expect(store.libraryApply('owner', command, current.version, false).record).toMatchObject({ revision: 2, evidenceClass: 'user_stated' })
  const detail = store.libraryDetail('owner', record.id)!
  expect(detail.sources).toMatchObject([{ engine: 'harness_viewer', role: 'user' }])
  expect(() => store.libraryApply('owner', command, current.version, false)).toThrow('preview_changed')
  expect(() => store.libraryCorrect('owner', record.id, 1, command.fields)).toThrow('revision_conflict')
})

it('refuses payload authority changes and secret-bearing corrections without changing the record', () => {
  const record = learn('one')
  expect(() => store.libraryCorrect('owner', record.id, 1, { ...fields(record), scope: { profileId: 'owner' } } as MemoryCorrection)).toThrow('invalid_input')
  expect(() => store.libraryPreview('owner', { kind: 'correct', id: record.id, revision: 1,
    fields: { ...fields(record), claim: 'Save this API key sk-ant-api03-abcdefghijklmnopqrstuvwxyz0123456789' } })).toThrow()
  expect(store.libraryDetail('owner', record.id)!.record).toEqual(record)
})

it('previews forgetting without erasing evidence and refuses a changed dependency snapshot', () => {
  const record = learn('one')
  const preview = store.libraryPreview('owner', { kind: 'forget', id: record.id, revision: 1 })
  expect(preview.effects).toEqual({ deletedIds: [record.id], deletedTopicIds: [], alreadyDeliveredContent: 'not_erased' })
  expect(store.libraryDetail('owner', record.id)!.record).toEqual(record)
  learn('new_knowledge')
  expect(() => store.libraryApply('owner', preview.command, preview.version, true)).toThrow('preview_changed')
  const current = store.libraryPreview('owner', preview.command)
  store.libraryApply('owner', current.command, current.version, true)
  expect(store.libraryDetail('owner', record.id)).toBeNull()
})

it('invalidates a forget preview when a new notebook page depends on the record', () => {
  const record = learn('one')
  const preview = store.libraryPreview('owner', { kind: 'forget', id: record.id, revision: 1 })
  store.putTopic({ id: 'new_topic', scope: record.scope, title: 'Debugging', statements: [{ text: record.claim,
    supports: [{ memoryId: record.id, revision: 1, paths: ['/claim'] }] }] }, { profileId: 'owner', projectIds: ['project'], includeProfile: true })
  expect(() => store.libraryApply('owner', preview.command, preview.version, true)).toThrow('preview_changed')
  expect(store.libraryPreview('owner', preview.command).effects.deletedTopicIds).toEqual(['new_topic'])
})

it('invalidates a forget preview when new corroborating evidence connects existing memories', () => {
  const one = learn('one'), two = learn('two')
  const preview = store.libraryPreview('owner', { kind: 'forget', id: one.id, revision: 1 })
  const text = `${one.claim} ${two.claim}`
  store.ingest({ id: 'bridge', profileId: 'owner', projectId: 'project', role: 'user', engine: 'codex', sessionId: 'bridge',
    nativeEventId: 'bridge', rootIds: ['bridge'], eligibility: 'coding', observedAt: 950, text })
  for (const record of [one, two]) {
    const { schemaVersion: _schema, id: _id, revision: _revision, state: _state, createdAt: _created, updatedAt: _updated, ...draft } = record
    const input = { ...draft, evidence: [{ sourceEventId: 'bridge', quote: text, paths: ['/claim', '/futureAction', '/applicability'] }] }
    const access = { profileId: 'owner', projectIds: ['project'], includeProfile: true }
    expect(store.propose(input, access).disposition).toBe('duplicate')
    const version = store.libraryPage('owner').version
    store.propose(input, access) // Replaying the same root changes neither evidence nor the snapshot.
    expect(store.libraryPage('owner').version).toEqual(version)
  }
  expect(store.libraryDetail('owner', one.id)!.record.revision).toBe(1)
  expect(() => store.libraryApply('owner', preview.command, preview.version, true)).toThrow('preview_changed')
  expect(store.libraryPreview('owner', preview.command).effects.deletedIds).toEqual(expect.arrayContaining([one.id, two.id]))
})

it('keeps effective controls off when changing preferences without watching consent', () => {
  store.setControls({ learn: false, recall: false })
  const preview = store.libraryPreview('owner', { kind: 'configure', preferences: { learn: false, recall: true }, expected: { learn: true, recall: true } })
  expect(store.preferences()).toEqual({ learn: true, recall: true })
  expect(store.controls()).toMatchObject({ learn: false, recall: false })
  store.libraryApply('owner', preview.command, preview.version, false)
  expect(store.preferences()).toEqual({ learn: false, recall: true })
  expect(store.controls()).toMatchObject({ learn: false, recall: false })
  expect(() => store.changePreferences({ learn: true, recall: true }, { learn: true, recall: true })).toThrow('revision_conflict')
})
