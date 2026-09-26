/**
 * P4/P5 — the control interface (pair/control.ts): each tool maps to the right owner call or sealed RPC,
 * write tools are refused without the pair harness's token, and the autonomy matrix decides what runs,
 * what waits for a key, and what is refused.
 */
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { mkdtempSync, readFileSync, rmSync, statSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { CONTROL_TOOLS, PairControl, PROPOSAL_TTL_MS, StartedHarnesses, type ControlDeps } from './control.js'
import { PairToken } from './token.js'
import type { Autonomy } from './floor.js'
import type { DaemonSay } from './protocol.js'

type Result = Record<string, unknown>

let dir: string
beforeEach(() => { dir = mkdtempSync(join(tmpdir(), 'pair-control-')); vi.useFakeTimers({ now: 1_000_000 }) })
afterEach(() => { vi.useRealTimers(); rmSync(dir, { recursive: true, force: true }) })

function world(opts: { autonomy?: Autonomy; present?: boolean; fleet?: boolean } = {}) {
  let autonomy: Autonomy = opts.autonomy ?? 'suggest'
  const token = new PairToken(join(dir, 'token'))
  const secret = token.rotate()
  const owner = {
    list: vi.fn(() => [{ agentId: 'api', name: 'api', engine: 'claude', status: 'idle' as const }]),
    read: vi.fn((agentId: string) => ({ ok: true as const, harness: null, row: { agentId } })),
    answer: vi.fn(async () => ({ ok: true as const, option: '1. Yes' })),
    send: vi.fn(() => ({ ok: true as const, deliveryId: 'd1' })),
    stop: vi.fn(() => ({ ok: true as const })),
    start: vi.fn(async () => ({ ok: true as const, agentId: 'new-1' })),
    pause: vi.fn(async () => ({ ok: true as const })),
    resume: vi.fn(async () => ({ ok: true as const })),
  }
  const requests: Array<{ machineId: string; type: string; payload: Result }> = []
  const fleet = {
    isRunning: opts.fleet !== false,
    machines: () => [
      { machineId: 'machine-a', name: 'desk', status: 'ok' as const, local: true },
      { machineId: 'machine-b', name: 'laptop', status: 'ok' as const, local: false },
      { machineId: 'machine-c', name: 'mini', status: 'unreachable' as const, local: false },
    ],
    harnesses: () => [],
    request: vi.fn(async (machineId: string, type: string, payload: Result) => {
      requests.push({ machineId, type, payload })
      if (type === 'pair_list') return { harnesses: [{ agentId: 'web', name: 'web', engine: 'codex', status: 'waiting' }] }
      if (type === 'pair_start') return { ok: true, agentId: 'remote-new' }
      return { ok: true }
    }),
    journals: vi.fn(async () => [{ machineId: 'machine-a', machine: 'desk', local: true, entries: [
      { epoch: 'e', seq: 1, at: 999_000, kind: 'done' as const, agentId: 'api', name: 'api', engine: 'claude' },
      { epoch: 'e', seq: 2, at: 999_500, kind: 'act' as const, agentId: 'api', name: 'api', engine: 'claude', by: 'rule' as const, action: 'answer' as const, text: 'answered "Yes"' },
    ] }]),
  }
  const said: DaemonSay[] = []
  const unsaid: Array<{ id: string; reason: string }> = []
  let seq = 0
  const deps: ControlDeps = {
    owner, fleet: fleet as unknown as ControlDeps['fleet'],
    local: { machineId: () => 'machine-a', name: () => 'desk', journal: () => ({ epoch: 'e', seq: 0, entries: [] }), harnesses: () => [] },
    pairing: { enabled: () => true, pairedDaemon: () => 'tim' },
    autonomy: () => autonomy,
    tokenMatches: (candidate) => token.matches(candidate),
    voice: { say: (say) => { said.push(say); return true }, unsay: (id, reason) => { unsaid.push({ id, reason }); return true } },
    present: () => opts.present !== false,
    started: new StartedHarnesses(join(dir, 'started.json')),
    talk: async (text) => ({ ok: true, sent: text }),
    now: Date.now,
    newId: () => `id${++seq}`,
  }
  const control = new PairControl(deps)
  const call = (verb: string, args: Result = {}, withToken = true): Promise<Result> =>
    control.local({ verb, ...args, ...(withToken ? { token: secret } : {}) })
  return { control, call, owner, fleet, requests, said, unsaid, deps, setAutonomy: (a: Autonomy) => { autonomy = a } }
}

describe('each tool maps to the right call', () => {
  it('lists the BRAIN.md table, and nothing that deletes, restarts, forks or bypasses', () => {
    expect(CONTROL_TOOLS.map((t) => t.name)).toEqual(['list_machines', 'list_harnesses', 'read_harness', 'brief', 'answer_question',
      'send_prompt', 'stop_turn', 'start_harness', 'pause_harness', 'resume_harness', 'say'])
    expect(CONTROL_TOOLS.map((t) => t.name).join(' ')).not.toMatch(/delete|restart|fork|bypass/i)
    const start = CONTROL_TOOLS.find((t) => t.name === 'start_harness')!
    expect(Object.keys((start.input as { properties: object }).properties)).not.toContain('bypassPermission')
  })

  it('reads: this machine from its owner, another over sealed pair_list / pair_read', async () => {
    const w = world()
    expect(await w.call('list_machines', {}, false)).toMatchObject({ ok: true, machines: expect.arrayContaining([expect.objectContaining({ machineId: 'machine-b' })]) })
    const all = await w.call('list_harnesses', {}, false)
    expect(all.machines).toEqual([
      { machineId: 'machine-a', machine: 'desk', harnesses: [expect.objectContaining({ agentId: 'api' })] },
      { machineId: 'machine-b', machine: 'laptop', harnesses: [expect.objectContaining({ agentId: 'web', status: 'waiting' })] },
      { machineId: 'machine-c', machine: 'mini', error: 'MACHINE_UNREACHABLE' },
    ])
    await w.call('read_harness', { agentId: 'api' }, false)
    expect(w.owner.read).toHaveBeenCalledWith('api')
    await w.call('read_harness', { agentId: 'web', machineId: 'machine-b' }, false)
    expect(w.requests.at(-1)).toMatchObject({ machineId: 'machine-b', type: 'pair_read', payload: { agentId: 'web' } })
    const brief = await w.call('brief', { sinceMinutes: 30 }, false)
    expect(brief).toMatchObject({ ok: true, sinceMinutes: 30, acted: [expect.objectContaining({ by: 'rule', action: 'answer' })] })
    expect(w.fleet.journals).toHaveBeenCalledWith(1_000_000 - 30 * 60_000, 3_000)
  })

  it('writes on this machine go to its owner as `pair`; on another as the matching sealed request', async () => {
    const w = world({ autonomy: 'act-on-key' })
    // Started by the pair, so it may drive them without a key.
    w.deps.started.add('machine-a', 'api')
    w.deps.started.add('machine-b', 'web')
    const local: Array<[string, Result, string, unknown[]]> = [
      ['answer_question', { agentId: 'api', requestId: 'q1', choice: 'Yes' }, 'answer', [{ agentId: 'api', requestId: 'q1', choice: 'Yes' }, 'pair']],
      ['send_prompt', { agentId: 'api', text: 'run it' }, 'send', [{ agentId: 'api', text: 'run it' }, 'pair']],
      ['stop_turn', { agentId: 'api' }, 'stop', [{ agentId: 'api' }, 'pair']],
      ['pause_harness', { agentId: 'api' }, 'pause', [{ agentId: 'api' }, 'pair']],
      ['resume_harness', { agentId: 'api' }, 'resume', [{ agentId: 'api' }, 'pair']],
    ]
    for (const [verb, args, method, expected] of local) {
      expect(await w.call(verb, args)).toMatchObject({ ok: true, machineId: 'machine-a' })
      expect(w.owner[method as 'answer']).toHaveBeenLastCalledWith(...expected)
    }
    const remote: Array<[string, Result, string, Result]> = [
      ['answer_question', { agentId: 'web', requestId: 'q9', choice: 'No' }, 'pair_answer', { agentId: 'web', expectRequestId: 'q9', choice: 'No', by: 'pair' }],
      ['send_prompt', { agentId: 'web', text: 'go' }, 'pair_send', { agentId: 'web', text: 'go', by: 'pair' }],
      ['stop_turn', { agentId: 'web' }, 'pair_stop', { agentId: 'web', by: 'pair' }],
      ['pause_harness', { agentId: 'web' }, 'pair_pause', { agentId: 'web', by: 'pair' }],
      ['resume_harness', { agentId: 'web' }, 'pair_resume', { agentId: 'web', by: 'pair' }],
    ]
    for (const [verb, args, type, payload] of remote) {
      expect(await w.call(verb, { ...args, machineId: 'machine-b' })).toMatchObject({ ok: true, machineId: 'machine-b' })
      expect(w.requests.at(-1)).toEqual({ machineId: 'machine-b', type, payload })
    }
  })
})

describe('the token', () => {
  it('refuses every write without the pair harness\'s token, or with an old one', async () => {
    const w = world({ autonomy: 'act-on-key' })
    w.deps.started.add('machine-a', 'api')
    for (const tool of CONTROL_TOOLS.filter((t) => t.kind === 'write')) {
      expect(await w.call(tool.name, { agentId: 'api', requestId: 'q', choice: 'Yes', text: 'x', engine: 'codex', cwd: '/w' }, false))
        .toMatchObject({ ok: false, error: 'TOKEN_REQUIRED' })
    }
    const old = new PairToken(join(dir, 'token')).rotate()   // a new launch: the token the old one held is dead
    expect(await w.control.local({ verb: 'stop_turn', agentId: 'api', token: 'f'.repeat(64) })).toMatchObject({ error: 'TOKEN_REQUIRED' })
    expect(old).toMatch(/^[a-f0-9]{64}$/)
    expect(w.owner.stop).not.toHaveBeenCalled()
    // Reads never need it.
    expect(await w.call('list_harnesses', {}, false)).toMatchObject({ ok: true })
  })

  it('is kept 0600 and read back by a daemon that restarts', () => {
    const token = new PairToken(join(dir, 'pair', 'token'))
    expect(token.launched).toBe(false)
    expect(token.matches('')).toBe(false)
    const value = token.rotate()
    expect(statSync(join(dir, 'pair', 'token')).mode & 0o777).toBe(0o600)
    expect(readFileSync(join(dir, 'pair', 'token'), 'utf8').trim()).toBe(value)
    expect(new PairToken(join(dir, 'pair', 'token')).matches(value)).toBe(true)
  })
})

describe('the autonomy matrix', () => {
  const write = { agentId: 'api', text: 'run the tests' }

  it('watch: reads and say only; every write refused', async () => {
    const w = world({ autonomy: 'watch' })
    w.deps.started.add('machine-a', 'api')
    expect(await w.call('send_prompt', write)).toMatchObject({ ok: false, error: 'AUTONOMY_WATCH' })
    expect(await w.call('list_harnesses')).toMatchObject({ ok: true })
    expect(await w.call('say', { line: 'api is done.' })).toEqual({ ok: true })
    expect(w.owner.send).not.toHaveBeenCalled()
    expect(w.said.map((s) => s.mood)).toEqual(['say'])
  })

  it('suggest: every write waits for the person\'s key, even on a harness it started', async () => {
    const w = world({ autonomy: 'suggest' })
    w.deps.started.add('machine-a', 'api')
    const proposed = await w.call('send_prompt', write)
    expect(proposed).toMatchObject({ ok: true, proposed: true })
    expect(w.owner.send).not.toHaveBeenCalled()
    expect(w.said).toEqual([expect.objectContaining({ id: proposed.id, mood: 'ask', line: 'tell api: "run the tests"? [y/n]',
      actions: [{ key: 'y', label: 'do it', choice: 'y' }, { key: 'n', label: 'skip', choice: 'n' }] })])
    expect(w.control.owns(String(proposed.id))).toBe(true)
    expect(await w.control.act(String(proposed.id), 'y')).toMatchObject({ ok: true, results: [expect.objectContaining({ ok: true, verb: 'send_prompt' })] })
    // Run as the person's key, not as the pair.
    expect(w.owner.send).toHaveBeenCalledWith({ agentId: 'api', text: 'run the tests' }, 'key')
    expect(w.unsaid).toEqual([{ id: proposed.id, reason: 'answered' }])
    expect(await w.control.act(String(proposed.id), 'y')).toMatchObject({ ok: false, error: 'GONE' })
  })

  it('suggest: `n` drops it, and a proposal nobody answered expires', async () => {
    const w = world({ autonomy: 'suggest' })
    const first = await w.call('stop_turn', { agentId: 'api' })
    expect(await w.control.act(String(first.id), 'n')).toEqual({ ok: true, declined: 1 })
    const second = await w.call('stop_turn', { agentId: 'api' })
    vi.advanceTimersByTime(PROPOSAL_TTL_MS)
    expect(await w.control.act(String(second.id), 'y')).toMatchObject({ ok: false, error: 'GONE' })
    expect(w.owner.stop).not.toHaveBeenCalled()
  })

  it('act-on-key: drives a harness it started; the rest wait in one batch that one key approves', async () => {
    const w = world({ autonomy: 'act-on-key' })
    // Starting is never "its own": it waits for the key, then the new harness is its own to drive.
    const start = await w.call('start_harness', { engine: 'codex', cwd: '/w/api', prompt: 'add a test' })
    expect(start).toMatchObject({ proposed: true, batch: 1 })
    const batchLine = w.said.at(-1)!
    expect(await w.control.act(batchLine.id, 'y')).toMatchObject({ ok: true })
    expect(w.owner.start).toHaveBeenCalledWith({ engine: 'codex', cwd: '/w/api', prompt: 'add a test', name: null }, 'key')
    expect(await w.call('send_prompt', { agentId: 'new-1', text: 'now the docs' })).toMatchObject({ ok: true, deliveryId: 'd1' })
    expect(w.owner.send).toHaveBeenLastCalledWith({ agentId: 'new-1', text: 'now the docs' }, 'pair')

    const one = await w.call('stop_turn', { agentId: 'api' })
    const two = await w.call('pause_harness', { agentId: 'web', machineId: 'machine-b' })
    expect([one.batch, two.batch]).toEqual([1, 2])
    const line = w.said.at(-1)!
    expect(line.line).toBe("2 things to do: stop api's turn; pause web@machine-b. [y/n]")
    expect(w.unsaid.at(-1)).toMatchObject({ reason: 'replaced' })
    expect(await w.control.act(line.id, 'y')).toMatchObject({ ok: true, results: [expect.objectContaining({ verb: 'stop_turn' }), expect.objectContaining({ verb: 'pause_harness' })] })
    expect(w.owner.stop).toHaveBeenCalledWith({ agentId: 'api' }, 'key')
    expect(w.requests.at(-1)).toEqual({ machineId: 'machine-b', type: 'pair_pause', payload: { agentId: 'web', by: 'key' } })
  })

  it('act-within-rules: tools behave as act-on-key (rules are the owning machine\'s, pair/rules.ts)', async () => {
    const w = world({ autonomy: 'act-within-rules' })
    w.deps.started.add('machine-a', 'api')
    expect(await w.call('stop_turn', { agentId: 'api' })).toMatchObject({ ok: true })
    expect(await w.call('stop_turn', { agentId: 'other' })).toMatchObject({ proposed: true })
  })

  it('a proposal needs someone here to approve it; say needs someone to hear it, and is rate-limited', async () => {
    const away = world({ autonomy: 'suggest', present: false })
    expect(await away.call('send_prompt', write)).toMatchObject({ error: 'NOBODY_HERE' })
    expect(await away.call('say', { line: 'hi' })).toMatchObject({ error: 'NOBODY_HERE' })
    const w = world()
    expect(await w.call('say', { line: 'api finished.' })).toEqual({ ok: true })
    expect(await w.call('say', { line: 'and again' })).toMatchObject({ error: 'RATE_LIMITED' })
    vi.advanceTimersByTime(5_000)
    expect(await w.call('say', { line: 'and again' })).toEqual({ ok: true })
  })

  it('refuses anything while pairing is off, and an unknown verb', async () => {
    const w = world()
    w.deps.pairing.enabled = () => false
    expect(await w.call('list_harnesses')).toMatchObject({ error: 'PAIR_OFF' })
    expect(await w.control.local({ verb: 'delete_harness', agentId: 'api' })).toMatchObject({ error: 'UNKNOWN_VERB' })
    expect(await w.control.local({ verb: 'talk', text: 'hi tim' })).toEqual({ ok: true, sent: 'hi tim' })
  })
})
