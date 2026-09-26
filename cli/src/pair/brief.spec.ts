/**
 * P3 — the brief on return (daemons/BRAIN.md): the wording, an unreachable machine named, nothing for
 * an absence under 15 minutes, nothing after a restart, and one brief per desk however many clients
 * come back. Real sensors and journals on two machines, a fake link, a fake clock, a stubbed one-shot.
 */
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { mkdtempSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { PairJournal } from './journal.js'
import { PairSensor, type PairSubject } from './sensor.js'
import { PairFleet, type PairLinkOpener } from './fleet.js'
import { PairTriage, type PairOneShot } from './triage.js'
import { PairVoice, backLine } from './voice.js'
import { PairBrain } from './brain.js'
import { composeBrief, parseBrief } from './brief.js'
import type { DaemonSay } from './protocol.js'

type Frame = Record<string, unknown>
const MIN = 60_000
const SUBJECTS: Record<string, PairSubject> = {
  api: { name: 'api', engine: 'claude' },
  web: { name: 'web', engine: 'codex' },
  docs: { name: 'docs', engine: 'claude' },
}
const ask = (q: string) => [{ key: q, q, options: ['Yes', 'No'], multi: false }]

let dirs: string[] = []
function journalDir(): string {
  const dir = mkdtempSync(join(tmpdir(), 'pair-brief-'))
  dirs.push(dir)
  return dir
}
function sensorAt(machineId: string, dir = journalDir()): PairSensor {
  const sensor = new PairSensor({ machineId: () => machineId, journal: new PairJournal({ dir }), describe: (id) => SUBJECTS[id] ?? null, now: Date.now })
  sensor.setPair('tim')
  return sensor
}

function world(opts: { oneshot?: PairOneShot; laptopHangs?: boolean; localDir?: string; remote?: PairSensor } = {}) {
  const local = sensorAt('machine-a', opts.localDir)
  const remote = opts.remote ?? sensorAt('machine-b')
  const open: PairLinkOpener = async (_machineId, on) => {
    const connId = `relay-${Math.random()}`
    return {
      request: async (type, payload) => {
        if (type === 'pair_watch') return { snapshot: remote.watch(connId, (e) => { on.event(structuredClone(e)); return true }) }
        if (type === 'pair_journal') return opts.laptopHangs ? new Promise(() => {}) : { ...remote.journal(payload) }
        return { error: 'UNSUPPORTED' }
      },
      close: () => remote.unwatch(connId),
    }
  }
  const frames: Frame[] = []
  let brain: PairBrain | null = null
  const fleet = new PairFleet({
    local: { machineId: () => 'machine-a', name: () => 'desk', snapshot: () => local.snapshot(), subscribe: (l) => local.subscribe(l), journal: (p) => local.journal(p) },
    machines: () => [{ machineId: 'machine-b', name: 'laptop', linked: true }],
    open, onChange: (c) => brain?.onFleetChange(c), now: Date.now,
  })
  const oneshot = opts.oneshot ? vi.fn(opts.oneshot) : null
  brain = new PairBrain({
    pairing: { enabled: () => true, pairedDaemon: () => 'tim' }, fleet,
    triage: new PairTriage({ oneshot, now: Date.now }),
    voice: new PairVoice({ sendLocal: (f) => frames.push(f), now: Date.now }),
    sendLocal: (f) => frames.push(f), sendLocalTo: () => true,
    answer: async () => ({ ok: false, error: 'UNSUPPORTED' }), now: Date.now,
  })
  const backs = () => frames.filter((f) => f.type === 'daemon_say' && (f.payload as DaemonSay).mood === 'back').map((f) => (f.payload as DaemonSay).line)
  const briefs = () => frames.filter((f) => f.type === 'daemon_brief').map((f) => f.payload as { line: string; items: Array<{ id: string; kind: string; line: string }> })
  return { local, remote, brain, fleet, frames, backs, briefs, oneshot }
}

const settle = async (ms = 1): Promise<void> => { await vi.advanceTimersByTimeAsync(ms) }

beforeEach(() => { vi.useFakeTimers({ now: 10_000_000 }) })
afterEach(() => {
  vi.useRealTimers()
  for (const dir of dirs) rmSync(dir, { recursive: true, force: true })
  dirs = []
})

/** The daemon has been up a while, the window is open, then the person leaves (window goes inactive). */
async function upAndAway(w: ReturnType<typeof world>): Promise<void> {
  await settle(20 * MIN)
  w.brain.clientAttached('local:window')
  await settle()
  w.brain.onPresence('local:window', { active: false })
}

describe('brief on return', () => {
  it('says the back line in the paired daemon\'s words: done, waiting and how long, nothing on fire', async () => {
    const w = world()
    await upAndAway(w)
    w.local.turnStarted('web'); w.local.turnEnded('web'); w.local.recap('web', 'Fixed the login redirect.')
    await settle(MIN)
    w.remote.turnStarted('docs'); w.remote.turnEnded('docs')
    await settle(4 * MIN)
    w.remote.question('api', 'q_1', ask('Bash: npm run migrate'))
    await settle(40 * MIN)
    w.brain.onPresence('local:window', { active: true, awayMs: 45 * MIN })
    await settle(10)
    expect(w.backs()).toEqual(['welcome back. 2 done, 1 waiting 40m. nothing on fire.'])
    expect(w.briefs()[0].items.map((i) => [i.kind, i.line])).toEqual([
      ['waiting', 'api@laptop asks: Bash: npm run migrate (40m)'],
      ['done', 'docs@laptop finished.'],
      ['done', 'web finished: Fixed the login redirect.'],
    ])
  })

  it('names a machine whose journal does not answer in 3 s, in place of "nothing on fire"', async () => {
    const w = world({ laptopHangs: true })
    await upAndAway(w)
    w.local.turnStarted('web'); w.local.turnEnded('web')
    await settle(30 * MIN)
    w.brain.onPresence('local:window', { active: true, awayMs: 30 * MIN })
    await settle(2_999)
    expect(w.backs()).toEqual([])
    await settle(2)
    expect(w.backs()).toEqual(['welcome back. 1 done, 0 waiting. laptop unreachable.'])
    expect(w.briefs()[0].items.map((i) => i.kind)).toEqual(['unreachable', 'done'])
  })

  it('says nothing for an absence under 15 minutes', async () => {
    const w = world()
    await upAndAway(w)
    w.local.turnStarted('web'); w.local.turnEnded('web')
    await settle(14 * MIN)
    w.brain.onPresence('local:window', { active: true, awayMs: 14 * MIN })
    await settle(4_000)
    expect(w.backs()).toEqual([])
    expect(w.briefs()).toEqual([])
  })

  it('says nothing after a restart: an absence that began before this daemon did is a baseline', async () => {
    const localDir = journalDir()
    const before = sensorAt('machine-a', localDir)
    before.turnStarted('web'); before.turnEnded('web')
    await settle(40 * MIN)
    // The daemon restarts; the window reconnects to it and reports the person was away for 40 minutes.
    const w = world({ localDir })
    w.brain.clientAttached('local:window')
    w.brain.onPresence('local:window', { active: true, awayMs: 40 * MIN })
    await settle(4_000)
    expect(w.backs()).toEqual([])
    expect(w.briefs()).toEqual([])
  })

  it('briefs a desk once: a second client coming back, or a reconnect, does not repeat it', async () => {
    const w = world()
    await upAndAway(w)
    w.local.turnStarted('web'); w.local.turnEnded('web')
    await settle(20 * MIN)
    w.brain.onPresence('local:window', { active: true, awayMs: 20 * MIN })
    w.brain.clientAttached('local:hn')
    w.brain.onPresence('local:hn', { active: true, awayMs: 20 * MIN })
    await settle(4_000)
    expect(w.backs()).toHaveLength(1)
  })

  it('a window reconnecting after 15 minutes or more is a return', async () => {
    const w = world()
    await settle(20 * MIN)
    w.brain.clientAttached('local:window')
    await settle()
    w.brain.clientDetached('local:window')
    w.remote.turnStarted('docs'); w.remote.turnEnded('docs')
    await settle(16 * MIN)
    w.brain.clientAttached('local:window')
    await settle(4_000)
    expect(w.backs()).toEqual(['welcome back. 1 done, 0 waiting. nothing on fire.'])
  })

  it('asks the model once for 3+ items, a failure or a question — and uses the template if its answer is off', async () => {
    const quiet = world({ oneshot: async () => '{"items": []}' })
    await upAndAway(quiet)
    quiet.local.turnStarted('web'); quiet.local.turnEnded('web')
    await settle(20 * MIN)
    quiet.brain.onPresence('local:window', { active: true, awayMs: 20 * MIN })
    await settle(4_000)
    expect(quiet.oneshot).not.toHaveBeenCalled()                 // one item, nothing wrong: no call
    expect(quiet.briefs()[0].items).toEqual([expect.objectContaining({ kind: 'done', line: 'web finished.' })])

    const failing = world({ oneshot: async (prompt) => {
      const ids = [...prompt.matchAll(/^(\S+:\S+) \|/gm)].map((m) => m[1])
      return JSON.stringify({ items: ids.map((id) => ({ id, line: `rewritten ${id.split(':')[0]}` })) })
    } })
    await upAndAway(failing)
    failing.local.failed('web', 'the engine exited')
    await settle(20 * MIN)
    failing.brain.onPresence('local:window', { active: true, awayMs: 20 * MIN })
    await settle(4_000)
    expect(failing.oneshot).toHaveBeenCalledTimes(1)
    expect(failing.backs()).toEqual(['welcome back. 0 done, 0 waiting. web failed.'])
    expect(failing.briefs()[0].items.map((i) => i.line)).toEqual(['rewritten failed'])

    const garbled = world({ oneshot: async () => '{"items": [{"id": "made-up", "line": "all good"}]}' })
    await upAndAway(garbled)
    garbled.local.failed('web', 'the engine exited')
    await settle(20 * MIN)
    garbled.brain.onPresence('local:window', { active: true, awayMs: 20 * MIN })
    await settle(4_000)
    expect(garbled.briefs()[0].items.map((i) => i.line)).toEqual(['web failed: the engine exited'])
  })
})

describe('brief wording', () => {
  it('composes facts from journals and the fleet, and every daemon says them', () => {
    const now = 100 * MIN
    const { facts, items } = composeBrief({
      journals: [
        { machineId: 'a', machine: 'desk', local: true, entries: [
          { epoch: 'e', seq: 1, at: now - 30 * MIN, kind: 'done', agentId: 'web', name: 'web', engine: 'codex' },
          { epoch: 'e', seq: 2, at: now - 20 * MIN, kind: 'done', agentId: 'web', name: 'web', engine: 'codex' },
          { epoch: 'e', seq: 3, at: now - 20 * MIN, kind: 'done', agentId: 'api', name: 'api', engine: 'claude', text: 'interrupted' },
        ] },
        { machineId: 'b', machine: 'laptop', local: false, entries: [], error: 'unreachable' },
      ],
      harnesses: [], machines: [{ machineId: 'a', name: 'desk', status: 'ok', local: true }, { machineId: 'b', name: 'laptop', status: 'ok', local: false }],
      awayMs: 45 * MIN, now,
    })
    expect(facts).toMatchObject({ done: 1, waiting: 0, failed: [], unreachable: ['laptop'], machines: 2 })
    expect(items.map((i) => i.line)).toEqual(['laptop did not answer.', 'web finished 2 turns.'])
    expect(backLine('ping', facts)).toBe('you\'re back. 1 reply, 0 waiting, 50% loss.')
    expect(backLine('vim', facts)).toBe(':earlier 45m 1 done, 0 waiting. laptop unreachable.')
    expect(backLine('grue', facts)).toBe('you came back to the dark. brave. 1 done. laptop unreachable.')
    expect(parseBrief('{"items":[{"id":"x","line":"ok"}]}', [{ id: 'x', kind: 'done', machineId: 'a', machine: 'desk', line: 't' }])).toEqual(new Map([['x', 'ok']]))
    expect(parseBrief('not json', [])).toBeNull()
  })
})
