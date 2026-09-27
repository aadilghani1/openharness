import { describe, expect, it, vi } from 'vitest'

// Drop 1 (unix) is released and drop 2 (tty) is announced, out 2026-10-11. This file also adds a third drop
// that is announced but not yet out, with one common daemon, to pin what a draw does on either side of a
// release date (daemons/README.md, "The draw").
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

const regularsOf = (drop: string) => DAEMON_ROSTER.daemons.filter((d) => d.drop === drop && d.rarity !== 'secret').map((d) => d.id)
const REGULARS = regularsOf('unix')
const TTY = regularsOf('tty')
const daemon = (id: string) => ({ id, hatchedAt: '2026-09-01T00:00:00.000Z', egg: 'first', shiny: false, bond: 0, xp: 0, version: '0.1' })
const eggOf = (kind: string) => ({ id: 'e', kind, grantedAt: '2026-10-01T00:00:00.000Z' })
const eligible = (zoo: ReturnType<typeof emptyZoo>, at: string, kind = 'turn') =>
  drawWeights(zoo, kind, new Date(at)).filter((w) => w.weight > 0).map((w) => w.id)
/** A small seeded generator, so a run is reproducible. */
function seeded(seed: number) {
  let a = seed >>> 0
  return (n: number) => {
    a = (a + 0x6d2b79f5) >>> 0
    let t = Math.imul(a ^ (a >>> 15), a | 1)
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
    return Math.floor((((t ^ (t >>> 14)) >>> 0) / 4294967296) * n)
  }
}

describe('drops: announced, then released', () => {
  it('ships drop 1 released and drop 2 (tty) announced, each 14 days before its release', async () => {
    const { DAEMON_ROSTER: shipped } = await vi.importActual<typeof import('./daemonRoster.g.js')>('./daemonRoster.g.js')
    expect(shipped.drops).toEqual([
      { id: 'unix', announce: '2026-09-12', release: '2026-09-26' },
      { id: 'tty', announce: '2026-09-27', release: '2026-10-11' },
    ])
    expect(dropReleased(shipped.drops[0], new Date('2026-09-26T00:00:00.000Z'))).toBe(true)
    expect(dropReleased(shipped.drops[0], new Date('2026-09-25T23:59:59.999Z'))).toBe(false)
    expect(dropReleased(shipped.drops[1], new Date('2026-10-10T23:59:59.999Z'))).toBe(false)
    expect(dropReleased(shipped.drops[1], new Date('2026-10-11T00:00:00.000Z'))).toBe(true)
    // Nine regulars and a secret, like drop 1.
    expect(TTY).toEqual(['xeyes', 'oneko', 'cowsay', 'fortune', 'rogue', 'sl', 'doctor', 'hack', 'tty'])
    expect(shipped.daemons.filter((d) => d.drop === 'tty' && d.rarity === 'secret').map((d) => d.id)).toEqual(['lp0'])
  })

  it('never draws drop 2 before 2026-10-11, and adds its regulars to the set that day', () => {
    expect(releasedDaemons(new Date('2026-10-10T23:59:59.999Z')).map((d) => d.drop)).not.toContain('tty')
    expect(eligible(emptyZoo(), '2026-10-10T23:59:59.999Z')).toEqual(REGULARS)
    expect(eligible(emptyZoo(), '2026-10-11T00:00:00.000Z')).toEqual([...REGULARS, ...TTY])
    // A hatch the day before gives drop 1, whatever the dice say.
    for (let seed = 1; seed <= 200; seed++) {
      const r = applyZooOps({ ...emptyZoo(), eggs: [eggOf('marathon')] }, [{ op: 'zoo.hatch', eggId: 'e' }], seeded(seed), new Date('2026-10-10T23:00:00.000Z'))
      expect(REGULARS).toContain(r.hatched[0].daemonId)
    }
    // Owning all of drop 1 before the release gives a duplicate; from the release, only drop 2 is new.
    const allOfDrop1 = { ...emptyZoo(), daemons: REGULARS.map(daemon), eggs: [eggOf('turn')] }
    expect(eligible(allOfDrop1, '2026-10-10T12:00:00.000Z')).toEqual(REGULARS)
    expect(eligible(allOfDrop1, '2026-10-11T12:00:00.000Z')).toEqual(TTY)
  })

  it('keeps lp0 a secret: only from an egg that can hold one, only once released, and the pity finds it', () => {
    expect(eligible(emptyZoo(), '2026-10-12T12:00:00.000Z')).not.toContain('lp0')
    expect(eligible(emptyZoo(), '2026-10-12T12:00:00.000Z', 'night')).toEqual(expect.arrayContaining(['grue', 'lp0']))
    expect(eligible(emptyZoo(), '2026-10-10T12:00:00.000Z', 'night')).not.toContain('lp0')
    // At a pity of 7 with the grue owned, the next night egg is lp0 once it is out, and cannot be before.
    const grueOwned = { ...emptyZoo(), daemons: [daemon('grue')], pity: 7, eggs: [eggOf('night')] }
    expect(eligible(grueOwned, '2026-10-11T12:00:00.000Z', 'night')).toEqual(['lp0'])
    const after = applyZooOps(grueOwned, [{ op: 'zoo.hatch', eggId: 'e' }], seeded(3), new Date('2026-10-11T12:00:00.000Z'))
    expect(after.hatched[0].daemonId).toBe('lp0')
    const before = applyZooOps(grueOwned, [{ op: 'zoo.hatch', eggId: 'e' }], seeded(3), new Date('2026-10-10T12:00:00.000Z'))
    expect(REGULARS).toContain(before.hatched[0].daemonId)
  })

  it('never seeds a daemon of a drop that is not out yet', () => {
    const seed = { daemons: [daemon('tim'), daemon('xeyes'), daemon('lp0')], eggs: [], pair: 'xeyes' }
    const early = applyZooOps(emptyZoo(), [{ op: 'zoo.seed', zoo: seed }], seeded(1), new Date('2026-10-10T12:00:00.000Z'))
    expect(early.zoo.daemons.map((d) => d.id)).toEqual(['tim'])
    expect(early.zoo.pair).toBe('tim')
    const late = applyZooOps(emptyZoo(), [{ op: 'zoo.seed', zoo: seed }], seeded(1), new Date('2026-10-11T12:00:00.000Z'))
    expect(late.zoo.daemons.map((d) => d.id)).toEqual(['tim', 'xeyes'])        // never a secret
    expect(late.zoo.pair).toBe('xeyes')
  })

  it('never draws a daemon of a drop that is only announced', () => {
    const plan9 = { id: 'plan9', announce: '2026-10-01', release: '2026-10-15' }
    expect(DAEMON_ROSTER.drops).toContainEqual(plan9)
    expect(dropReleased(plan9, new Date('2026-10-14T23:59:59.000Z'))).toBe(false)
    expect(releasedDaemons(new Date('2026-10-10T12:00:00.000Z')).map((d) => d.id)).not.toContain('rio')
    expect(eligible(emptyZoo(), '2026-10-14T12:00:00.000Z')).toEqual([...REGULARS, ...TTY])
    expect(eligible(emptyZoo(), '2026-10-15T00:00:00.000Z')).toEqual([...REGULARS, ...TTY, 'rio'])
  })

  it('counts a released drop\'s regulars toward the set the moment it is out', () => {
    const allReleased = { ...emptyZoo(), daemons: [...REGULARS, ...TTY].map(daemon), eggs: [eggOf('turn')] }
    // Before the release every released regular is owned, so a draw gives a duplicate...
    expect(eligible(allReleased, '2026-10-14T12:00:00.000Z')).toEqual([...REGULARS, ...TTY])
    const before = applyZooOps(allReleased, [{ op: 'zoo.hatch', eggId: 'e' }], (n) => n - 1, new Date('2026-10-14T12:00:00.000Z'))
    expect(before.hatched[0]).toMatchObject({ duplicate: true })
    // ...and on release day the new regular is the only one eligible.
    expect(eligible(allReleased, '2026-10-15T12:00:00.000Z')).toEqual(['rio'])
    const after = applyZooOps(allReleased, [{ op: 'zoo.hatch', eggId: 'e' }], (n) => n - 1, new Date('2026-10-15T12:00:00.000Z'))
    expect(after.hatched).toEqual([{ eggId: 'e', daemonId: 'rio', shiny: false }])
  })
})
