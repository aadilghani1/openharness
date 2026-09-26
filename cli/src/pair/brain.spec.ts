/**
 * P2 — triage and one key (daemons/BRAIN.md).
 *
 * Two machines, both with a REAL PairSensor and journal: this one (machine-a, where the window is) and
 * a laptop (machine-b) reached through a fake link that does what the sealed relay does — carries
 * `pair_*` requests and `pair_event` pushes, nothing else. A fake clock, a stubbed one-shot, and the
 * brain's local frames captured where `sendLocal` would deliver them.
 */
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { mkdtempSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { PairJournal } from './journal.js'
import { PairSensor, type PairSubject } from './sensor.js'
import { PairFleet, relayPairLinkOpener, type PairLinkOpener } from './fleet.js'
import { PairTriage, actionsFor, parseTriage, type PairOneShot } from './triage.js'
import { PairVoice, DONE_COOLDOWN_MS } from './voice.js'
import { PairBrain, type AnswerResult } from './brain.js'
import type { DaemonSay, PairEvent } from './protocol.js'
import { BackendSocket } from '../backendSocket.js'

type Frame = Record<string, unknown>

const SUBJECTS: Record<string, PairSubject> = {
  api: { name: 'api', engine: 'claude' },
  web: { name: 'web', engine: 'codex' },
}
const ask = (q: string, options = ['Yes', 'No']) => [{ key: q, q, options, multi: false }]

let dirs: string[] = []
function sensorFor(machineId: string): PairSensor {
  const dir = mkdtempSync(join(tmpdir(), `pair-${machineId}-`))
  dirs.push(dir)
  const sensor = new PairSensor({ machineId: () => machineId, journal: new PairJournal({ dir }), describe: (id) => SUBJECTS[id] ?? null, now: Date.now })
  sensor.setPair('tim')
  return sensor
}

/** The laptop, as the relay would carry it: sealed requests in, pushes out. */
function laptop() {
  const sensor = sensorFor('machine-b')
  const answers: Frame[] = []
  let answerReply: Frame = { error: 'UNSUPPORTED' }
  let seq = 0
  const links: Array<{ drop: () => void }> = []
  const open: PairLinkOpener = async (machineId, on) => {
    if (machineId !== 'machine-b') throw new Error('NO_PEER_LINK')
    const connId = `relay-${++seq}`
    let closed = false
    links.push({ drop: () => { if (!closed) { closed = true; sensor.unwatch(connId); on.closed('relay dropped') } } })
    return {
      request: async (type, payload) => {
        if (closed) throw new Error('closed')
        if (type === 'pair_watch') {
          if (payload.off) { sensor.unwatch(connId); return { ok: true } }
          return { snapshot: sensor.watch(connId, (event) => { if (closed) return false; on.event(structuredClone(event)); return true }) }
        }
        if (type === 'pair_journal') return { ...sensor.journal(payload) }
        if (type === 'pair_answer') { answers.push(payload); return answerReply }
        return { error: 'UNSUPPORTED' }
      },
      close: () => { closed = true; sensor.unwatch(connId) },
    }
  }
  return { sensor, open, answers, links, reply: (r: Frame) => { answerReply = r } }
}

function world(opts: { oneshot?: PairOneShot | null; answer?: (i: { agentId: string; requestId: string; choice: string }) => Promise<AnswerResult>; linked?: boolean } = {}) {
  const local = sensorFor('machine-a')
  const remote = laptop()
  const frames: Frame[] = []
  const toClient: Array<{ connId: string; frame: Frame }> = []
  let brain: PairBrain | null = null
  const fleet = new PairFleet({
    local: { machineId: () => 'machine-a', name: () => 'desk', snapshot: () => local.snapshot(), subscribe: (l) => local.subscribe(l), journal: (p) => local.journal(p) },
    machines: () => [{ machineId: 'machine-b', name: 'laptop', linked: opts.linked !== false }],
    open: remote.open,
    onChange: (change) => brain?.onFleetChange(change),
    now: Date.now,
  })
  const oneshot = opts.oneshot === undefined ? null : opts.oneshot
  const answer = vi.fn(opts.answer ?? (async () => ({ ok: true })))
  const triage = new PairTriage({ oneshot, now: Date.now })
  const voice = new PairVoice({ sendLocal: (f) => frames.push(f), now: Date.now })
  brain = new PairBrain({
    pairing: { enabled: () => local.enabled(), pairedDaemon: () => local.pairedDaemon() },
    fleet, triage, voice,
    sendLocal: (f) => frames.push(f),
    sendLocalTo: (connId, frame) => { toClient.push({ connId, frame }); return true },
    answer, now: Date.now,
  })
  const says = () => frames.filter((f) => f.type === 'daemon_say').map((f) => f.payload as DaemonSay)
  const unsays = () => frames.filter((f) => f.type === 'daemon_unsay').map((f) => f.payload as Frame)
  const act = async (payload: Frame): Promise<Frame> => {
    const replies: Frame[] = []
    await brain!.onAct(payload, (f) => replies.push(f))
    return replies[0].payload as Frame
  }
  return { local, remote, brain, fleet, frames, toClient, says, unsays, act, answer, triage }
}

const settle = async (ms = 1): Promise<void> => { await vi.advanceTimersByTimeAsync(ms) }

beforeEach(() => { vi.useFakeTimers({ now: 1_000_000 }) })
afterEach(() => {
  vi.useRealTimers()
  for (const dir of dirs) rmSync(dir, { recursive: true, force: true })
  dirs = []
})

describe('triage', () => {
  const question = { requestId: 'q1', text: 'Bash: npm test', options: ['1. Yes', '2. No, and tell Claude what to do'], multi: false, deny: false, since: 0 }
  const input = { daemonId: 'tim', machineId: 'machine-a', who: 'api', engine: 'claude', question, present: true }

  it('uses one small model call, cached per requestId', async () => {
    const oneshot = vi.fn<PairOneShot>(async () => '{"line": "api wants to run the tests. harmless.", "recommend": "1. Yes"}')
    const triage = new PairTriage({ oneshot, now: Date.now })
    const first = await triage.triage(input)
    const again = await triage.triage(input)
    expect(first).toEqual({ line: 'api wants to run the tests. harmless. [y/n]', recommend: '1. Yes', tier: 1,
      actions: [{ key: 'y', label: 'Yes', choice: '1. Yes' }, { key: 'n', label: 'No, and tell Claude what to do', choice: '2. No, and tell Claude what to do' }] })
    expect(again).toBe(first)
    expect(oneshot).toHaveBeenCalledTimes(1)
    const prompt = oneshot.mock.calls[0][0]
    expect(prompt).toContain('<question>\nBash: npm test\n</question>')
    expect(prompt.length).toBeLessThan(4_500)   // ~1k tokens
  })

  it('falls back to the template whole on a timeout', async () => {
    const triage = new PairTriage({ oneshot: () => new Promise(() => {}), now: Date.now })
    const pending = triage.triage(input)
    await settle(2_500)
    expect(await pending).toMatchObject({ tier: 0, why: 'timeout', recommend: null, line: 'api needs you. bash: npm test [y/n]' })
  })

  it.each([
    ['bad JSON', 'sure! api wants to run tests', 'bad-json'],
    ['an off-list suggestion', '{"line": "api wants to run the tests.", "recommend": "Yes, and always allow rm"}', 'off-list'],
    ['a line that is not a line', '{"line": "", "recommend": null}', 'bad-line'],
  ])('falls back to the template whole on %s', async (_name, reply, why) => {
    const triage = new PairTriage({ oneshot: async () => reply, now: Date.now })
    const result = await triage.triage(input)
    expect(result).toMatchObject({ tier: 0, why, recommend: null })
    expect(result.line).toBe('api needs you. bash: npm test [y/n]')
  })

  it('never sends a deny-class prompt to the model, never recommends it, and never offers [y]', async () => {
    const oneshot = vi.fn<PairOneShot>(async () => '{"line": "ship it", "recommend": "1. Yes"}')
    const triage = new PairTriage({ oneshot, now: Date.now })
    const result = await triage.triage({ ...input, question: { ...question, requestId: 'q-push', text: 'Bash: git push --force origin main', deny: true } })
    expect(oneshot).not.toHaveBeenCalled()
    expect(result).toMatchObject({ tier: 0, why: 'deny', recommend: null })
    expect(result.actions.map((a) => a.key)).toEqual(['n'])
    expect(result.line).toMatch(/\[n\]$/)
    expect(result.line).not.toContain('[y')
  })

  it('does not call the model while nobody is at the computer, nor past the hourly cap', async () => {
    const oneshot = vi.fn<PairOneShot>(async () => '{"line": "api wants to run the tests.", "recommend": null}')
    const triage = new PairTriage({ oneshot, now: Date.now, hourlyCap: 2 })
    expect(await triage.triage({ ...input, present: false })).toMatchObject({ tier: 0, why: 'absent' })
    for (const id of ['a', 'b', 'c']) await triage.triage({ ...input, question: { ...question, requestId: id } })
    expect(oneshot).toHaveBeenCalledTimes(2)
    expect(await triage.triage({ ...input, question: { ...question, requestId: 'd' } })).toMatchObject({ tier: 0, why: 'cap' })
    await settle(60 * 60_000)
    expect(await triage.triage({ ...input, question: { ...question, requestId: 'e' } })).toMatchObject({ tier: 1 })
  })

  it('offers keys only a person can check: [y] is the recommendation or a plain yes, [n] a plain no', () => {
    const q = (options: string[], extra = {}) => ({ ...question, options, ...extra })
    expect(actionsFor(q(['Yes', 'No']), 'No').map((a) => a.key)).toEqual(['n'])
    expect(actionsFor(q(['Postgres', 'SQLite']), null)).toEqual([])
    expect(actionsFor(q(['Postgres', 'SQLite']), 'SQLite')).toEqual([{ key: 'y', label: 'SQLite', choice: 'SQLite' }])
    expect(actionsFor(q(['Yes', 'No'], { multi: true }), 'Yes').map((a) => a.key)).toEqual(['n'])
    expect(parseTriage('{"line":"x","recommend":"2. no, and tell claude what to do"}', question.options))
      .toEqual({ line: 'x', recommend: '2. No, and tell Claude what to do' })
  })
})

describe('voice', () => {
  it('never repeats a line, keeps the done cooldown, and caps what it says per minute', () => {
    const frames: Frame[] = []
    const voice = new PairVoice({ sendLocal: (f) => frames.push(f), now: Date.now })
    const say = (id: string, mood: DaemonSay['mood']) => voice.say({ id, mood, line: id, actions: [], ttlMs: 30_000, about: { machineId: 'm', agentId: 'a' } })
    expect(say('done:1', 'done')).toBe(true)
    expect(say('done:1', 'done')).toBe(false)
    expect(say('done:2', 'done')).toBe(false)
    vi.advanceTimersByTime(DONE_COOLDOWN_MS)
    expect(say('done:2', 'done')).toBe(true)
    for (let i = 0; i < 4; i++) expect(say(`fail:${i}`, 'fail')).toBe(true)
    expect(say('fail:x', 'fail')).toBe(false)        // six in a minute
    expect(say('need:x', 'need')).toBe(true)         // a question still gets through
    expect(frames.filter((f) => f.type === 'daemon_say')).toHaveLength(7)
    expect(voice.unsay('need:x', 'answered')).toBe(true)
    expect(voice.unsay('need:x', 'answered')).toBe(false)
  })
})

describe('the brain', () => {
  it('says a new question once, with its keys, and puts it in daemon_state', async () => {
    const w = world()
    w.brain.clientAttached('local:window')
    await settle()
    w.remote.sensor.turnStarted('api')
    w.remote.sensor.question('api', 'q_1', ask('Bash: npm test'))
    await settle(200)
    expect(w.says()).toEqual([expect.objectContaining({
      mood: 'need', line: 'api@laptop needs you. bash: npm test [y/n]',
      about: { machineId: 'machine-b', agentId: 'api', requestId: 'q_1' },
      actions: [{ key: 'y', label: 'Yes', choice: 'Yes' }, { key: 'n', label: 'No', choice: 'No' }],
    })])
    const state = w.frames.filter((f) => f.type === 'daemon_state').at(-1)!.payload as Frame
    expect(state).toMatchObject({ pair: 'tim', working: 0, needs: [{ machineId: 'machine-b', machine: 'laptop', agentId: 'api',
      requestId: 'q_1', question: 'Bash: npm test', id: w.says()[0].id }] })
    expect((state.machines as Frame[]).map((m) => [m.machineId, m.status])).toEqual([['machine-a', 'ok'], ['machine-b', 'ok']])
  })

  it('a reconnect does not repeat a line — neither the laptop\'s relay nor the window', async () => {
    const w = world()
    w.brain.clientAttached('local:window')
    await settle()
    w.remote.sensor.question('api', 'q_1', ask('Bash: npm test'))
    await settle(200)
    expect(w.says()).toHaveLength(1)
    // The relay drops; the laptop is reached again on the next sync and its snapshot still holds the question.
    w.remote.links[0].drop()
    await settle(61_000)
    expect(w.fleet.machines().find((m) => m.machineId === 'machine-b')?.status).toBe('ok')
    // The window reconnects: it is sent the state, not the line again.
    w.brain.clientDetached('local:window')
    w.brain.clientAttached('local:window')
    await settle(200)
    expect(w.says()).toHaveLength(1)
    // It is handed the state at once, and the state again once the laptop has answered.
    expect(w.toClient.filter((t) => t.frame.type === 'daemon_state')).toHaveLength(2)
    expect(w.frames.filter((f) => f.type === 'daemon_state').at(-1)?.payload).toMatchObject({ needs: [{ requestId: 'q_1' }] })
  })

  it('a question already open when the brain starts watching is a baseline: no line', async () => {
    const w = world()
    w.remote.sensor.question('api', 'q_old', ask('Allow the edit?'))
    w.local.question('web', 'q_mine', ask('Allow the read?'))
    w.brain.clientAttached('local:window')
    await settle(200)
    expect(w.says()).toEqual([])
    expect((w.brain.state().needs as unknown[]).length).toBe(2)
  })

  it('says a finished turn with its recap, a failure with its reason, and nothing for an interrupt', async () => {
    const w = world()
    w.brain.clientAttached('local:window')
    await settle()
    w.local.turnStarted('web')
    w.local.turnEnded('web')
    w.local.recap('web', 'Fixed the login redirect.')
    w.local.turnStarted('api')
    w.local.turnEnded('api', { aborted: true })
    await settle(DONE_COOLDOWN_MS)
    w.remote.sensor.failed('api', 'the engine exited')
    await settle(2_000)
    expect(w.says().map((s) => [s.mood, s.line])).toEqual([
      ['done', 'web finished. fixed the login redirect.'],
      ['fail', 'api@laptop failed. the engine exited'],
    ])
  })

  it('answered elsewhere sends daemon_unsay', async () => {
    const w = world()
    w.brain.clientAttached('local:window')
    await settle()
    w.remote.sensor.question('api', 'q_1', ask('Bash: npm test'))
    await settle(200)
    const id = w.says()[0].id
    w.remote.sensor.questionGone('api', 'q_1')
    await settle(200)
    expect(w.unsays()).toEqual([{ id, reason: 'answered' }])
    expect(w.brain.state().needs).toEqual([])
  })

  it('daemon_act reaches the machine that owns the harness', async () => {
    const w = world()
    w.remote.reply({ ok: true })
    w.brain.clientAttached('local:window')
    await settle()
    w.remote.sensor.question('api', 'q_remote', ask('Bash: npm test'))
    w.local.question('web', 'q_local', ask('Read src/auth.ts?'))
    await settle(200)
    const [remoteSay, localSay] = w.says()
    expect(await w.act({ requestId: 'r1', id: remoteSay.id, choice: 'Yes' })).toEqual({ requestId: 'r1', id: remoteSay.id, ok: true, machineId: 'machine-b' })
    expect(w.remote.answers).toEqual([expect.objectContaining({ agentId: 'api', requestId: 'q_remote', expectRequestId: 'q_remote', choice: 'Yes' })])
    expect(w.answer).not.toHaveBeenCalled()
    expect(await w.act({ requestId: 'r2', id: localSay.id, choice: 'n' })).toMatchObject({ ok: true, machineId: 'machine-a' })
    expect(w.answer).toHaveBeenCalledWith({ agentId: 'web', requestId: 'q_local', choice: 'No' })
    expect(w.unsays().map((u) => u.id)).toEqual([remoteSay.id, localSay.id])
  })

  it('a stale answer sends no keys: the question on the harness is no longer the one the line was about', async () => {
    const w = world()
    w.brain.clientAttached('local:window')
    await settle()
    w.local.question('web', 'q_first', ask('Read src/auth.ts?'))
    await settle(200)
    const first = w.says()[0]
    // The dialog moved on before the key arrived (the watcher reports a different question).
    w.local.question('web', 'q_second', ask('Bash: git push origin main'))
    expect(await w.act({ requestId: 'r1', id: first.id, choice: 'Yes' })).toMatchObject({ ok: false, error: expect.stringMatching(/GONE|STALE_QUESTION/) })
    expect(w.answer).not.toHaveBeenCalled()
  })

  it('refuses a key for a deny-class prompt whatever the client sends, and one never offered', async () => {
    const w = world()
    w.brain.clientAttached('local:window')
    await settle()
    w.local.question('web', 'q_push', ask('Bash: git push --force origin main'))
    await settle(200)
    const say = w.says()[0]
    expect(say.actions.map((a) => a.key)).toEqual(['n'])
    expect(await w.act({ requestId: 'r1', id: say.id, choice: 'Yes' })).toMatchObject({ ok: false, error: 'NOT_OFFERED' })
    expect(await w.act({ requestId: 'r2', id: say.id, choice: 'y' })).toMatchObject({ ok: false, error: 'NOT_OFFERED' })
    expect(w.answer).not.toHaveBeenCalled()
  })

  it('a laptop that is not linked is never dialled; one too old for the pair brain is named as such', async () => {
    const unlinked = world({ linked: false })
    const open = vi.spyOn(unlinked.remote, 'open')
    unlinked.brain.clientAttached('local:window')
    await settle()
    expect(open).not.toHaveBeenCalled()
    expect(unlinked.fleet.machines()[1].status).toBe('unlinked')

    let fleetStatus = ''
    const old = new PairFleet({
      local: { machineId: () => 'a', name: () => 'desk', snapshot: () => ({ machineId: 'a', epoch: 'e', seq: 0, rev: 0, harnesses: [] }), subscribe: () => () => {}, journal: () => ({ epoch: 'e', seq: 0, entries: [] }) },
      machines: () => [{ machineId: 'b', name: 'old-mac', linked: true }],
      open: async () => ({ request: async () => ({ error: 'UNSUPPORTED' }), close: () => {} }),
      onChange: (c) => { if (c.status) fleetStatus = c.status },
    })
    old.start()
    await settle()
    expect(fleetStatus).toBe('old')
    old.stop()
  })

  it('sends daemon_* only through sendLocal: nothing reaches the cloud queue', async () => {
    const socket = new BackendSocket('token')
    const internals = socket as unknown as { queue: Array<{ data: string }>; enqueue: (m: unknown) => void }
    const enqueued: string[] = []
    const enqueue = internals.enqueue.bind(socket)
    internals.enqueue = (msg: unknown) => { enqueued.push(JSON.stringify(msg)); enqueue(msg) }
    const windowFrames: Frame[] = []
    socket.registerLocalClient('local:window', { sendFrame: (f) => { windowFrames.push(f); return true }, sendBinary: () => true })
    const local = sensorFor(socket.machineId)
    let brain: PairBrain | null = null
    const fleet = new PairFleet({
      local: { machineId: () => socket.machineId, name: () => 'desk', snapshot: () => local.snapshot(), subscribe: (l) => local.subscribe(l), journal: (p) => local.journal(p) },
      machines: () => [], open: async () => { throw new Error('NO_PEER_LINK') }, onChange: (c) => brain?.onFleetChange(c),
    })
    brain = new PairBrain({
      pairing: { enabled: () => true, pairedDaemon: () => 'tim' }, fleet,
      triage: new PairTriage({ oneshot: null, now: Date.now }),
      voice: new PairVoice({ sendLocal: (f) => socket.sendLocal(f), now: Date.now }),
      sendLocal: (f) => socket.sendLocal(f), sendLocalTo: (c, f) => socket.sendLocalTo(c, f),
      answer: async () => ({ ok: false, error: 'UNSUPPORTED' }), now: Date.now,
    })
    socket.onLocalClient = (connId, attached) => attached ? brain!.clientAttached(connId) : brain!.clientDetached(connId)
    brain.clientAttached('local:window')
    local.turnStarted('api')
    local.question('api', 'q_1', ask('Bash: npm test'))
    await settle(200)
    local.questionGone('api', 'q_1')
    local.turnEnded('api')
    local.recap('api', 'ran the tests')
    local.failed('web', 'the engine exited')
    await settle(2_000)
    await brain.onAct({ requestId: 'r', id: 'nope', choice: 'y' }, (f) => { socket.sendLocalTo('local:window', f) })
    const types = windowFrames.map((f) => f.type)
    expect(types).toEqual(expect.arrayContaining(['daemon_state', 'daemon_say', 'daemon_unsay', 'daemon_act_result']))
    expect(enqueued.filter((m) => m.includes('daemon_'))).toEqual([])
    expect(internals.queue.map((q) => q.data).filter((d) => d.includes('daemon_'))).toEqual([])
    await socket.unregisterLocalClient('local:window')
    await socket.stop()
  })
})

describe('the relay opener', () => {
  it('correlates pair_* results by requestId, hands pair_event on, and stops the watch on close', async () => {
    const sent: Frame[] = []
    let sink: { sendFrame: (f: Frame) => boolean } | null = null
    let detached = false
    const events: PairEvent[] = []
    let n = 0
    const open = relayPairLinkOpener({
      acquire: async (_m, s) => { sink = s; return { send: async (f) => { sent.push(f) }, detach: () => { detached = true } } },
      newId: () => `id-${++n}`,
    })
    const link = await open('machine-b', { event: (e) => events.push(e), closed: () => {} })
    const pending = link.request('pair_journal', { at: 5 }, 1_000)
    expect(sent[0]).toEqual({ type: 'pair_journal', payload: { at: 5, requestId: 'id-1' } })
    sink!.sendFrame({ type: 'connected', payload: {} })
    sink!.sendFrame({ type: 'pair_event', payload: { machineId: 'machine-b', rev: 1, agentId: 'api', harness: null } })
    sink!.sendFrame({ type: 'pair_journal_result', payload: { requestId: 'id-1', entries: [] } })
    expect(await pending).toEqual({ requestId: 'id-1', entries: [] })
    expect(events).toHaveLength(1)
    const late = expect(link.request('pair_watch', {}, 500)).rejects.toThrow('timeout')
    await settle(500)
    await late
    link.close()
    expect(sent.at(-1)).toMatchObject({ type: 'pair_watch', payload: { off: true } })
    expect(detached).toBe(true)
  })
})
