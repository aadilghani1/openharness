import { describe, expect, it, vi } from 'vitest'
import { localDayHour, ZOO_TURN_FLUSH_MS, ZooTurnCounter, ZooTurnReporter, type ZooPost, type ZooTurnOp } from './zooTurns.js'

describe('ZooTurnCounter — which finished turns count', () => {
  const counter = (eligible: (id: string) => boolean = () => true) => new ZooTurnCounter({ eligible })

  it('counts a turn it saw start live and finish', () => {
    const c = counter()
    c.started('s1', { replay: false })
    expect(c.ended('s1', { replay: false, aborted: false })).toBe(true)
    expect(c.ended('s1', { replay: false, aborted: false })).toBe(false)          // one end, one count
  })

  it('never counts a replay, a turn picked up at attach, or an end it never saw start', () => {
    const c = counter()
    c.started('s1', { replay: true })
    expect(c.ended('s1', { replay: false, aborted: false })).toBe(false)
    c.started('s2', { replay: false })
    expect(c.ended('s2', { replay: true, aborted: false })).toBe(false)
    expect(c.ended('s3', { replay: false, aborted: false })).toBe(false)
    // A live start after a replayed one counts as usual.
    c.started('s1', { replay: false })
    expect(c.ended('s1', { replay: false, aborted: false })).toBe(true)
  })

  it('does not count a turn killed by an interrupt', () => {
    const c = counter()
    c.started('s1', { replay: false })
    expect(c.ended('s1', { replay: false, aborted: true })).toBe(false)
    c.started('s1', { replay: false })
    expect(c.ended('s1', { replay: false, aborted: false })).toBe(true)
  })

  it('asks whether the session is one a person drives when the turn ends', () => {
    const skip = new Set(['sub-agent', 'terminal', 'pair'])
    const eligible = vi.fn((id: string) => !skip.has(id))
    const c = counter(eligible)
    for (const id of ['sub-agent', 'terminal', 'pair', 'mine']) c.started(id, { replay: false })
    expect(eligible).not.toHaveBeenCalled()
    expect(['sub-agent', 'terminal', 'pair', 'mine'].map((id) => c.ended(id, { replay: false, aborted: false }))).toEqual([false, false, false, true])
  })

  it('forgets a session that went away mid-turn', () => {
    const c = counter()
    c.started('s1', { replay: false })
    c.forget('s1')
    expect(c.ended('s1', { replay: false, aborted: false })).toBe(false)
  })
})

describe('localDayHour', () => {
  it('reads the machine\'s local calendar day and hour', () => {
    expect(localDayHour(new Date(2026, 8, 26, 4, 59, 30))).toEqual({ day: '2026-09-26', hour: 4 })
    expect(localDayHour(new Date(2027, 0, 1, 0, 0, 1))).toEqual({ day: '2027-01-01', hour: 0 })
    expect(localDayHour(new Date(2026, 11, 31, 23, 59, 59))).toEqual({ day: '2026-12-31', hour: 23 })
  })
})

/** A reporter on a fake clock, fake timers and a fake backend. */
function harness(opts: { answers?: Array<{ status: number; body?: Record<string, unknown> } | Error>; signedIn?: boolean } = {}) {
  let now = new Date(2026, 8, 26, 10, 0, 0)
  let signedIn = opts.signedIn ?? true
  const timers: Array<{ fn: () => void; ms: number; cleared: boolean }> = []
  const answers = [...(opts.answers ?? [])]
  const posts: ZooTurnOp[][] = []
  const post = vi.fn<ZooPost>(async (body) => {
    posts.push(body.ops.map((op) => ({ ...op })))
    const next = answers.shift() ?? { status: 200, body: { success: true, data: { revision: 1, grants: [], levelUps: [] } } }
    if (next instanceof Error) throw next
    return { status: next.status, body: next.body ?? {} }
  })
  let ids = 0
  const log = vi.fn()
  const reporter = new ZooTurnReporter({
    post,
    signedIn: () => signedIn,
    machineId: () => 'mac-1',
    now: () => now,
    setTimer: (fn, ms) => { const t = { fn, ms, cleared: false }; timers.push(t); return t },
    clearTimer: (t) => { (t as { cleared: boolean }).cleared = true },
    newBatchId: () => `b${++ids}`,
    log,
  })
  const armed = () => timers.filter((t) => !t.cleared)
  return {
    reporter, post, posts, log,
    at: (d: Date) => { now = d },
    signOut: () => { signedIn = false },
    armed,
    /** Let the minute pass: fire the armed timer and wait for the report it starts. */
    async tick() {
      const live = armed()
      expect(live).toHaveLength(1)
      expect(live[0].ms).toBe(ZOO_TURN_FLUSH_MS)
      live[0].cleared = true
      live[0].fn()
      await reporter.idle()
    },
  }
}

describe('ZooTurnReporter — reporting counted turns', () => {
  it('gathers a minute of turns into one zoo.turn for the local day and hour', async () => {
    const h = harness()
    h.reporter.count()
    h.reporter.count()
    h.reporter.count()
    expect(h.post).not.toHaveBeenCalled()
    expect(h.armed()).toHaveLength(1)                                          // one timer for the minute
    expect(h.reporter.waiting).toEqual({ counted: 3, pending: 0 })
    await h.tick()
    expect(h.posts).toEqual([[{ op: 'zoo.turn', batchId: 'b1', n: 3, day: '2026-09-26', hour: 10, machineId: 'mac-1' }]])
    expect(h.reporter.waiting).toEqual({ counted: 0, pending: 0 })
    expect(h.armed()).toHaveLength(0)                                          // quiet until the next turn
    expect(h.log).toHaveBeenCalledWith('[zoo] reported 3 turns (1 batch)')
  })

  it('splits a minute that crosses an hour or a day into one op each', async () => {
    const h = harness()
    h.at(new Date(2026, 8, 26, 23, 59, 40)); h.reporter.count()
    h.at(new Date(2026, 8, 27, 0, 0, 5)); h.reporter.count(); h.reporter.count()
    await h.tick()
    expect(h.posts[0].map(({ n, day, hour }) => ({ n, day, hour }))).toEqual([
      { n: 1, day: '2026-09-26', hour: 23 },
      { n: 2, day: '2026-09-27', hour: 0 },
    ])
    expect(new Set(h.posts[0].map((op) => op.batchId)).size).toBe(2)
  })

  it('never sends more than 50 turns in one op', async () => {
    const h = harness()
    for (let i = 0; i < 120; i++) h.reporter.count()
    await h.tick()
    expect(h.posts[0].map((op) => op.n)).toEqual([50, 50, 20])
  })

  it('counts nothing while signed out, and drops what was waiting when the account signs out', async () => {
    const guest = harness({ signedIn: false })
    guest.reporter.count()
    expect(guest.armed()).toHaveLength(0)
    await guest.reporter.flush()
    expect(guest.post).not.toHaveBeenCalled()
    const h = harness()
    h.reporter.count()
    h.signOut()
    await h.tick()
    expect(h.post).not.toHaveBeenCalled()
    expect(h.reporter.waiting).toEqual({ counted: 0, pending: 0 })
  })

  it('retries a report that failed with the same batch ids, beside the next minute\'s turns', async () => {
    const h = harness({ answers: [{ status: 502, body: { success: false, error: { code: 'BACKEND_UNREACHABLE' } } }, new Error('socket hang up')] })
    h.reporter.count(); h.reporter.count()
    await h.tick()
    expect(h.reporter.waiting).toEqual({ counted: 0, pending: 1 })
    expect(h.armed()).toHaveLength(1)                                          // it tries again in a minute
    expect(h.log).toHaveBeenCalledWith('[zoo] could not report 2 turns (502 BACKEND_UNREACHABLE); retrying')
    h.at(new Date(2026, 8, 26, 10, 1, 30)); h.reporter.count()
    await h.tick()                                                             // the fetch itself throws
    await h.tick()                                                             // and then it lands
    expect(h.posts.map((ops) => ops.map((op) => `${op.batchId}:${op.n}`))).toEqual([['b1:2'], ['b1:2', 'b2:1'], ['b1:2', 'b2:1']])
    expect(h.reporter.waiting).toEqual({ counted: 0, pending: 0 })
    expect(h.armed()).toHaveLength(0)
  })

  it('drops a report the server refuses or that finds the account signed out, rather than resending it forever', async () => {
    for (const status of [400, 401, 403]) {
      const h = harness({ answers: [{ status, body: { success: false, error: { code: 'X' } } }] })
      h.reporter.count()
      await h.tick()
      expect(h.reporter.waiting).toEqual({ counted: 0, pending: 0 })
      expect(h.armed()).toHaveLength(0)
      expect(h.log).toHaveBeenCalledWith(`[zoo] dropped 1 turn: ${status} X`)
    }
  })

  it('stops retrying a day the server would no longer take, and keeps at most 64 ops waiting', async () => {
    const h = harness({ answers: Array.from({ length: 80 }, () => ({ status: 504 })) })
    h.reporter.count()
    await h.tick()
    h.at(new Date(2026, 8, 29, 9, 0, 0))                                       // three days later
    h.reporter.count()
    await h.tick()
    expect(h.posts.at(-1)!.map((op) => op.day)).toEqual(['2026-09-29'])
    for (let i = 0; i < 70; i++) {
      h.at(new Date(2026, 8, 29, 9, i % 60, 0))
      h.reporter.count()
      await h.tick()
    }
    expect(h.posts.at(-1)).toHaveLength(64)
    expect(h.posts.at(-1)!.at(-1)!.batchId).toBe('b72')
  })

  it('sends one report at a time', async () => {
    let release!: () => void
    const h = harness()
    h.post.mockImplementationOnce(async (body) => {
      h.posts.push(body.ops.map((op) => ({ ...op })))
      await new Promise<void>((resolve) => { release = resolve })
      return { status: 200, body: {} }
    })
    h.reporter.count()
    const first = h.reporter.flush()
    await vi.waitFor(() => expect(h.post).toHaveBeenCalledOnce())
    h.reporter.count()
    const second = h.reporter.flush()
    await Promise.resolve()
    expect(h.post).toHaveBeenCalledOnce()
    release()
    await Promise.all([first, second])
    expect(h.posts.map((ops) => ops.map((op) => op.batchId))).toEqual([['b1'], ['b2']])
  })

  it('stops counting when stopped, and still sends what was waiting on a last flush', async () => {
    const h = harness()
    h.reporter.count()
    h.reporter.stop()
    expect(h.armed()).toHaveLength(0)
    h.reporter.count()
    await h.reporter.flush()
    expect(h.posts).toEqual([[expect.objectContaining({ n: 1 })]])
  })
})
