import { describe, expect, it, vi } from 'vitest'

// Drop 1 is released. This file adds a second drop that is announced but not yet out, with one common
// daemon, to pin what a draw does on either side of a release date (daemons/README.md, "The draw").
vi.mock('./daemonRoster.g.js', async (original) => {
  const { DAEMON_ROSTER } = await original<typeof import('./daemonRoster.g.js')>()
  return {
    DAEMON_ROSTER: {
      ...DAEMON_ROSTER,
      drops: [...DAEMON_ROSTER.drops, { id: 'plan9', announce: '2026-10-01', release: '2026-10-15' }],
      daemons: [...DAEMON_ROSTER.daemons, { id: 'rio', n: 1, drop: 'plan9', rarity: 'common' }],
    },
  }
})
const { DAEMON_ROSTER } = await import('./daemonRoster.g.js')
const { applyZooOps, drawWeights, dropReleased, emptyZoo, releasedDaemons } = await import('./zoo.js')

const REGULARS = DAEMON_ROSTER.daemons.filter((d) => d.drop === 'unix' && d.rarity !== 'secret').map((d) => d.id)
const daemon = (id: string) => ({ id, hatchedAt: '2026-09-01T00:00:00.000Z', egg: 'first', shiny: false, bond: 0, xp: 0, version: '0.1' })
const eligible = (zoo: ReturnType<typeof emptyZoo>, at: string) =>
  drawWeights(zoo, 'turn', new Date(at)).filter((w) => w.weight > 0).map((w) => w.id)

describe('drops: announced, then released', () => {
  it('ships drop 1 released, with its announcement 14 days before', async () => {
    const { DAEMON_ROSTER: shipped } = await vi.importActual<typeof import('./daemonRoster.g.js')>('./daemonRoster.g.js')
    expect(shipped.drops).toEqual([{ id: 'unix', announce: '2026-09-12', release: '2026-09-26' }])
    expect(dropReleased(shipped.drops[0], new Date('2026-09-26T00:00:00.000Z'))).toBe(true)
    expect(dropReleased(shipped.drops[0], new Date('2026-09-25T23:59:59.999Z'))).toBe(false)
  })

  it('never draws a daemon of a drop that is only announced', () => {
    const plan9 = { id: 'plan9', announce: '2026-10-01', release: '2026-10-15' }
    expect(DAEMON_ROSTER.drops).toContainEqual(plan9)
    expect(dropReleased(plan9, new Date('2026-10-14T23:59:59.000Z'))).toBe(false)
    expect(releasedDaemons(new Date('2026-10-10T12:00:00.000Z')).map((d) => d.id)).not.toContain('rio')
    expect(eligible(emptyZoo(), '2026-10-10T12:00:00.000Z')).toEqual(REGULARS)
    expect(eligible(emptyZoo(), '2026-10-15T00:00:00.000Z')).toEqual([...REGULARS, 'rio'])
  })

  it('counts a released drop\'s regulars toward the set the moment it is out', () => {
    const allOfDrop1 = { ...emptyZoo(), daemons: REGULARS.map(daemon), eggs: [{ id: 'e', kind: 'turn', grantedAt: '2026-10-01T00:00:00.000Z' }] }
    // Before the release every regular is owned, so a draw gives a duplicate...
    expect(eligible(allOfDrop1, '2026-10-14T12:00:00.000Z')).toEqual(REGULARS)
    const before = applyZooOps(allOfDrop1, [{ op: 'zoo.hatch', eggId: 'e' }], (n) => n - 1, new Date('2026-10-14T12:00:00.000Z'))
    expect(before.hatched[0]).toMatchObject({ duplicate: true })
    // ...and on release day the new regular is the only one eligible.
    expect(eligible(allOfDrop1, '2026-10-15T12:00:00.000Z')).toEqual(['rio'])
    const after = applyZooOps(allOfDrop1, [{ op: 'zoo.hatch', eggId: 'e' }], (n) => n - 1, new Date('2026-10-15T12:00:00.000Z'))
    expect(after.hatched).toEqual([{ eggId: 'e', daemonId: 'rio', shiny: false }])
  })
})
