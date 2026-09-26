import { describe, expect, it } from 'vitest'
import {
  applyZooOps, drawWeights, emptyZoo, parseZoo, zooOpSchema, zooOpsBodySchema,
  ZOO_MAX_DAEMONS, ZOO_MAX_EGGS, type Rng, type Zoo, type ZooDaemon, type ZooOp,
} from './zoo.js'
import { DAEMON_ROSTER } from './daemonRoster.g.js'

const NOW = new Date('2026-09-26T12:00:00.000Z')
const UNIT = 1_000_000
const ALL = DAEMON_ROSTER.daemons.map((d) => d.id)
const HABITS = [...DAEMON_ROSTER.rules.firstEgg.habits]

/** A small seeded generator: realistic ids, reproducible runs. */
function seeded(seed = 1): Rng {
  let a = seed >>> 0
  return (n) => {
    a = (a + 0x6d2b79f5) >>> 0
    let t = a
    t = Math.imul(t ^ (t >>> 15), t | 1)
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
    return Math.floor((((t ^ (t >>> 14)) >>> 0) / 4294967296) * n)
  }
}
/** Answers `values` in order, then falls back to a seeded generator. */
function scripted(values: number[], rest: Rng = seeded(7)): Rng & { calls: number[] } {
  const queue = [...values]
  const calls: number[] = []
  const rng = ((n: number) => { calls.push(n); return queue.length ? queue.shift()! : rest(n) }) as Rng & { calls: number[] }
  rng.calls = calls
  return rng
}
/** The random index that lands a draw from `kind` on `id`. */
function indexOf(zoo: Zoo, kind: string, id: string): number {
  let at = 0
  for (const w of drawWeights(zoo, kind)) {
    if (w.id === id) { expect(w.weight).toBeGreaterThan(0); return at }
    at += w.weight
  }
  throw new Error(`${id} cannot come out of ${kind}`)
}
const daemon = (id: string, extra: Partial<ZooDaemon> = {}): ZooDaemon =>
  ({ id, hatchedAt: '2026-09-01T00:00:00.000Z', egg: 'first', shiny: false, bond: 0, version: '0.1', ...extra })
const zooOf = (patch: Partial<Zoo>): Zoo => ({ ...emptyZoo(), ...patch })
const egg = (id: string, kind = 'first') => ({ id, kind, grantedAt: '2026-09-02T00:00:00.000Z' })
const apply = (zoo: Zoo, ops: ZooOp[], rng: Rng = seeded()) => applyZooOps(zoo, ops, rng, NOW)
const weightOf = (zoo: Zoo, kind: string) => Object.fromEntries(drawWeights(zoo, kind).map((w) => [w.id, w.weight / UNIT]))

describe('first egg — habits', () => {
  it('grants exactly one first egg when the fifth habit is done, in any order', () => {
    let zoo = emptyZoo()
    for (const key of HABITS.slice(0, 4)) zoo = apply(zoo, [{ op: 'zoo.habit', key }]).zoo
    expect(zoo.eggs).toEqual([])
    expect(zoo.firstEgg).toBe(false)
    const fifth = apply(zoo, [{ op: 'zoo.habit', key: HABITS[4] }])
    expect(fifth.changed).toBe(true)
    expect(fifth.zoo.eggs).toEqual([{ id: expect.stringMatching(/^[a-z2-9]{10}$/), kind: 'first', grantedAt: NOW.toISOString() }])
    expect(fifth.zoo.firstEgg).toBe(true)
    zoo = fifth.zoo
    for (const key of HABITS.slice(5)) zoo = apply(zoo, [{ op: 'zoo.habit', key }]).zoo
    expect(zoo.habits).toEqual(HABITS)
    expect(zoo.eggs).toHaveLength(1)
    // Hatched and gone, every habit again: still no second first egg.
    const hatched = apply(zoo, [{ op: 'zoo.hatch', eggId: zoo.eggs[0].id }]).zoo
    const again = apply(hatched, HABITS.map((key) => ({ op: 'zoo.habit' as const, key })))
    expect(again.changed).toBe(false)
    expect(again.zoo.eggs).toEqual([])
  })

  it('drops a habit it does not know, without refusing the batch', () => {
    const op = { op: 'zoo.habit', key: 'teleport' }
    expect(zooOpSchema.safeParse(op).success).toBe(true)
    const r = apply(emptyZoo(), [op as ZooOp, { op: 'zoo.habit', key: 'turn' }])
    expect(r.zoo.habits).toEqual(['turn'])
    expect(apply(emptyZoo(), [op as ZooOp]).changed).toBe(false)
    expect(zooOpSchema.safeParse({ op: 'zoo.habit', key: 'not a key' }).success).toBe(false)
  })

  it('grants the first egg on the next habit when the nest was full', () => {
    const full = zooOf({ habits: HABITS.slice(0, 4), eggs: Array.from({ length: ZOO_MAX_EGGS }, (_, i) => egg(`e${i}`, 'turn')) })
    const blocked = apply(full, [{ op: 'zoo.habit', key: HABITS[4] }])
    expect(blocked.zoo.firstEgg).toBe(false)
    expect(blocked.zoo.eggs).toHaveLength(ZOO_MAX_EGGS)
    const roomy = apply(blocked.zoo, [{ op: 'zoo.hatch', eggId: 'e0' }]).zoo
    const granted = apply(roomy, [{ op: 'zoo.habit', key: HABITS[4] }])        // already counted: the grant still lands
    expect(granted.changed).toBe(true)
    expect(granted.zoo.firstEgg).toBe(true)
    expect(granted.zoo.eggs.filter((e) => e.kind === 'first')).toHaveLength(1)
  })
})

describe('hatching', () => {
  it('removes the egg, adds the daemon at 0.1 with no bond, and pairs the first one', () => {
    const zoo = zooOf({ eggs: [egg('a'), egg('b', 'turn')] })
    const rng = scripted([indexOf(zoo, 'first', 'vim'), 5])
    const r = apply(zoo, [{ op: 'zoo.hatch', eggId: 'a' }], rng)
    expect(r.hatched).toEqual([{ eggId: 'a', daemonId: 'vim', shiny: false }])
    expect(r.zoo.eggs.map((e) => e.id)).toEqual(['b'])
    expect(r.zoo.daemons).toEqual([{ id: 'vim', hatchedAt: NOW.toISOString(), egg: 'first', shiny: false, bond: 0, version: '0.1' }])
    expect(r.zoo.pair).toBe('vim')
    const second = apply(r.zoo, [{ op: 'zoo.hatch', eggId: 'b' }], scripted([indexOf(r.zoo, 'turn', 'tim'), 9]))
    expect(second.zoo.daemons.map((d) => d.id)).toEqual(['vim', 'tim'])
    expect(second.zoo.daemons[1].egg).toBe('turn')
    expect(second.zoo.pair).toBe('vim')                                         // a pair is never replaced by a hatch
  })

  it('drops a hatch of an egg that is not there', () => {
    const r = apply(zooOf({ eggs: [egg('a')] }), [{ op: 'zoo.hatch', eggId: 'gone' }])
    expect(r).toMatchObject({ changed: false, hatched: [] })
    expect(r.zoo.eggs).toHaveLength(1)
  })

  it('never draws a daemon you own until you own them all', () => {
    const allButGrue = zooOf({ daemons: ALL.filter((id) => id !== 'grue').map((id) => daemon(id)), eggs: [egg('a')] })
    expect(Object.entries(weightOf(allButGrue, 'first')).filter(([, w]) => w > 0).map(([id]) => id)).toEqual(['grue'])
    for (const roll of [0, 1, 17]) {
      const r = apply(allButGrue, [{ op: 'zoo.hatch', eggId: 'a' }], scripted([roll % (drawWeights(allButGrue, 'first').reduce((s, w) => s + w.weight, 0)), 1]))
      expect(r.hatched[0].daemonId).toBe('grue')
    }
    const two = zooOf({ daemons: ALL.filter((id) => id !== 'grue' && id !== 'tim').map((id) => daemon(id)), eggs: [egg('a')] })
    for (let seed = 1; seed <= 40; seed++) {
      expect(['tim', 'grue']).toContain(apply(two, [{ op: 'zoo.hatch', eggId: 'a' }], seeded(seed)).hatched[0].daemonId)
    }
  })

  it('allows duplicates again once every released daemon is owned', () => {
    const everyone = zooOf({ daemons: ALL.map((id) => daemon(id)), eggs: [egg('a'), egg('b')], pair: 'fzf' })
    const weights = weightOf(everyone, 'first')
    expect(Object.keys(weights)).toEqual(ALL)
    expect(weights).toMatchObject({ tim: 15, vim: 9, fzf: 6, grue: 1 })
    let r = apply(everyone, [{ op: 'zoo.hatch', eggId: 'a' }], scripted([indexOf(everyone, 'first', 'tim'), 1]))
    r = apply(r.zoo, [{ op: 'zoo.hatch', eggId: 'b' }], scripted([indexOf(r.zoo, 'first', 'tim'), 1]))
    expect(r.zoo.daemons.filter((d) => d.id === 'tim')).toHaveLength(3)
    expect(r.zoo.pair).toBe('fzf')
  })

  it('weighs a rarity by how many of it are left, and gives an empty rarity to nobody', () => {
    expect(weightOf(emptyZoo(), 'first')).toEqual({ tim: 15, fish: 15, ping: 15, bat: 15, vim: 9, zsh: 9, biff: 9, fzf: 6, tldr: 6, grue: 1 })
    expect(weightOf(zooOf({ daemons: [daemon('tim')] }), 'first')).toMatchObject({ fish: 20, ping: 20, bat: 20, vim: 9 })
    const noCommons = zooOf({ daemons: ['tim', 'fish', 'ping', 'bat'].map((id) => daemon(id)) })
    const w = weightOf(noCommons, 'first')
    expect(w).toEqual({ vim: 9, zsh: 9, biff: 9, fzf: 6, tldr: 6, grue: 1 })   // 40 in all: the commons' 60 went nowhere
  })

  it('grows pity on every miss, adds it to the secret, and resets it on a secret', () => {
    const zoo = zooOf({ eggs: [egg('a'), egg('b')], pity: 10 })
    expect(weightOf(zoo, 'first').grue).toBe(1 + 10 * DAEMON_ROSTER.rules.pityPerMiss)
    const miss = apply(zoo, [{ op: 'zoo.hatch', eggId: 'a' }], scripted([indexOf(zoo, 'first', 'tim'), 1]))
    expect(miss.zoo.pity).toBe(11)
    const hit = apply(miss.zoo, [{ op: 'zoo.hatch', eggId: 'b' }], scripted([indexOf(miss.zoo, 'first', 'grue'), 1]))
    expect(hit.hatched[0].daemonId).toBe('grue')
    expect(hit.zoo.pity).toBe(0)
  })

  it('boosts a night egg toward bat', () => {
    const w = weightOf(emptyZoo(), 'night')
    expect(w.bat).toBe((50 / 4) * 4)
    expect(w.tim).toBe(50 / 4)
    expect(w.grue).toBe(8)
    const zoo = zooOf({ eggs: [egg('n', 'night')] })
    const r = apply(zoo, [{ op: 'zoo.hatch', eggId: 'n' }], scripted([indexOf(zoo, 'night', 'bat') + Math.floor(w.bat * UNIT) - 1, 1]))
    expect(r.hatched[0].daemonId).toBe('bat')
  })

  it('makes a daemon shiny on a 1-in-shinyOneIn roll, independent of who hatched', () => {
    const zoo = zooOf({ eggs: [egg('a')] })
    const lucky = scripted([indexOf(zoo, 'first', 'tim'), 0])
    const r = apply(zoo, [{ op: 'zoo.hatch', eggId: 'a' }], lucky)
    expect(lucky.calls[1]).toBe(DAEMON_ROSTER.rules.shinyOneIn)
    expect(r.hatched[0]).toEqual({ eggId: 'a', daemonId: 'tim', shiny: true })
    expect(r.zoo.daemons[0].shiny).toBe(true)
    const plain = apply(zoo, [{ op: 'zoo.hatch', eggId: 'a' }], scripted([indexOf(zoo, 'first', 'tim'), DAEMON_ROSTER.rules.shinyOneIn - 1]))
    expect(plain.hatched[0].shiny).toBe(false)
  })

  it('draws an easter egg that has nothing new to give as a duplicate rather than as nobody', () => {
    const zoo = zooOf({ daemons: ['fzf', 'tldr', 'grue'].map((id) => daemon(id)), eggs: [egg('x', 'easter')] })
    const w = drawWeights(zoo, 'easter')
    expect(w.filter((x) => x.weight > 0).map((x) => x.id)).toEqual(['fzf', 'tldr', 'grue'])
    const r = apply(zoo, [{ op: 'zoo.hatch', eggId: 'x' }])
    expect(['fzf', 'tldr', 'grue']).toContain(r.hatched[0].daemonId)
  })

  it('leaves an egg of a kind the roster cannot draw where it is', () => {
    const zoo = zooOf({ eggs: [egg('q', 'comet'), egg('c', 'constructor')] })
    expect(drawWeights(zoo, 'constructor')).toEqual([])
    expect(apply(zoo, [{ op: 'zoo.hatch', eggId: 'q' }, { op: 'zoo.hatch', eggId: 'c' }]).changed).toBe(false)
  })

  it('stops hatching at 64 daemons', () => {
    const full = zooOf({ daemons: Array.from({ length: ZOO_MAX_DAEMONS }, () => daemon('tim')), eggs: [egg('a')] })
    expect(apply(full, [{ op: 'zoo.hatch', eggId: 'a' }]).changed).toBe(false)
  })

  it('uses crypto by default', () => {
    const r = applyZooOps(zooOf({ eggs: [egg('a')] }), [{ op: 'zoo.hatch', eggId: 'a' }])
    expect(ALL).toContain(r.hatched[0].daemonId)
  })
})

describe('pair, nickname, easter', () => {
  it('pairs only a daemon you own', () => {
    const zoo = zooOf({ daemons: [daemon('tim'), daemon('vim')], pair: 'tim' })
    expect(apply(zoo, [{ op: 'zoo.pair', id: 'vim' }]).zoo.pair).toBe('vim')
    expect(apply(zoo, [{ op: 'zoo.pair', id: 'tim' }]).changed).toBe(false)
    expect(apply(zoo, [{ op: 'zoo.pair', id: 'grue' }]).changed).toBe(false)
  })

  it('sets a 1-24 character printable nickname, clears it with null, and refuses anything else', () => {
    const zoo = zooOf({ daemons: [daemon('tim'), daemon('tim')] })
    const named = apply(zoo, [{ op: 'zoo.nickname', id: 'tim', nickname: 'timothy' }])
    expect(named.zoo.daemons.map((d) => d.nickname)).toEqual(['timothy', undefined])   // the first one hatched
    expect(apply(named.zoo, [{ op: 'zoo.nickname', id: 'tim', nickname: 'timothy' }]).changed).toBe(false)
    const cleared = apply(named.zoo, [{ op: 'zoo.nickname', id: 'tim', nickname: null }])
    expect(cleared.zoo.daemons[0]).not.toHaveProperty('nickname')
    expect(apply(cleared.zoo, [{ op: 'zoo.nickname', id: 'tim', nickname: null }]).changed).toBe(false)
    expect(apply(zoo, [{ op: 'zoo.nickname', id: 'vim', nickname: 'nope' }]).changed).toBe(false)
    const parse = (nickname: unknown) => zooOpSchema.safeParse({ op: 'zoo.nickname', id: 'tim', nickname })
    expect(parse('x'.repeat(24)).success).toBe(true)
    expect(parse('  tim  ').data).toMatchObject({ nickname: 'tim' })
    for (const bad of ['', '   ', 'x'.repeat(25), 'tïm', 'tab\there', 'emoji 🐱']) expect(parse(bad).success, bad).toBe(false)
  })

  it('grants one easter egg per word, once, and only for a word it knows', () => {
    const r = apply(emptyZoo(), [{ op: 'zoo.easter', word: 'xyzzy' }])
    expect(r.zoo.eggs).toEqual([expect.objectContaining({ kind: 'easter' })])
    expect(r.zoo.easter).toEqual(['xyzzy'])
    expect(apply(r.zoo, [{ op: 'zoo.easter', word: 'xyzzy' }]).changed).toBe(false)
    expect(apply(emptyZoo(), [{ op: 'zoo.easter', word: 'plugh' }]).changed).toBe(false)
    // A full nest leaves the word unspent.
    const full = zooOf({ eggs: Array.from({ length: ZOO_MAX_EGGS }, (_, i) => egg(`e${i}`)) })
    const blocked = apply(full, [{ op: 'zoo.easter', word: 'xyzzy' }])
    expect(blocked.changed).toBe(false)
    expect(blocked.zoo.easter).toEqual([])
  })
})

describe('seed — a guest zoo on first sign-in', () => {
  const guest = {
    daemons: [daemon('fish', { nickname: 'wanda', shiny: true }), daemon('nope'), { id: 'vim' }, daemon('bat', { egg: 'night' })],
    eggs: [egg('local-1'), egg('local-2', 'comet'), 'junk'],
    pair: 'nope',
    habits: ['turn', 'split', 'teleport'],
    firstEgg: true,
    pity: 2,
    easter: ['xyzzy', 'plugh'],
  }

  it('takes what the roster knows, renames the eggs, and pairs a daemon it kept', () => {
    const r = apply(emptyZoo(), [{ op: 'zoo.seed', zoo: guest }])
    expect(r.changed).toBe(true)
    expect(r.zoo.daemons.map((d) => d.id)).toEqual(['fish', 'bat'])
    expect(r.zoo.daemons[0]).toMatchObject({ nickname: 'wanda', shiny: true })
    expect(r.zoo.eggs).toEqual([{ id: expect.stringMatching(/^[a-z2-9]{10}$/), kind: 'first', grantedAt: '2026-09-02T00:00:00.000Z' }])
    expect(r.zoo).toMatchObject({ pair: 'fish', habits: ['turn', 'split'], firstEgg: true, pity: 2, easter: ['xyzzy'] })
  })

  it('applies only while the account zoo is empty', () => {
    const seeded1 = apply(emptyZoo(), [{ op: 'zoo.seed', zoo: guest }]).zoo
    expect(apply(seeded1, [{ op: 'zoo.seed', zoo: guest }]).changed).toBe(false)          // a second sign-in
    for (const account of [zooOf({ habits: ['turn'] }), zooOf({ eggs: [egg('a')] }), zooOf({ daemons: [daemon('tim')] })]) {
      const r = apply(account, [{ op: 'zoo.seed', zoo: guest }])
      expect(r.changed).toBe(false)
      expect(r.zoo).toEqual(account)
    }
    expect(apply(emptyZoo(), [{ op: 'zoo.seed', zoo: {} }]).changed).toBe(false)
  })

  it('never seeds past the limits', () => {
    const big = {
      daemons: Array.from({ length: ZOO_MAX_DAEMONS + 6 }, () => daemon('tim')),
      eggs: Array.from({ length: ZOO_MAX_EGGS + 6 }, (_, i) => egg(`g${i}`)),
    }
    const r = apply(emptyZoo(), [{ op: 'zoo.seed', zoo: big }])
    expect(r.zoo.daemons).toHaveLength(ZOO_MAX_DAEMONS)
    expect(r.zoo.eggs).toHaveLength(ZOO_MAX_EGGS)
    expect(new Set(r.zoo.eggs.map((e) => e.id)).size).toBe(ZOO_MAX_EGGS)
  })
})

describe('the document', () => {
  it('replays a whole batch as a no-op', () => {
    const start = zooOf({ daemons: [daemon('tim')], eggs: [egg('a')], habits: HABITS.slice(0, 3), pair: 'tim' })
    const ops: ZooOp[] = [
      { op: 'zoo.habit', key: HABITS[3] },
      { op: 'zoo.habit', key: HABITS[4] },
      { op: 'zoo.hatch', eggId: 'a' },
      { op: 'zoo.easter', word: 'xyzzy' },
      { op: 'zoo.nickname', id: 'tim', nickname: 'tim the enchanter' },
      { op: 'zoo.pair', id: 'tim' },
      { op: 'zoo.seed', zoo: { daemons: [daemon('grue')] } },
    ]
    const once = apply(start, ops)
    expect(once.changed).toBe(true)
    expect(once.hatched).toHaveLength(1)
    const twice = apply(once.zoo, ops)
    expect(twice).toEqual({ changed: false, zoo: once.zoo, hatched: [] })
  })

  it('never changes the zoo it was handed', () => {
    const start = zooOf({ daemons: [daemon('tim')], eggs: [egg('a')], pair: 'tim' })
    const copy = structuredClone(start)
    apply(start, [{ op: 'zoo.hatch', eggId: 'a' }, { op: 'zoo.nickname', id: 'tim', nickname: 'x' }, { op: 'zoo.habit', key: 'turn' }])
    expect(start).toEqual(copy)
  })

  it('reads a stored zoo entry by entry and drops what does not parse', () => {
    expect(parseZoo(null)).toEqual(emptyZoo())
    expect(parseZoo('junk')).toEqual(emptyZoo())
    expect(parseZoo([])).toEqual(emptyZoo())
    const stored = parseZoo({
      daemons: [daemon('tim'), daemon('retired'), { ...daemon('vim'), bond: -1 }, { ...daemon('zsh'), version: '9.9' }, { ...daemon('fish'), extra: 1 }, daemon('Bad Id'), 'junk'],
      eggs: [egg('a'), egg('a'), { id: 'b' }, egg('c', 'turn'), egg('bad id')],
      pair: 'vim',
      habits: ['turn', 'turn', 7, 'split'],
      firstEgg: 'yes',
      pity: -3,
      easter: ['xyzzy', null],
    })
    // A well-formed id the roster lacks survives a read: a rolled-back roster must not eat a daemon.
    expect(stored.daemons.map((d) => d.id)).toEqual(['tim', 'retired'])
    expect(stored.eggs.map((e) => e.id)).toEqual(['a', 'c'])
    expect(stored).toMatchObject({ pair: null, habits: ['turn', 'split'], firstEgg: false, pity: 0, easter: ['xyzzy'] })
    expect(parseZoo({ pity: 1e12 }).pity).toBe(1_000_000)
    expect(parseZoo({ daemons: Array.from({ length: 80 }, () => daemon('tim')) }).daemons).toHaveLength(ZOO_MAX_DAEMONS)
  })

  it('takes between 1 and 64 ops, each one of the six', () => {
    expect(zooOpsBodySchema.safeParse({ ops: [] }).success).toBe(false)
    expect(zooOpsBodySchema.safeParse({ ops: Array.from({ length: 65 }, () => ({ op: 'zoo.habit', key: 'turn' })) }).success).toBe(false)
    expect(zooOpsBodySchema.safeParse({ ops: [{ op: 'zoo.draw', daemonId: 'grue' }] }).success).toBe(false)
    expect(zooOpsBodySchema.safeParse({ ops: [{ op: 'zoo.hatch', eggId: 'a', daemonId: 'grue' }] }).success).toBe(false)   // no client-sent results
  })

  it('makes egg ids unlike any egg in the nest', () => {
    // The first ten rolls spell the id of the egg already there; the next try does not.
    const zoo = zooOf({ eggs: [egg('aaaaaaaaaa')] })
    const r = apply(zoo, [{ op: 'zoo.easter', word: 'xyzzy' }], scripted(Array(10).fill(0), seeded(3)))
    expect(r.zoo.eggs).toHaveLength(2)
    expect(r.zoo.eggs[1].id).not.toBe('aaaaaaaaaa')
  })
})
