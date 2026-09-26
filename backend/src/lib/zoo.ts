/**
 * The zoo document and the operations that change it — pure, so the rules and the draw can be tested
 * without a database (daemons/README.md, "The zoo (server contract)" and "First egg: habits").
 *
 * The same ONE RULE as the desk (lib/desk.ts): every op is idempotent and an op on something that is
 * not there is dropped, never an error. A client that was offline replays its queue against a zoo that
 * moved and every op still means what it meant: a hatch of an egg already hatched lands on nothing, a
 * habit already counted counts once.
 *
 * The draw happens here and only here. Clients never send a result; `rng` is injected so tests are
 * deterministic, and is `crypto.randomInt` in production.
 */
import { randomInt } from 'node:crypto'
import { z } from 'zod'
import { DAEMON_ROSTER } from './daemonRoster.g.js'

export const ZOO_MAX_EGGS = 12
export const ZOO_MAX_DAEMONS = 64
export const ZOO_NICKNAME_MAX = 24
/** Far past anything a real account reaches (it resets on every secret); a bound keeps the draw's
 *  integer weights inside `randomInt`'s range whatever a stored document says. */
export const ZOO_MAX_PITY = 1_000_000

/** A uniform integer in [0, n). */
export type Rng = (n: number) => number
export const cryptoRng: Rng = (n) => randomInt(n)

// ── What the roster says ─────────────────────────────────────────────────────────────────────────
interface EggRule { weights: Readonly<Record<string, number>>; boost?: Readonly<Record<string, number>> }
interface RosterDaemon { id: string; n: number; drop: string; rarity: string }

const RULES = DAEMON_ROSTER.rules
const EGG_RULES: Readonly<Record<string, EggRule>> = RULES.eggs
/** The rule for an egg kind — own keys only, so a kind spelled `constructor` is simply unknown. */
const eggRule = (kind: string): EggRule | undefined => Object.hasOwn(EGG_RULES, kind) ? EGG_RULES[kind] : undefined
const ROSTER_DAEMONS: readonly RosterDaemon[] = DAEMON_ROSTER.daemons
const RELEASED_DROPS: ReadonlySet<string> = new Set<string>(DAEMON_ROSTER.drops)
const ROSTER_IDS: ReadonlySet<string> = new Set(ROSTER_DAEMONS.map((d) => d.id))
const HABIT_KEYS: ReadonlySet<string> = new Set<string>(RULES.firstEgg.habits)
const EASTER_WORDS: ReadonlySet<string> = new Set<string>(RULES.easterWords)
const VERSIONS: readonly string[] = RULES.versions
const FIRST_VERSION = VERSIONS[0]
/** Every daemon a draw may give: the released drops, in roster order. */
const RELEASED: readonly RosterDaemon[] = ROSTER_DAEMONS.filter((d) => RELEASED_DROPS.has(d.drop))

// ── Shapes ───────────────────────────────────────────────────────────────────────────────────────
/** A roster id's shape (the same rule daemons/tools/generate.mjs holds the roster to). */
const daemonId = z.string().regex(/^[a-z][a-z0-9-]{0,15}$/)
/** An egg id, a habit key, an egg kind, an easter word: short and id-safe. */
const key = z.string().min(1).max(64).regex(/^[A-Za-z0-9_-]+$/)
const isoTime = z.string().max(40).refine((s) => !Number.isNaN(Date.parse(s)), 'not a time')
/** 1–24 printable ASCII once trimmed: what a status line and a card can draw on every terminal. */
export const zooNicknameSchema = z.string().trim().regex(/^[\x20-\x7e]{1,24}$/, 'nickname must be 1-24 printable ASCII characters')

export const zooDaemonSchema = z.object({
  id: daemonId,
  hatchedAt: isoTime,
  egg: key,
  shiny: z.boolean(),
  nickname: zooNicknameSchema.optional(),
  bond: z.number().int().min(0).max(1_000_000),
  version: z.string().refine((v) => VERSIONS.includes(v), 'unknown version'),
}).strict()
export const zooEggSchema = z.object({ id: key, kind: key, grantedAt: isoTime }).strict()

export type ZooDaemon = z.infer<typeof zooDaemonSchema>
export type ZooEgg = z.infer<typeof zooEggSchema>
export interface Zoo {
  daemons: ZooDaemon[]
  eggs: ZooEgg[]
  pair: string | null
  habits: string[]
  firstEgg: boolean
  pity: number
  easter: string[]
}
export interface ZooDoc { revision: number; zoo: Zoo }
export interface Hatched { eggId: string; daemonId: string; shiny: boolean }

export const emptyZoo = (): Zoo => ({ daemons: [], eggs: [], pair: null, habits: [], firstEgg: false, pity: 0, easter: [] })

// Names in ops are plain strings rather than roster enums on purpose: a newer client naming a habit or
// a word this server does not know yet gets that op dropped, not the whole batch refused.
export const zooOpSchema = z.discriminatedUnion('op', [
  z.object({ op: z.literal('zoo.habit'), key }).strict(),
  z.object({ op: z.literal('zoo.hatch'), eggId: key }).strict(),
  z.object({ op: z.literal('zoo.pair'), id: daemonId }).strict(),
  z.object({ op: z.literal('zoo.nickname'), id: daemonId, nickname: zooNicknameSchema.nullable() }).strict(),
  z.object({ op: z.literal('zoo.easter'), word: z.string().min(1).max(64) }).strict(),
  // A guest's local zoo, read entry by entry like a stored one (a bad entry is dropped, not the seed).
  z.object({ op: z.literal('zoo.seed'), zoo: z.record(z.string(), z.unknown()) }).strict(),
])
export type ZooOp = z.infer<typeof zooOpSchema>

export const zooOpsBodySchema = z.object({
  ops: z.array(zooOpSchema).min(1).max(64),
}).strict()

// ── Reading a stored (or seeded) zoo ─────────────────────────────────────────────────────────────
const record = (raw: unknown): Record<string, unknown> =>
  typeof raw === 'object' && raw !== null && !Array.isArray(raw) ? raw as Record<string, unknown> : {}

function uniqueStrings(raw: unknown, keep: (s: string) => boolean, max: number): string[] {
  if (!Array.isArray(raw)) return []
  const out: string[] = []
  for (const item of raw) {
    if (typeof item !== 'string' || !key.safeParse(item).success || !keep(item) || out.includes(item)) continue
    out.push(item)
    if (out.length >= max) break
  }
  return out
}

/**
 * The zoo as stored (Json), validated entry by entry; anything malformed is dropped rather than served.
 *
 * `roster: true` (a guest's seed) also drops what the roster does not know: daemons, egg kinds,
 * habits and words. A STORED zoo keeps a well-formed daemon id the roster lacks — a roster rolled back
 * must not delete someone's daemon on their next write.
 */
export function parseZoo(raw: unknown, opts: { roster?: boolean } = {}): Zoo {
  const src = record(raw)
  const strict = !!opts.roster
  const daemons: ZooDaemon[] = []
  if (Array.isArray(src.daemons)) {
    for (const item of src.daemons) {
      const parsed = zooDaemonSchema.safeParse(item)
      if (!parsed.success) continue
      if (strict && (!ROSTER_IDS.has(parsed.data.id) || !eggRule(parsed.data.egg))) continue
      daemons.push(parsed.data)
      if (daemons.length >= ZOO_MAX_DAEMONS) break
    }
  }
  const eggs: ZooEgg[] = []
  if (Array.isArray(src.eggs)) {
    for (const item of src.eggs) {
      const parsed = zooEggSchema.safeParse(item)
      if (!parsed.success || eggs.some((e) => e.id === parsed.data.id)) continue
      if (strict && !eggRule(parsed.data.kind)) continue
      eggs.push(parsed.data)
      if (eggs.length >= ZOO_MAX_EGGS) break
    }
  }
  const pair = typeof src.pair === 'string' && daemons.some((d) => d.id === src.pair) ? src.pair : null
  const pity = typeof src.pity === 'number' && Number.isInteger(src.pity) && src.pity >= 0 ? Math.min(src.pity, ZOO_MAX_PITY) : 0
  return {
    daemons,
    eggs,
    pair,
    habits: uniqueStrings(src.habits, (h) => !strict || HABIT_KEYS.has(h), 64),
    firstEgg: src.firstEgg === true,
    pity,
    easter: uniqueStrings(src.easter, (w) => !strict || EASTER_WORDS.has(w), 64),
  }
}

// ── The draw ─────────────────────────────────────────────────────────────────────────────────────
/** Weights are whole units so `randomInt` can draw them exactly; a millionth is far below any odds. */
const WEIGHT_UNITS = 1_000_000

/**
 * Who can come out of an egg of `kind` for this zoo, and how likely, in whole units (README, "The draw"):
 *
 *  1. Eligible: every released daemon not owned; when all are owned, duplicates are allowed again.
 *  2. Weight: `weights[rarity] / (eligible of that rarity)`, plus `pity * pityPerMiss` for a secret,
 *     times `boost[id]`. A rarity with no eligible daemon gives its weight to nothing.
 *
 * One case the README leaves open: an egg whose unowned daemons all weigh nothing (an easter egg once
 * every legendary and secret is owned). That egg draws as if everything were owned — duplicates of what
 * it can give — rather than giving nobody.
 */
export function drawWeights(zoo: Zoo, kind: string): Array<{ id: string; rarity: string; weight: number }> {
  const egg = eggRule(kind)
  if (!egg) return []
  const owned = new Set(zoo.daemons.map((d) => d.id))
  const unowned = RELEASED.filter((d) => !owned.has(d.id))
  const weigh = (pool: readonly RosterDaemon[]) => {
    const perRarity = new Map<string, number>()
    for (const d of pool) perRarity.set(d.rarity, (perRarity.get(d.rarity) ?? 0) + 1)
    return pool.map((d) => {
      const base = (egg.weights[d.rarity] ?? 0) / perRarity.get(d.rarity)!
      const pity = d.rarity === 'secret' ? zoo.pity * RULES.pityPerMiss : 0
      const boost = egg.boost && Object.hasOwn(egg.boost, d.id) ? egg.boost[d.id] : 1
      return { id: d.id, rarity: d.rarity, weight: Math.round((base + pity) * boost * WEIGHT_UNITS) }
    })
  }
  const fresh = weigh(unowned)
  return fresh.some((w) => w.weight > 0) ? fresh : weigh(RELEASED)
}

/** One draw: who hatches, then (independently) whether it is shiny. `rng` is called in that order. */
export function draw(zoo: Zoo, kind: string, rng: Rng): { id: string; rarity: string; shiny: boolean } | null {
  const weights = drawWeights(zoo, kind)
  const total = weights.reduce((sum, w) => sum + w.weight, 0)
  if (total <= 0) return null
  let at = rng(total)
  let picked = weights[weights.length - 1]
  for (const w of weights) {
    if (at < w.weight) { picked = w; break }
    at -= w.weight
  }
  return { id: picked.id, rarity: picked.rarity, shiny: rng(RULES.shinyOneIn) === 0 }
}

// ── Ops ──────────────────────────────────────────────────────────────────────────────────────────
const EGG_ID_ALPHABET = 'abcdefghijkmnpqrstuvwxyz23456789'   // 32 symbols: no 0/o, 1/l
const EGG_ID_LENGTH = 10                                     // 50 bits: an id is never reused in practice

/** A fresh egg id, unlike any egg in the zoo. Random, so a replayed hatch of an egg long gone can never
 *  land on a new egg that happens to share its name. */
function newEggId(zoo: Zoo, rng: Rng): string {
  for (;;) {
    let id = ''
    for (let i = 0; i < EGG_ID_LENGTH; i++) id += EGG_ID_ALPHABET[rng(EGG_ID_ALPHABET.length)]
    if (!zoo.eggs.some((e) => e.id === id)) return id
  }
}

function grantEgg(zoo: Zoo, kind: string, rng: Rng, now: Date): boolean {
  if (zoo.eggs.length >= ZOO_MAX_EGGS) return false
  zoo.eggs.push({ id: newEggId(zoo, rng), kind, grantedAt: now.toISOString() })
  return true
}

/** The first egg, when enough habits are done and it has not been given. Checked on every habit op, so
 *  a grant that found the nest full happens on the next one. */
function maybeGrantFirstEgg(zoo: Zoo, rng: Rng, now: Date): boolean {
  if (zoo.firstEgg) return false
  const done = zoo.habits.filter((h) => HABIT_KEYS.has(h)).length
  if (done < RULES.firstEgg.need) return false
  if (!grantEgg(zoo, 'first', rng, now)) return false
  zoo.firstEgg = true
  return true
}

const isEmpty = (zoo: Zoo): boolean => zoo.daemons.length === 0 && zoo.eggs.length === 0 && zoo.habits.length === 0

const clone = (zoo: Zoo): Zoo => ({
  daemons: zoo.daemons.map((d) => ({ ...d })),
  eggs: zoo.eggs.map((e) => ({ ...e })),
  pair: zoo.pair,
  habits: [...zoo.habits],
  firstEgg: zoo.firstEgg,
  pity: zoo.pity,
  easter: [...zoo.easter],
})

/**
 * Apply one op to `zoo` IN PLACE (applyZooOps hands it a copy). Returns whether anything changed and,
 * for a hatch, what came out.
 *
 * Duplicates share their roster id, so `zoo.pair` and `zoo.nickname` name a daemon by id and address
 * the first one hatched with it.
 */
function applyZooOp(zoo: Zoo, op: ZooOp, rng: Rng, now: Date): { changed: boolean; hatched?: Hatched } {
  switch (op.op) {
    case 'zoo.habit': {
      if (!HABIT_KEYS.has(op.key)) return { changed: false }
      let changed = false
      if (!zoo.habits.includes(op.key)) { zoo.habits.push(op.key); changed = true }
      if (maybeGrantFirstEgg(zoo, rng, now)) changed = true
      return { changed }
    }
    case 'zoo.hatch': {
      const i = zoo.eggs.findIndex((e) => e.id === op.eggId)
      if (i < 0 || zoo.daemons.length >= ZOO_MAX_DAEMONS) return { changed: false }
      const egg = zoo.eggs[i]
      const out = draw(zoo, egg.kind, rng)
      if (!out) return { changed: false }                        // a kind this roster cannot draw
      zoo.eggs.splice(i, 1)
      zoo.daemons.push({ id: out.id, hatchedAt: now.toISOString(), egg: egg.kind, shiny: out.shiny, bond: 0, version: FIRST_VERSION })
      zoo.pity = out.rarity === 'secret' ? 0 : Math.min(zoo.pity + 1, ZOO_MAX_PITY)
      if (zoo.pair === null) zoo.pair = out.id
      return { changed: true, hatched: { eggId: egg.id, daemonId: out.id, shiny: out.shiny } }
    }
    case 'zoo.pair': {
      if (zoo.pair === op.id || !zoo.daemons.some((d) => d.id === op.id)) return { changed: false }
      zoo.pair = op.id
      return { changed: true }
    }
    case 'zoo.nickname': {
      const d = zoo.daemons.find((x) => x.id === op.id)
      if (!d || (d.nickname ?? null) === op.nickname) return { changed: false }
      if (op.nickname === null) delete d.nickname
      else d.nickname = op.nickname
      return { changed: true }
    }
    case 'zoo.easter': {
      if (!EASTER_WORDS.has(op.word) || zoo.easter.includes(op.word)) return { changed: false }
      // A full nest leaves the word unspent, so saying it again later still works.
      if (!grantEgg(zoo, 'easter', rng, now)) return { changed: false }
      zoo.easter.push(op.word)
      return { changed: true }
    }
    case 'zoo.seed': {
      if (!isEmpty(zoo)) return { changed: false }
      const seed = parseZoo(op.zoo, { roster: true })
      if (isEmpty(seed) && !seed.firstEgg && seed.easter.length === 0 && seed.pity === 0) return { changed: false }
      // Egg ids are the server's to give: a seeded egg is renamed on the way in.
      const eggs: ZooEgg[] = []
      for (const egg of seed.eggs) {
        const renamed = { ...egg, id: newEggId({ ...seed, eggs }, rng) }
        eggs.push(renamed)
      }
      Object.assign(zoo, seed, { eggs, pair: seed.pair ?? seed.daemons[0]?.id ?? null })
      return { changed: true }
    }
  }
}

/** Apply `ops` in order to a copy of `zoo`. `changed` is false when every op was a no-op — the same
 *  request twice, or ops on things already gone — and then nothing needs writing. */
export function applyZooOps(zoo: Zoo, ops: ZooOp[], rng: Rng = cryptoRng, now: Date = new Date()): { changed: boolean; zoo: Zoo; hatched: Hatched[] } {
  const next = clone(zoo)
  const hatched: Hatched[] = []
  let changed = false
  for (const op of ops) {
    const result = applyZooOp(next, op, rng, now)
    changed ||= result.changed
    if (result.hatched) hatched.push(result.hatched)
  }
  return { changed, zoo: next, hatched }
}
