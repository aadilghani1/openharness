/**
 * L1 PROPOSE, TEACH, REVERT (daemons/LEARNING.md): one line for a pending lesson — at most one an hour,
 * never over a `need`, never about the pane you are looking at — and what [y], [n] and [s] do; the brain
 * routing a key to the learner; `harness pair lessons` through the control interface and the CLI.
 * A real lessons folder (real git) in a temp dir, a real PairVoice, a fake clock.
 */
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { LessonDistiller } from './distill.js'
import { LessonStore, type LessonRecord } from './store.js'
import { PairLearner, joinProposals, LESSON_ASK_TTL_MS, LESSON_PROPOSAL_GAP_MS, LESSON_REPROPOSE_MS, DISTILL_EVERY_MS, SIGNAL_MAX_WAIT_MS } from './propose.js'
import { LESSONS_BEGIN } from './publish.js'
import { projectHash, type Signal } from './types.js'
import { PairVoice, DISPLAY_MS } from '../voice.js'
import { PairBrain } from '../brain.js'
import { PairControl, type ControlDeps } from '../control.js'
import { PairToken } from '../token.js'
import { pairCommand, parsePairArgs, PairUsageError, type PairSocket } from '../client.js'
import type { PairFleet } from '../fleet.js'
import type { PairTriage } from '../triage.js'
import type { Autonomy } from '../floor.js'
import type { DaemonSay } from '../protocol.js'

type Frame = Record<string, unknown>

let dir: string
let ws: string
beforeEach(() => {
  dir = realpathSync(mkdtempSync(join(tmpdir(), 'learn-propose-')))
  ws = join(dir, 'code', 'api')
  mkdirSync(ws, { recursive: true })
  vi.useFakeTimers({ now: Date.UTC(2026, 9, 3, 15, 0) })
})
afterEach(() => { vi.useRealTimers(); rmSync(dir, { recursive: true, force: true }) })

let signalSeq = 0
function stepsSignal(agentId = 'a1', steps = ['npm run db:reset', 'npm run migrate', 'npm test']): Signal {
  const project = projectHash(ws)
  return {
    kind: 'repeat-steps', key: `steps:${project}:${steps.join('>')}:${++signalSeq}`, project, projectName: 'api', at: Date.now(), steps,
    from: [1, 2, 3].map((turn) => ({ engine: turn === 2 ? 'codex' : 'claude', machine: 'desk', agentId, session: 's', turn, project, at: Date.now() })),
    evidence: [steps.join(' ; ')],
  }
}
function failureSignal(agentId = 'b1'): Signal {
  const project = projectHash(ws)
  return {
    kind: 'repeat-failure', key: `fail:test:${project}:billing:${++signalSeq}`, project, projectName: 'api', at: Date.now(),
    from: [{ engine: 'claude', machine: 'desk', agentId, session: 's', turn: 1, project, at: Date.now() }, { engine: 'codex', machine: 'desk', agentId: 'c1', session: 't', turn: 2, project, at: Date.now() }],
    evidence: ['npm test -> FAIL billing'], failure: { what: 'test', name: 'src/billing.spec.ts > rounds cents' },
  }
}

function world(opts: { autonomy?: Autonomy; present?: boolean } = {}) {
  let autonomy: Autonomy = opts.autonomy ?? 'suggest'
  let present = opts.present !== false
  let busy = false
  const focused = new Set<string>()
  const frames: Frame[] = []
  const voice = new PairVoice({ sendLocal: (f) => frames.push(f), now: Date.now })
  let ids = 0
  const store = new LessonStore({ root: join(dir, 'home', '.harness', 'lessons'), now: Date.now, newId: () => `beef${(++ids).toString(16).padStart(2, '0')}`, env: { PATH: process.env.PATH } })
  const learned = vi.fn()
  const credit = vi.fn()
  const changed = vi.fn()
  const learner = new PairLearner({
    store, distiller: new LessonDistiller({ now: Date.now }), pairedDaemon: () => 'tim', autonomy: () => autonomy,
    voice, sendLocal: (f) => frames.push(f), present: () => present, focused: (agentId) => focused.has(agentId), busy: () => busy,
    projects: () => [join(dir, 'code', 'web'), ws], learned, credit, machineId: () => 'machine-a', changed, home: join(dir, 'home'), now: Date.now,
  })
  const says = () => frames.filter((f) => f.type === 'daemon_say').map((f) => f.payload as DaemonSay)
  const add = async (signal: Signal): Promise<LessonRecord> => {
    learner.signal(signal)
    vi.advanceTimersByTime(DISTILL_EVERY_MS)
    await learner.tick()
    const record = store.pending().find((r) => r.signal.key === signal.key)
    if (!record) throw new Error('not pending')
    return record
  }
  return {
    learner, store, voice, frames, says, learned, credit, changed, focused, add,
    set: (patch: { autonomy?: Autonomy; present?: boolean; busy?: boolean }) => {
      if (patch.autonomy) autonomy = patch.autonomy
      if (patch.present !== undefined) present = patch.present
      if (patch.busy !== undefined) busy = patch.busy
    },
  }
}

describe('distilling waits for a quiet moment', () => {
  it('keeps a signal until nothing is working, or an hour has passed', async () => {
    const w = world({ present: false })
    w.set({ busy: true })
    w.learner.signal(stepsSignal())
    vi.advanceTimersByTime(DISTILL_EVERY_MS)
    await w.learner.tick()
    expect(w.store.pending()).toEqual([])
    vi.advanceTimersByTime(SIGNAL_MAX_WAIT_MS)
    await w.learner.tick()
    expect(w.store.pending().map((r) => r.name)).toEqual(['run-npm-run-db-reset-before-npm-test'])
    expect(w.store.pending()[0]!.learnedBy).toBe('tim')
  })

  it('a correction without the model is noticed and teaches nothing', async () => {
    const w = world()
    w.learner.signal({ ...stepsSignal(), kind: 'correction', steps: undefined, correction: { said: 'no, x', before: [] } })
    vi.advanceTimersByTime(DISTILL_EVERY_MS)
    await w.learner.tick()
    expect(w.store.list()).toEqual([])
    expect(w.says()).toEqual([])
  })
})

describe('propose: one line, when every rule allows it', () => {
  it('says [y/n/s] for a pending lesson, as an ask, keys first', async () => {
    const w = world()
    const record = await w.add(stepsSignal())
    const [say] = w.says()
    expect(say).toMatchObject({ mood: 'ask', ttlMs: DISPLAY_MS, about: { machineId: 'machine-a', agentId: 'a1' } })
    expect(say!.line).toBe('[y/n/s] teach your agents "run-npm-run-db-reset-before-npm-test"? the same steps, 3 times in api.')
    expect(say!.actions.map((a) => [a.key, a.label])).toEqual([['y', 'teach'], ['n', 'skip'], ['s', 'show']])
    expect(w.learner.pending()).toEqual([{ id: say!.id, line: say!.line, actions: say!.actions }])
    expect(w.store.proposedAt(record.id)).toBe(Date.now())
    expect(w.changed).toHaveBeenCalled()
  })

  it('at most one lesson an hour, even once the first is answered', async () => {
    const w = world()
    await w.add(stepsSignal())
    await w.learner.act(w.says()[0]!.id, 'n')
    await w.add(failureSignal())
    expect(w.says()).toHaveLength(1)
    vi.advanceTimersByTime(LESSON_PROPOSAL_GAP_MS)
    await w.learner.tick()
    expect(w.says()).toHaveLength(2)
    expect(w.says()[1]!.line).toBe('[y/n/s] add a note to api\'s AGENTS.md? claude and codex hit the same failure.')
  })

  it('never while a need is showing, never about the focused pane, never at watch, never with nobody here', async () => {
    const w = world({ present: false })
    await w.add(stepsSignal('a1'))
    expect(w.says()).toEqual([])
    w.set({ present: true, autonomy: 'watch' })
    await w.learner.tick()
    expect(w.says()).toEqual([])
    w.set({ autonomy: 'suggest' })
    w.voice.say({ id: 'need:1', about: { machineId: 'machine-a', agentId: 'z' }, mood: 'need', line: '[g] api: Bash', actions: [], ttlMs: DISPLAY_MS })
    await w.learner.tick()
    expect(w.says().map((s) => s.mood)).toEqual(['need'])
    vi.advanceTimersByTime(DISPLAY_MS)
    w.focused.add('a1')
    await w.learner.tick()
    expect(w.says().map((s) => s.mood)).toEqual(['need'])
    w.focused.delete('a1')
    await w.learner.tick()
    expect(w.says().map((s) => s.mood)).toEqual(['need', 'ask'])
  })

  it('an unanswered proposal waits in asks for ten minutes, then comes back after a day', async () => {
    const w = world()
    await w.add(stepsSignal())
    vi.advanceTimersByTime(LESSON_ASK_TTL_MS)
    expect(w.learner.pending()).toEqual([])
    vi.advanceTimersByTime(LESSON_PROPOSAL_GAP_MS)
    await w.learner.tick()
    expect(w.says()).toHaveLength(1)
    vi.advanceTimersByTime(LESSON_REPROPOSE_MS)
    await w.learner.tick()
    expect(w.says()).toHaveLength(2)
  })
})

describe('the keys', () => {
  it('[y] approves: skills/<name>, one commit, the daemon credited in the journal, and it says so', async () => {
    const w = world()
    const record = await w.add(stepsSignal())
    const id = w.says()[0]!.id
    const result = await w.learner.act(id, 'y')
    expect(result).toMatchObject({ ok: true, learned: 'run-npm-run-db-reset-before-npm-test', kind: 'skill', published: { via: 'runtime', dir: '~/.harness/lessons/skills' } })
    expect(typeof result.commit).toBe('string')
    expect(existsSync(join(w.store.skillsDir, 'run-npm-run-db-reset-before-npm-test', 'SKILL.md'))).toBe(true)
    expect(w.learned).toHaveBeenCalledWith({ daemon: 'tim', lesson: expect.objectContaining({ id: record.id, status: 'approved' }) })
    expect(w.credit).toHaveBeenCalledWith('tim', expect.objectContaining({ id: record.id }))
    expect(w.frames).toContainEqual({ type: 'daemon_unsay', payload: { id, reason: 'answered' } })
    expect(w.says().at(-1)).toMatchObject({ mood: 'say', line: 'learned "run-npm-run-db-reset-before-npm-test". harness sessions on every engine will load it.' })
    expect(await w.learner.act(id, 'y')).toEqual({ ok: false, error: 'GONE' })
  })

  it('[n] skips it for good', async () => {
    const w = world()
    const signal = stepsSignal()
    const record = await w.add(signal)
    expect(await w.learner.act(w.says()[0]!.id, 'skip')).toEqual({ ok: true, id: record.id, skipped: record.name })
    expect(w.store.get(record.id)?.status).toBe('skipped')
    expect(w.learned).not.toHaveBeenCalled()
    w.learner.signal({ ...signal })
    vi.advanceTimersByTime(DISTILL_EVERY_MS)
    await w.learner.tick()
    expect(w.store.pending()).toEqual([])
  })

  it('[s] shows the lesson in a daemon_brief frame, and its keys keep working while it is read', async () => {
    const w = world()
    const record = await w.add(stepsSignal())
    const id = w.says()[0]!.id
    const shown = await w.learner.act(id, 's')
    expect(shown).toMatchObject({ ok: true, shown: true })
    expect(shown.lesson).toContain('name: run-npm-run-db-reset-before-npm-test')
    const brief = w.frames.find((f) => f.type === 'daemon_brief')!.payload as { line: string; items: Array<Frame> }
    expect(brief.line).toBe('lesson "run-npm-run-db-reset-before-npm-test", pending')
    expect(brief.items).toEqual([{ id, kind: 'lesson', machineId: 'machine-a', line: '[y/n] teach your agents "run-npm-run-db-reset-before-npm-test"? the same steps, 3 times in api.',
      actions: [{ key: 'y', label: 'teach', choice: 'y' }, { key: 'n', label: 'skip', choice: 'n' }], text: w.store.text(record) }])
    vi.advanceTimersByTime(LESSON_ASK_TTL_MS - 30_000)
    expect(await w.learner.act(id, 'y')).toMatchObject({ ok: true })
  })

  it('refuses a key it did not offer, one at watch, and a line that is gone', async () => {
    const w = world()
    await w.add(stepsSignal())
    const id = w.says()[0]!.id
    expect(await w.learner.act(id, 'g')).toEqual({ ok: false, error: 'NOT_OFFERED' })
    w.set({ autonomy: 'watch' })
    expect(await w.learner.act(id, 'y')).toEqual({ ok: false, error: 'AUTONOMY_WATCH' })
    expect(await w.learner.act('lesson:nope:1', 'y')).toEqual({ ok: false, error: 'GONE' })
  })
})

describe('teaching a note: only into an AGENTS.md or CLAUDE.md that is there', () => {
  it('approved without one: kept, nothing written, and the way to ask for a new file named', async () => {
    const w = world()
    const record = await w.add(failureSignal())
    const result = await w.learner.act(w.says()[0]!.id, 'y')
    expect(result).toMatchObject({ ok: true, kind: 'note', published: { ok: false, error: 'NO_INSTRUCTION_FILE' } })
    expect(result.line).toBe(`kept "note-${record.id}". api has no AGENTS.md: harness pair lessons approve ${record.id} --create writes one.`)
    expect(existsSync(join(ws, 'AGENTS.md'))).toBe(false)
    // The person asks for exactly that, at their terminal.
    expect(await w.learner.local({ action: 'approve', id: record.id, create: true, confirmed: true })).toMatchObject({ ok: true, published: { ok: true, file: join(ws, 'AGENTS.md').replace(join(dir, 'home'), '~'), created: true } })
    expect(readFileSync(join(ws, 'AGENTS.md'), 'utf8')).toContain('The failing test is flaky: `src/billing.spec.ts > rounds cents`')
  })

  it('approved with one: written into its block; reverted: taken back out and git-reverted', async () => {
    writeFileSync(join(ws, 'AGENTS.md'), '# API\n')
    const w = world()
    const record = await w.add(failureSignal())
    expect(await w.learner.act(w.says()[0]!.id, 'y')).toMatchObject({ ok: true, published: { ok: true, file: join(ws, 'AGENTS.md') } })
    expect(readFileSync(join(ws, 'AGENTS.md'), 'utf8')).toContain(LESSONS_BEGIN)
    const reverted = await w.learner.local({ action: 'revert', id: record.id })
    expect(reverted).toMatchObject({ ok: true, reverted: `note-${record.id}`, unpublished: { file: join(ws, 'AGENTS.md') } })
    expect(typeof reverted.commit).toBe('string')
    expect(readFileSync(join(ws, 'AGENTS.md'), 'utf8')).toBe('# API\n')
    expect(w.store.get(record.id)?.status).toBe('reverted')
  })
})

describe('harness pair lessons', () => {
  it('lists, shows, skips; approve needs the terminal\'s yes', async () => {
    const w = world({ present: false })
    const record = await w.add(stepsSignal())
    const list = await w.learner.local({ action: 'list' })
    expect(list).toMatchObject({ ok: true, root: '~/.harness/lessons', git: true, lessons: [{ id: record.id, status: 'pending', learnedBy: 'tim', signal: 'repeat-steps', project: 'api', from: ['claude@desk turn 1', 'codex@desk turn 2', 'claude@desk turn 3'] }] })
    expect(await w.learner.local({ action: 'show', id: record.id })).toMatchObject({ ok: true, text: expect.stringContaining('learnedBy: "tim"') })
    expect(await w.learner.local({ action: 'approve', id: record.id })).toMatchObject({ ok: false, error: 'CONFIRM' })
    expect(await w.learner.local({ action: 'show' })).toMatchObject({ ok: false, error: 'MISSING_ID' })
    expect(await w.learner.local({ action: 'teach', id: record.id })).toMatchObject({ ok: false, error: 'UNKNOWN_ACTION' })
    expect(await w.learner.local({ action: 'skip', id: record.id })).toMatchObject({ ok: true })
    expect(await w.learner.local({ action: 'revert', id: record.id })).toMatchObject({ ok: false, error: 'NOT_APPROVED' })
  })

  it('the control interface routes the verb with pairing off, and never lets the pair harness approve', async () => {
    const w = world()
    const token = new PairToken(join(dir, 'token'))
    const secret = token.rotate()
    const lessons = vi.fn((payload: Frame) => w.learner.local(payload))
    const control = new PairControl({
      owner: {} as ControlDeps['owner'], fleet: { isRunning: false } as unknown as ControlDeps['fleet'],
      local: { machineId: () => 'machine-a', name: () => 'desk', journal: () => ({ epoch: 'e', seq: 0, entries: [] }), harnesses: () => [] },
      pairing: { enabled: () => false, pairedDaemon: () => null }, autonomy: () => 'suggest', tokenMatches: (c) => token.matches(c),
      voice: { say: () => true, unsay: () => true }, present: () => true, started: { has: () => false, add: () => {} } as unknown as ControlDeps['started'],
      lessons, now: Date.now, newId: () => 'x',
    })
    expect(control.verbs.has('lessons')).toBe(true)
    expect(await control.local({ verb: 'lessons', action: 'list' })).toMatchObject({ ok: true, lessons: [] })
    expect(await control.local({ verb: 'lessons', action: 'approve', id: 'beef01', confirmed: true, token: secret })).toMatchObject({ ok: false, error: 'PERSON_ONLY' })
    expect(await control.local({ verb: 'lessons', action: 'show', id: 'beef01', token: secret })).toMatchObject({ ok: false, error: 'NOT_FOUND' })
    expect(lessons.mock.calls.every(([payload]) => !('token' in payload))).toBe(true)
  })

  it('the CLI parses the verbs, shows the lesson and asks before it approves', async () => {
    expect(parsePairArgs('lessons', []).payload).toEqual({ verb: 'lessons', action: 'list' })
    expect(parsePairArgs('lessons', ['approve', 'beef01', '--create', '--json'])).toEqual({ payload: { verb: 'lessons', action: 'approve', id: 'beef01', create: true }, json: true })
    expect(() => parsePairArgs('lessons', ['revert'])).toThrow(PairUsageError)
    expect(() => parsePairArgs('lessons', ['teach', 'x'])).toThrow(PairUsageError)
    const sent: Frame[] = []
    const connect = (): PairSocket => {
      const handlers: Record<string, (...args: never[]) => void> = {}
      const message = (frame: Frame) => queueMicrotask(() => (handlers.message as (d: { toString(): string }) => void)({ toString: () => JSON.stringify(frame) }))
      return {
        send: (data) => {
          const frame = JSON.parse(data) as { type: string; payload: Frame }
          if (frame.type === 'machine_select') message({ type: 'connected', payload: {} })
          if (frame.type === 'pair') {
            sent.push(frame.payload)
            const reply = frame.payload.action === 'show' ? { ok: true, text: '---\nname: x\n---\nDo it.\n' } : { ok: true, learned: 'x' }
            message({ type: 'pair_result', payload: { requestId: frame.payload.requestId, ...reply } })
          }
        },
        close: () => {},
        on: ((event: string, listener: (...args: never[]) => void) => { handlers[event] = listener; if (event === 'open') queueMicrotask(() => listener()) }) as PairSocket['on'],
      }
    }
    const out: string[] = []
    const errors: string[] = []
    const base = { port: 1, machineId: async () => 'machine-a', connect, env: {} as NodeJS.ProcessEnv, output: (l: string) => out.push(l), error: (l: string) => errors.push(l) }
    vi.useRealTimers()
    expect(await pairCommand(['lessons', 'approve', 'beef01', '--json'], base)).toBe(1)
    expect(out.pop()).toContain('"error":"CONFIRM"')
    expect(sent).toEqual([])
    expect(await pairCommand(['lessons', 'approve', 'beef01', '--json'], { ...base, confirm: async () => false })).toBe(1)
    expect(out.pop()).toBe('{"ok":false,"error":"DECLINED"}')
    const asked: string[] = []
    expect(await pairCommand(['lessons', 'approve', 'beef01', '--json'], { ...base, confirm: async (q) => { asked.push(q); return true } })).toBe(0)
    expect(asked).toEqual(['Teach lesson beef01 to your agents? [y/N] '])
    expect(errors).toContain('---\nname: x\n---\nDo it.\n')
    expect(sent.map(({ requestId: _r, ...p }) => p)).toEqual([
      { verb: 'lessons', action: 'show', id: 'beef01' },
      { verb: 'lessons', action: 'show', id: 'beef01' },
      { verb: 'lessons', action: 'approve', id: 'beef01', confirmed: true },
    ])
  })
})

describe('the brain routes a lesson key to the learner', () => {
  it('daemon_act on a lesson line answers with what was learned, and daemon_state lists the ask', async () => {
    const w = world()
    const control = { owns: (id: string) => id.startsWith('ask:'), act: vi.fn(async () => ({ ok: true })), pending: () => [] }
    const fleet = { start: () => {}, stop: () => {}, machines: () => [], harnesses: () => [], find: () => null } as unknown as PairFleet
    const sent: Frame[] = []
    const brain = new PairBrain({
      pairing: { enabled: () => true, pairedDaemon: () => 'tim' }, fleet, triage: {} as PairTriage, voice: w.voice,
      proposals: joinProposals(control, w.learner), sendLocal: (f) => sent.push(f), sendLocalTo: () => true,
      answer: async () => ({ ok: true }), now: Date.now,
    })
    brain.clientAttached('conn-1')
    await w.add(stepsSignal())
    const id = w.says()[0]!.id
    expect((brain.state().asks as Frame[]).map((a) => a.id)).toEqual([id])
    const replies: Frame[] = []
    await brain.onAct({ requestId: 'r1', id, choice: 'y' }, (f) => replies.push(f))
    expect(replies[0]).toEqual({ type: 'daemon_act_result', payload: { requestId: 'r1', id, ok: true, learned: 'run-npm-run-db-reset-before-npm-test' } })
    expect(control.act).not.toHaveBeenCalled()
    expect(brain.isFocused('machine-a', 'a1')).toBe(false)
  })
})
