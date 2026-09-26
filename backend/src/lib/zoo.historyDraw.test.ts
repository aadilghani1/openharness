import { describe, expect, it, vi } from 'vitest'

// The shipped roster names history daemons no drop holds yet (moth, teapot, zombie). This file gives
// one date a daemon that IS released, to pin what a history egg does once a drop brings its daemon.
vi.mock('./daemonRoster.g.js', async (original) => {
  const { DAEMON_ROSTER } = await original<typeof import('./daemonRoster.g.js')>()
  return { DAEMON_ROSTER: { ...DAEMON_ROSTER, rules: { ...DAEMON_ROSTER.rules, historyDates: { ...DAEMON_ROSTER.rules.historyDates, '09-26': 'grue' } } } }
})
const { applyZooOps, emptyZoo, historyDaemon } = await import('./zoo.js')

const egg = { id: 'h', kind: 'history', grantedAt: '2026-09-26T12:00:00.000Z', date: '2026-09-26' }
const now = new Date('2026-09-26T12:00:00.000Z')

describe('a history egg whose daemon a drop holds', () => {
  it('gives that daemon, rolling only for shiny', () => {
    const calls: number[] = []
    const rng = (n: number) => { calls.push(n); return 1 }
    const r = applyZooOps({ ...emptyZoo(), eggs: [egg] }, [{ op: 'zoo.hatch', eggId: 'h' }], rng, now)
    expect(r.hatched).toEqual([{ eggId: 'h', daemonId: 'grue', shiny: false }])
    expect(calls).toEqual([256])
    expect(r.zoo.pity).toBe(0)                                             // it is a secret: pity resets
    expect(r.zoo.daemons[0]).toMatchObject({ id: 'grue', egg: 'history' })
  })

  it('draws from the usual pool once you own it', () => {
    const owned = { ...emptyZoo(), daemons: [{ id: 'grue', hatchedAt: now.toISOString(), egg: 'night', shiny: false, bond: 0, xp: 0, version: '0.1' }], eggs: [egg] }
    expect(historyDaemon(owned, egg.date)).toBeNull()
    const r = applyZooOps(owned, [{ op: 'zoo.hatch', eggId: 'h' }], (n) => n - 1, now)
    expect(r.hatched[0].daemonId).not.toBe('grue')
  })

  it('earns the egg on that date like any history date', () => {
    const r = applyZooOps(emptyZoo(), [{ op: 'zoo.turn', batchId: 'b1', n: 1, day: '2026-09-26', hour: 10, machineId: 'm1' }], (n) => n - 1, now)
    expect(r.zoo.eggs).toEqual([expect.objectContaining({ kind: 'history', date: '2026-09-26' })])
  })
})
