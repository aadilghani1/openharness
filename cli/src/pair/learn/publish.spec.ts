/**
 * L1 TEACH (daemons/LEARNING.md): skills reach every engine only through the Store runtime path (a link in
 * the session's runtime and one CONTEXT.md line each); notes go into an AGENTS.md or CLAUDE.md block only
 * when the project already has one. Nothing is ever written into an engine's own folders.
 */
import { afterEach, beforeEach, describe, expect, it } from 'vitest'
import { existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, readlinkSync, realpathSync, rmSync, symlinkSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { prepareHarnessLaunch } from '../../dsh/runtime.js'
import type { InstalledDsh } from '../../dsh/installed.js'
import { LESSONS_BEGIN, LESSONS_END, findProject, noteFile, publishNote, runtimeLessons, unpublishNote } from './publish.js'
import { LessonStore, type LessonRecord } from './store.js'
import { projectHash, type Lesson, type Signal } from './types.js'

let dir: string
let home: string
let ws: string
let other: string
let store: LessonStore
beforeEach(() => {
  dir = realpathSync(mkdtempSync(join(tmpdir(), 'learn-publish-')))
  home = join(dir, 'home')
  ws = join(dir, 'code', 'api')
  other = join(dir, 'code', 'web')
  for (const d of [home, ws, other]) mkdirSync(d, { recursive: true })
  let n = 0
  store = new LessonStore({ root: join(home, '.harness', 'lessons'), now: () => Date.UTC(2026, 9, 3), newId: () => `abc${++n}`, env: { PATH: process.env.PATH } })
})
afterEach(() => rmSync(dir, { recursive: true, force: true }))

const signal = (project: string | null, key: string): Signal => ({
  kind: 'repeat-steps', key, project, projectName: 'api', at: 1,
  from: [{ engine: 'codex', machine: 'm2', agentId: 'a', session: 's', turn: 1, project, at: 1 }], evidence: [],
})
function approve(lesson: Lesson, project: string | null, key: string): LessonRecord {
  const added = store.add({ lesson, signal: signal(project, key), learnedBy: 'tim', source: 'template' })
  if (!added.ok) throw new Error(added.error)
  const approved = store.approve(added.record.id, 'key')
  if (!approved.ok) throw new Error(approved.error)
  return approved.record
}
const skill = (name: string): Lesson => ({ kind: 'skill', name, description: `${name}, for when it fits.`, body: 'Do the thing.' })

/** Every file under a folder, relative: to prove what was (not) written. */
function files(root: string): string[] {
  if (!existsSync(root)) return []
  const out: string[] = []
  const walk = (d: string, rel: string): void => {
    for (const name of readdirSync(d, { withFileTypes: true })) {
      const path = join(d, name.name)
      if (name.isDirectory()) walk(path, join(rel, name.name))
      else out.push(join(rel, name.name))
    }
  }
  walk(root, '')
  return out.sort()
}

describe('skills: only through the Store runtime path', () => {
  it('lists skills made in no project and in this one, never another project\'s', () => {
    approve(skill('global-habit'), null, 'k1')
    approve(skill('api-migrations'), projectHash(ws), 'k2')
    approve(skill('web-deploy-check'), projectHash(other), 'k3')
    approve({ kind: 'note', lines: ['a note is not a skill'] }, projectHash(ws), 'k4')
    expect(runtimeLessons(store, ws)).toEqual({ dir: store.skillsDir, skills: [
      { name: 'api-migrations', description: 'api-migrations, for when it fits.' },
      { name: 'global-habit', description: 'global-habit, for when it fits.' },
    ] })
    expect(runtimeLessons(store, join(dir, 'code', 'none'))?.skills.map((s) => s.name)).toEqual(['global-habit'])
    expect(runtimeLessons(new LessonStore({ root: join(dir, 'empty'), now: () => 1 }), ws)).toBeNull()
  })

  it('a harness session links them in its runtime and lists one line each in CONTEXT.md, and writes nowhere else', () => {
    approve(skill('api-migrations'), projectHash(ws), 'k1')
    const pkgDir = join(dir, 'package')
    mkdirSync(join(pkgDir, 'skills', 'draw'), { recursive: true })
    writeFileSync(join(pkgDir, 'AGENTS.md'), '# Draw\n')
    writeFileSync(join(pkgDir, 'skills', 'draw', 'SKILL.md'), '# Draw\n')
    const pkg: InstalledDsh = { id: 'acme/draw', dir: pkgDir, realDir: pkgDir, source: pkgDir, ref: null, commit: null, linked: true, installedAt: 1,
      manifest: { spec: 1, id: 'acme/draw', name: 'Drawing', engine: 'claude', agent: { instructions: 'AGENTS.md', skills: ['skills'] } } }
    const lessonsBefore = files(store.root)
    const launch = prepareHarnessLaunch(pkg, ws, 'codex', 'session', {}, null, runtimeLessons(store, ws))
    const context = readFileSync(launch.env.HARNESS_CONTEXT_FILE!, 'utf8')
    const runtime = join(launch.env.HARNESS_CONTEXT_FILE!, '..')
    expect(readlinkSync(join(runtime, 'lessons'))).toBe(store.skillsDir)
    expect(context).toContain('## Lessons\n')
    expect(context).toContain(`- api-migrations: api-migrations, for when it fits. ${JSON.stringify(join(runtime, 'lessons', 'api-migrations', 'SKILL.md'))}`)
    expect(readFileSync(join(runtime, 'lessons', 'api-migrations', 'SKILL.md'), 'utf8')).toContain('name: api-migrations')
    // Only the runtime and the bootstrap: no engine folder in the project, and nothing in the home folder.
    for (const engineDir of ['.claude', '.agents', '.codex', '.cursor', '.hermes']) expect(existsSync(join(ws, engineDir))).toBe(false)
    expect(files(home).filter((f) => !f.startsWith(join('.harness', 'lessons')))).toEqual([])
    expect(files(store.root)).toEqual(lessonsBefore)
    expect(files(ws).filter((f) => !f.startsWith('.harness'))).toEqual(['AGENTS.md'])
  })

  it('a reverted skill is gone from a live session at once, and from its index at the next launch', () => {
    const record = approve(skill('api-migrations'), projectHash(ws), 'k1')
    const pkgDir = join(dir, 'package')
    mkdirSync(pkgDir, { recursive: true })
    const pkg: InstalledDsh = { id: 'acme/plain', dir: pkgDir, realDir: pkgDir, source: pkgDir, ref: null, commit: null, linked: true, installedAt: 1,
      manifest: { spec: 1, id: 'acme/plain', name: 'Plain', engine: 'claude', agent: {} } }
    const launch = prepareHarnessLaunch(pkg, ws, 'claude', 'session', {}, null, runtimeLessons(store, ws))
    const runtime = join(launch.env.HARNESS_CONTEXT_FILE!, '..')
    expect(store.revert(record.id).ok).toBe(true)
    expect(existsSync(join(runtime, 'lessons', 'api-migrations', 'SKILL.md'))).toBe(false)
    prepareHarnessLaunch(pkg, ws, 'claude', 'session', {}, null, runtimeLessons(store, ws))
    expect(readFileSync(launch.env.HARNESS_CONTEXT_FILE!, 'utf8')).not.toContain('## Lessons')
    expect(existsSync(join(runtime, 'lessons'))).toBe(false)
  })

  it('a lessons path it does not own costs the lessons, never the launch', () => {
    approve(skill('api-migrations'), null, 'k1')
    const pkgDir = join(dir, 'package')
    mkdirSync(pkgDir, { recursive: true })
    const pkg: InstalledDsh = { id: 'acme/plain', dir: pkgDir, realDir: pkgDir, source: pkgDir, ref: null, commit: null, linked: true, installedAt: 1,
      manifest: { spec: 1, id: 'acme/plain', name: 'Plain', engine: 'claude', agent: {} } }
    const first = prepareHarnessLaunch(pkg, ws, 'claude', 'session')
    const runtime = join(first.env.HARNESS_CONTEXT_FILE!, '..')
    mkdirSync(join(runtime, 'lessons'))
    const launch = prepareHarnessLaunch(pkg, ws, 'claude', 'session', {}, null, runtimeLessons(store, ws))
    expect(readFileSync(launch.env.HARNESS_CONTEXT_FILE!, 'utf8')).not.toContain('## Lessons')
    expect(prepareHarnessLaunch(pkg, ws, 'claude', 'session', {}, null, { dir: store.skillsDir, skills: [{ name: '../escape', description: 'x' }] }).env.HARNESS_CONTEXT_FILE).toBeTruthy()
  })
})

describe('notes: only into an AGENTS.md or CLAUDE.md that exists', () => {
  const noteRecord = (lines: string[], key: string): LessonRecord => approve({ kind: 'note', lines }, projectHash(ws), key)

  it('writes nothing into a project with neither file, and creates one only when asked', () => {
    const record = noteRecord(['The failing test is flaky: `billing`.'], 'k1')
    expect(publishNote(ws, record)).toEqual({ ok: false, error: 'NO_INSTRUCTION_FILE', detail: 'the project has no AGENTS.md or CLAUDE.md' })
    expect(readdirSync(ws)).toEqual([])
    expect(publishNote(ws, record, { create: true })).toEqual({ ok: true, file: join(ws, 'AGENTS.md'), created: true })
    expect(readFileSync(join(ws, 'AGENTS.md'), 'utf8')).toBe([
      LESSONS_BEGIN, '## Lessons', '', 'Approved in Harness from what agents did in this project. `harness pair lessons revert <id>` takes one back.', '',
      `<!-- lesson:${record.id} -->`, '- The failing test is flaky: `billing`.', `<!-- /lesson:${record.id} -->`, LESSONS_END, '',
    ].join('\n'))
  })

  it('adds a marked block to an existing AGENTS.md, keeps every other byte, and takes each note back exactly', () => {
    const original = '# API\n\nRun `npm test` before committing.'
    writeFileSync(join(ws, 'AGENTS.md'), original)
    writeFileSync(join(ws, 'CLAUDE.md'), '@AGENTS.md\n')
    const a = noteRecord(['first note'], 'k1')
    const b = noteRecord(['second note', 'with two lines'], 'k2')
    expect(publishNote(ws, a)).toEqual({ ok: true, file: join(ws, 'AGENTS.md') })
    expect(publishNote(ws, b)).toEqual({ ok: true, file: join(ws, 'AGENTS.md') })
    expect(publishNote(ws, b)).toEqual({ ok: true, file: join(ws, 'AGENTS.md') })   // again: replaced, not doubled
    const text = readFileSync(join(ws, 'AGENTS.md'), 'utf8')
    expect(text.startsWith(`${original}\n\n${LESSONS_BEGIN}\n`)).toBe(true)
    expect(text.split(`<!-- lesson:${b.id} -->`)).toHaveLength(2)
    expect(text).toContain(`<!-- lesson:${a.id} -->\n- first note\n<!-- /lesson:${a.id} -->\n<!-- lesson:${b.id} -->\n- second note\n- with two lines\n<!-- /lesson:${b.id} -->\n${LESSONS_END}\n`)
    expect(readFileSync(join(ws, 'CLAUDE.md'), 'utf8')).toBe('@AGENTS.md\n')
    expect(unpublishNote(ws, a.id)).toEqual({ ok: true, file: join(ws, 'AGENTS.md') })
    expect(readFileSync(join(ws, 'AGENTS.md'), 'utf8')).not.toContain('first note')
    expect(unpublishNote(ws, b.id)).toEqual({ ok: true, file: join(ws, 'AGENTS.md') })
    expect(readFileSync(join(ws, 'AGENTS.md'), 'utf8')).toBe(`${original}\n`)
    expect(unpublishNote(ws, 'ffff')).toEqual({ ok: true, file: null })
  })

  it('uses CLAUDE.md when that is the file the project has; never writes through a symlink; refuses edited markers', () => {
    writeFileSync(join(ws, 'CLAUDE.md'), '# Rules\n')
    const record = noteRecord(['note'], 'k1')
    expect(noteFile(ws)).toBe(join(ws, 'CLAUDE.md'))
    expect(publishNote(ws, record)).toMatchObject({ ok: true, file: join(ws, 'CLAUDE.md') })
    rmSync(join(ws, 'CLAUDE.md'))
    writeFileSync(join(other, 'AGENTS.md'), 'elsewhere\n')
    symlinkSync(join(other, 'AGENTS.md'), join(ws, 'AGENTS.md'))
    expect(publishNote(ws, record, { create: true })).toMatchObject({ ok: false, error: 'NOT_A_FILE' })
    expect(readFileSync(join(other, 'AGENTS.md'), 'utf8')).toBe('elsewhere\n')
    rmSync(join(ws, 'AGENTS.md'))
    writeFileSync(join(ws, 'AGENTS.md'), `x\n${LESSONS_BEGIN}\nhand edit\n`)
    expect(publishNote(ws, record)).toMatchObject({ ok: false, error: 'EDITED' })
    expect(readFileSync(join(ws, 'AGENTS.md'), 'utf8')).toBe(`x\n${LESSONS_BEGIN}\nhand edit\n`)
  })

  it('finds a note\'s project among the folders harnesses run in, by its hash', () => {
    expect(findProject(projectHash(ws), [other, ws])).toBe(ws)
    expect(findProject(projectHash(ws), [other])).toBeNull()
    expect(findProject(null, [ws])).toBeNull()
  })
})
