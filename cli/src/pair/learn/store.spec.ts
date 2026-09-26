/**
 * L1 STORE (daemons/LEARNING.md): a git-backed folder at an injectable root. Real git, in a temp folder,
 * with no global or system config read; one commit per approval and per revert.
 */
import { afterEach, beforeEach, describe, expect, it } from 'vitest'
import { execFileSync } from 'node:child_process'
import { existsSync, mkdtempSync, readFileSync, readdirSync, rmSync, statSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { LessonStore, NO_GIT_NOTE } from './store.js'
import type { Lesson, Signal } from './types.js'

let dir: string
let root: string
let clock: number
let ids: number
beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), 'learn-store-'))
  root = join(dir, 'lessons')
  clock = Date.UTC(2026, 9, 3, 15, 2)
  ids = 0
})
afterEach(() => rmSync(dir, { recursive: true, force: true }))

const store = (git: string | null | undefined = undefined) => new LessonStore({
  root, now: () => clock, newId: () => `${(++ids).toString(16).padStart(6, 'a')}`, ...(git === undefined ? {} : { git }),
  // A hostile environment: none of this may leak into the lessons repo.
  env: { ...process.env, GIT_DIR: join(dir, 'elsewhere'), GIT_AUTHOR_EMAIL: 'person@example.com', HOME: dir },
})
const git = (...args: string[]) => execFileSync('git', args, { cwd: root, encoding: 'utf8', env: { PATH: process.env.PATH, GIT_CONFIG_GLOBAL: '/dev/null', GIT_CONFIG_NOSYSTEM: '1' } })

const signal = (key = 'steps:abc:x', project: string | null = 'abc'): Signal => ({
  kind: 'repeat-steps', key, project, projectName: 'api', at: clock,
  from: [{ engine: 'codex', machine: 'office', agentId: 'b1', session: 's1', turn: 14, project, at: clock }, { engine: 'claude', machine: 'm2', agentId: 'a1', session: 's2', turn: 3, project, at: clock }],
  evidence: ['npm run migrate -- --dry-run ; npm test'],
  steps: ['npm run db:reset', 'npm run migrate', 'npm test'],
})
const skill: Lesson = { kind: 'skill', name: 'run-migrations-safely', description: 'Run database migrations in api. Use before any migrate command.', body: 'Run `npm run migrate -- --dry-run` first and show the plan.\nRun the real migration only after the user says yes.' }
const note: Lesson = { kind: 'note', lines: ['The failing test is flaky: `billing > rounds cents`.'] }

describe('LessonStore', () => {
  it('touches nothing until the first lesson, then keeps it pending and uncommitted', () => {
    const s = store()
    expect(s.list()).toEqual([])
    expect(existsSync(root)).toBe(false)
    const added = s.add({ lesson: skill, signal: signal(), learnedBy: 'tim', source: 'model' })
    expect(added.ok).toBe(true)
    if (!added.ok) return
    const md = readFileSync(join(root, 'pending', added.record.id, 'SKILL.md'), 'utf8')
    expect(md).toMatch(/^---\nname: run-migrations-safely\ndescription: "Run database migrations in api\. Use before any migrate command\."\nmetadata:\n  harness:\n/)
    expect(md).toContain('    learnedBy: "tim"')
    expect(md).toContain('      - {"engine":"codex","machine":"office","session":"s1","turn":14,"project":"abc"}')
    expect(md).toContain('    evidence:\n      - "npm run migrate -- --dry-run ; npm test"')
    expect(md).toContain('    approved: null')
    expect(md.endsWith('Run the real migration only after the user says yes.\n')).toBe(true)
    expect(statSync(root).mode & 0o777).toBe(0o700)
    expect(git('log', '--format=%s')).toBe('lessons: start\n')
    expect(git('status', '--porcelain')).toBe('')
    expect(s.pending().map((r) => [r.name, r.status])).toEqual([['run-migrations-safely', 'pending']])
  })

  it('approve: moves it to skills/<name>, one commit by Harness with its id, and nothing else changes', () => {
    const s = store()
    const added = s.add({ lesson: skill, signal: signal(), learnedBy: 'tim', source: 'model' })
    if (!added.ok) throw new Error('add')
    const approved = s.approve(added.record.id, 'key')
    expect(approved).toMatchObject({ ok: true, record: { status: 'approved', approved: '2026-10-03', name: 'run-migrations-safely' } })
    if (!approved.ok) return
    expect(existsSync(join(root, 'pending', added.record.id))).toBe(false)
    expect(readFileSync(join(root, 'skills/run-migrations-safely/SKILL.md'), 'utf8')).toContain('    approved: "2026-10-03"')
    expect(git('log', '--format=%s|%an|%ae')).toBe('learn: run-migrations-safely|Harness|lessons@harness.invalid\nlessons: start|Harness|lessons@harness.invalid\n')
    expect(git('log', '-1', '--format=%b')).toContain(`Lesson-Id: ${added.record.id}\nLearned-By: tim\nApproved-By: key`)
    expect(approved.commit).toBe(git('rev-parse', 'HEAD').trim())
    expect(git('show', '--stat', '--format=', 'HEAD').trim().split('\n').slice(0, -1).map((l) => l.trim().split(' ')[0])).toEqual([
      'skills/run-migrations-safely/SKILL.md', 'skills/run-migrations-safely/lesson.json',
    ])
    expect(git('status', '--porcelain')).toBe('')
    expect(s.approved().map((r) => [r.id, r.commit])).toEqual([[added.record.id, approved.commit]])
    expect(existsSync(join(dir, 'elsewhere'))).toBe(false)
  })

  it('revert: git revert of that commit, the skill gone, and never proposed again', () => {
    const s = store()
    const added = s.add({ lesson: skill, signal: signal(), learnedBy: 'tim', source: 'model' })
    if (!added.ok) throw new Error('add')
    const approved = s.approve(added.record.id, 'key')
    const other = s.add({ lesson: note, signal: signal('fail:test:abc:billing'), learnedBy: 'tim', source: 'template' })
    if (!approved.ok || !other.ok) throw new Error('approve')
    s.approve(other.record.id, 'cli')
    const reverted = s.revert(added.record.id)
    expect(reverted).toMatchObject({ ok: true, record: { status: 'reverted' } })
    if (!reverted.ok) return
    expect(git('log', '-1', '--format=%B')).toContain(`unlearn: run-migrations-safely\n\nThis reverts commit ${approved.commit}.\nLesson-Id: ${added.record.id}`)
    expect(existsSync(join(root, 'skills/run-migrations-safely'))).toBe(false)
    expect(existsSync(join(root, `notes/${other.record.id}/NOTE.md`))).toBe(true)
    expect(git('status', '--porcelain')).toBe('')
    expect(s.get(added.record.id)?.status).toBe('reverted')
    expect(s.list().map((r) => [r.id, r.status])).toEqual([[other.record.id, 'approved'], [added.record.id, 'reverted']])
    expect(s.add({ lesson: skill, signal: signal('steps:abc:other'), learnedBy: 'tim', source: 'model' })).toMatchObject({ ok: false, error: 'SKIPPED' })
    expect(s.revert(added.record.id)).toMatchObject({ ok: false, error: 'NOT_APPROVED' })
  })

  it('skip: gone, remembered by its lesson and by its signal', () => {
    const s = store()
    const added = s.add({ lesson: skill, signal: signal(), learnedBy: 'tim', source: 'model' })
    if (!added.ok) throw new Error('add')
    expect(s.skip(added.record.id)).toMatchObject({ ok: true, record: { status: 'skipped' } })
    expect(s.pending()).toEqual([])
    expect(s.add({ lesson: skill, signal: signal('another'), learnedBy: 'tim', source: 'model' })).toMatchObject({ ok: false, error: 'SKIPPED' })
    expect(s.add({ lesson: { ...skill, name: 'reworded', body: 'Say it differently.' }, signal: signal(), learnedBy: 'tim', source: 'model' })).toMatchObject({ ok: false, error: 'SKIPPED' })
    expect(s.get(added.record.id)?.status).toBe('skipped')
    expect(git('log', '--format=%s')).toBe('lessons: start\n')
    expect(s.approve(added.record.id, 'key')).toMatchObject({ ok: false, error: 'NOT_PENDING' })
    expect(s.approve('ffffff', 'key')).toMatchObject({ ok: false, error: 'NOT_FOUND' })
  })

  it('refuses the same lesson twice, and numbers a second skill with a taken name', () => {
    const s = store()
    const first = s.add({ lesson: skill, signal: signal('k1'), learnedBy: 'tim', source: 'model' })
    expect(s.add({ lesson: skill, signal: signal('k2'), learnedBy: 'tim', source: 'model' })).toMatchObject({ ok: false, error: 'KNOWN' })
    expect(s.add({ lesson: { ...skill, body: 'Different.' }, signal: signal('k1'), learnedBy: 'tim', source: 'model' })).toMatchObject({ ok: false, error: 'KNOWN' })
    const second = s.add({ lesson: { ...skill, body: 'Different.' }, signal: signal('k3'), learnedBy: 'mo', source: 'model' })
    if (!first.ok || !second.ok) throw new Error('add')
    s.approve(first.record.id, 'key')
    expect(s.approve(second.record.id, 'key')).toMatchObject({ ok: true, record: { name: 'run-migrations-safely-2' } })
    expect(readFileSync(join(root, 'skills/run-migrations-safely-2/SKILL.md'), 'utf8')).toMatch(/^---\nname: run-migrations-safely-2\n/)
  })

  it('without git: the same moves with a plain journal, and it says so', () => {
    const s = store(null)
    const added = s.add({ lesson: skill, signal: signal(), learnedBy: 'tim', source: 'model' })
    if (!added.ok) throw new Error('add')
    expect(s.git).toBe(false)
    expect(s.approve(added.record.id, 'key')).toMatchObject({ ok: true, commit: null, note: NO_GIT_NOTE })
    expect(existsSync(join(root, '.git'))).toBe(false)
    expect(s.revert(added.record.id)).toMatchObject({ ok: true, commit: null, note: NO_GIT_NOTE })
    expect(readdirSync(join(root, 'reverted'))).toEqual([`${added.record.id}-run-migrations-safely`])
    const journal = readFileSync(join(root, 'journal.jsonl'), 'utf8').trim().split('\n').map((line) => JSON.parse(line))
    expect(journal.map((e) => [e.op, e.git])).toEqual([['added', false], ['approved', false], ['reverted', false]])
    expect(statSync(join(root, 'journal.jsonl')).mode & 0o777).toBe(0o600)
  })

  it('a git that cannot run is no git', () => {
    expect(store(join(dir, 'no-such-git')).git).toBe(false)
  })

  it('keeps the proposal bookkeeping out of the repository', () => {
    const s = store()
    const added = s.add({ lesson: skill, signal: signal(), learnedBy: 'tim', source: 'model' })
    if (!added.ok) throw new Error('add')
    s.markProposed(added.record.id, clock)
    expect(s.lastProposedAt()).toBe(clock)
    expect(s.proposedAt(added.record.id)).toBe(clock)
    expect(git('status', '--porcelain')).toBe('')
  })
})
