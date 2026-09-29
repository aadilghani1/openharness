import { describe, it, expect } from 'vitest'
import { newPairCode, pairLink, fingerprintParam, runQrLink, PAIR_CODE_ALPHABET, PAIR_CODE_LENGTH, type QrLinkDeps, type QrLinkEvent } from './qrLink.js'

/** A fake daemon: answers /api/pair from a script, and /api/group from a timeline. */
function harness(pairAnswers: Array<{ status: number; body: Record<string, unknown> }>, groupAt: (t: number) => Array<{ kind: string; machineId?: string; label: string }> = () => []) {
  let t = 0
  const shown: string[] = []
  const events: QrLinkEvent[] = []
  const codesSent: string[] = []
  let n = 0
  const deps: QrLinkDeps = {
    pair: async (code) => { codesSent.push(code); t += 100; return pairAnswers.shift() ?? { status: 409, body: { error: 'NO_INTENT' } } },
    group: async () => ({ members: groupAt(t) }),
    show: (code) => { shown.push(code) },
    note: (e) => events.push(e),
    sleep: async (ms) => { t += ms },
    now: () => t,
    mintCode: () => `CODE${n++}`,
  }
  return { deps, shown, events, codesSent, clock: () => t }
}

describe('pair code and link', () => {
  it('draws 16 symbols from the shared alphabet', () => {
    const code = newPairCode()
    expect(code).toHaveLength(PAIR_CODE_LENGTH)
    for (const ch of code) expect(PAIR_CODE_ALPHABET).toContain(ch)
  })

  it('puts everything after the # and keeps the fingerprint ASCII', () => {
    const url = pairLink({ machineId: 'a'.repeat(32), code: 'ABCDEFGHJKMNPQRS', fingerprint: '5F80·61C4·6142·ADCF', hostname: 'box 1', email: 'dee@x.ai' })
    const u = new URL(url)
    expect(`${u.origin}${u.pathname}`).toBe('https://harness.autonomous.ai/pair')
    expect(u.search).toBe('')
    const q = new URLSearchParams(u.hash.slice(1))
    expect(Object.fromEntries(q)).toEqual({ m: 'a'.repeat(32), c: 'ABCDEFGHJKMNPQRS', f: '5F8061C46142ADCF', n: 'box 1', e: 'dee@x.ai' })
    expect(fingerprintParam('5f80·61c4')).toBe('5F8061C4')
  })
})

describe('runQrLink', () => {
  it('re-polls while no phone is waiting, then reports the pairing and the machines the group brings', async () => {
    const machines = [{ kind: 'machine', machineId: 'a'.repeat(32), label: 'mac' }, { kind: 'viewer', label: 'phone' }, { kind: 'machine', machineId: 'b'.repeat(32), label: 'box' }]
    const h = harness(
      [{ status: 409, body: { error: 'NO_INTENT' } }, { status: 409, body: { error: 'BUSY' } }, { status: 200, body: { label: "Dee's iPhone", fingerprint: 'x' } }],
      (t) => (t > 5_000 ? machines : machines.slice(0, 1)),
    )
    const result = await runQrLink(h.deps)
    expect(result).toEqual({ ok: true, label: "Dee's iPhone", machines: [{ machineId: 'a'.repeat(32), label: 'mac' }, { machineId: 'b'.repeat(32), label: 'box' }] })
    expect(h.codesSent).toEqual(['CODE0', 'CODE0', 'CODE0'])
    expect(h.events.map((e) => e.type)).toEqual(['waiting', 'linked', 'syncing'])
  })

  it('a wrong code spends it: a new code and a redrawn QR', async () => {
    const h = harness([{ status: 403, body: { error: 'CODE_MISMATCH' } }, { status: 200, body: { label: 'p' } }])
    const result = await runQrLink(h.deps)
    expect(result.ok).toBe(true)
    expect(h.shown).toEqual(['CODE0', 'CODE1'])
    expect(h.codesSent).toEqual(['CODE0', 'CODE1'])
    expect(h.events.map((e) => e.type)).toContain('mismatch')
  })

  it('rotates the code every few minutes so a photographed QR goes stale', async () => {
    const answers: Array<{ status: number; body: Record<string, unknown> }> = Array.from({ length: 200 }, () => ({ status: 409, body: { error: 'NO_INTENT' } }))
    answers.push({ status: 200, body: { label: 'p' } })
    const h = harness(answers)
    await runQrLink(h.deps)
    expect(h.shown.length).toBeGreaterThan(1)
    expect(h.events.map((e) => e.type)).toContain('rotated')
  })

  it('waits out a rate limit, and stops on an error it cannot recover from', async () => {
    const limited = harness([{ status: 429, body: { error: 'RATE_LIMITED' } }, { status: 200, body: { label: 'p' } }])
    expect((await runQrLink(limited.deps)).ok).toBe(true)
    expect(limited.events.find((e) => e.type === 'rate_limited')).toBeTruthy()

    const unavailable = harness([{ status: 503, body: { error: 'PAIRING_UNAVAILABLE' } }])
    expect(await runQrLink(unavailable.deps)).toEqual({ ok: false, error: 'PAIRING_UNAVAILABLE' })

    const down = harness([])
    down.deps.pair = async () => { throw new Error('ECONNREFUSED') }
    expect(await runQrLink(down.deps)).toEqual({ ok: false, error: 'DAEMON_UNREACHABLE' })
  })

  it('a first link into an empty group does not wait the full sync window', async () => {
    const h = harness([{ status: 200, body: { label: 'p' } }])
    const result = await runQrLink(h.deps)
    expect(result).toEqual({ ok: true, label: 'p', machines: [] })
    expect(h.clock()).toBeLessThan(25_000)
  })
})
