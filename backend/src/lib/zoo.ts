/**
 * The zoo document and the operations that change it — pure, so the rules and the draw can be tested
 * without a database (daemons/README.md, "The zoo (server contract)", "First egg: habits" and "Earning
 * eggs and growing").
 *
 * The same ONE RULE as the desk (lib/desk.ts): every op is idempotent and an op on something that is
 * not there is dropped, never an error. A client that was offline replays its queue against a zoo that
 * moved and every op still means what it meant: a hatch of an egg already hatched lands on nothing, a
 * habit already counted counts once, a batch of turns already counted (its `batchId`) counts once.
 *
 * The draw happens here and only here. Clients never send a result; `rng` is injected so tests are
 * deterministic, and is `crypto.randomInt` in production. Eggs earned from work are granted here too:
 * a client reports turns, never eggs.
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
/** Eggs earned while the nest is full wait here, oldest first. 64 turn eggs is months at the daily cap;
 *  past that an earned egg is not kept. */
export const ZOO_MAX_HELD = 64
/** How many `zoo.turn` batch ids are remembered to drop a replay. A reporter retries within minutes. */
export const ZOO_BATCH_MEMORY = 64
/** The most turns one `zoo.turn` may report (a reporter batches a minute; the daily cap is far lower). */
export const ZOO_TURN_MAX_N = 50
/** A report may be this many days later than the latest local day on Earth still allows (a retry after
 *  an offline stretch); anything older, or a day that has not started anywhere yet, is dropped. */
export const ZOO_TURN_LATE_DAYS = 1
const ZOO_MAX_TURNS = 1_000_000_000
const ZOO_MAX_XP = 1_000_000_000
/** Days of per-day counts kept: two ISO weeks, so a week is always whole. */
const DAY_MEMORY = 14
const WEEK_MEMORY = 8
const HISTORY_MEMORY = 16
const DAY_MS = 86_400_000

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
const EARN = RULES.earn
const BOND_LEVELS: readonly number[] = RULES.bond.levels
const BOND_FOR_VERSION: Readonly<Record<string, number>> = RULES.bondForVersion
/** MM-DD → the daemon that date's history egg gives once a drop holds it, or null. */
const HISTORY_DATES: Readonly<Record<string, string | null>> = RULES.historyDates
/** Why a marathon egg was earned; each earns one, once. */
const MARATHON_REASONS = ['turns', 'machines'] as const

// ── Days, weeks and levels ───────────────────────────────────────────────────────────────────────
const DAY_RE = /^(\d{4})-(\d{2})-(\d{2})$/

/** A local calendar day, `YYYY-MM-DD`, that exists (no 02-30), in years 2000–2999. */
export function isLocalDay(s: string): boolean {
  const m = DAY_RE.exec(s)
  if (!m) return false
  const [y, mo, d] = [Number(m[1]), Number(m[2]), Number(m[3])]
  if (y < 2000 || y > 2999) return false
  const t = new Date(Date.UTC(y, mo - 1, d))
  return t.getUTCFullYear() === y && t.getUTCMonth() === mo - 1 && t.getUTCDate() === d
}

/** Days since 1970-01-01 of a calendar day — arithmetic on dates, no time zone involved. */
const dayNumber = (day: string): number => {
  const [y, m, d] = day.split('-').map(Number)
  return Date.UTC(y, m - 1, d) / DAY_MS
}

/** The ISO 8601 week a calendar day belongs to, `YYYY-Www` (weeks start on Monday; week 1 holds the
 *  year's first Thursday, so 2027-01-01 is in 2026-W53 and 2024-12-30 is in 2025-W01). */
export function isoWeek(day: string): string {
  const [y, m, d] = day.split('-').map(Number)
  const t = new Date(Date.UTC(y, m - 1, d))
  t.setUTCDate(t.getUTCDate() + 4 - (t.getUTCDay() || 7))          // the Thursday of that week
  const year = t.getUTCFullYear()
  const week = Math.floor((t.getTime() - Date.UTC(year, 0, 1)) / DAY_MS / 7) + 1
  return `${year}-W${String(week).padStart(2, '0')}`
}

/** Bond level for `xp`: the highest threshold of `rules.bond.levels` reached. */
export function levelFor(xp: number): number {
  let level = 0
  for (const [i, at] of BOND_LEVELS.entries()) if (xp >= at) level = i
  return level
}

/** The version a bond level has grown into (`rules.bondForVersion`). */
export function versionFor(level: number): string {
  let version = FIRST_VERSION
  for (const v of VERSIONS) if (level >= BOND_FOR_VERSION[v]) version = v
  return version
}

// ── Shapes ───────────────────────────────────────────────────────────────────────────────────────
/** A roster id's shape (the same rule daemons/tools/generate.mjs holds the roster to). */
const daemonId = z.string().regex(/^[a-z][a-z0-9-]{0,15}$/)
/** An egg id, a habit key, an egg kind, an easter word, a batch or machine id: short and id-safe. */
const key = z.string().min(1).max(64).regex(/^[A-Za-z0-9_-]+$/)
const isoTime = z.string().max(40).refine((s) => !Number.isNaN(Date.parse(s)), 'not a time')
const localDay = z.string().max(10).refine(isLocalDay, 'not a YYYY-MM-DD day')
/** 1–24 printable ASCII once trimmed: what a status line and a card can draw on every terminal. */
export const zooNicknameSchema = z.string().trim().regex(/^[\x20-\x7e]{1,24}$/, 'nickname must be 1-24 printable ASCII characters')

export const zooDaemonSchema = z.object({
  id: daemonId,
  hatchedAt: isoTime,
  egg: key,
  shiny: z.boolean(),
  nickname: zooNicknameSchema.optional(),
  bond: z.number().int().min(0).max(1_000_000),
  /** Absent on a daemon stored before xp existed; read as the least xp its bond needs. */
  xp: z.number().int().min(0).max(ZOO_MAX_XP).optional(),
  version: z.string().refine((v) => VERSIONS.includes(v), 'unknown version'),
}).strict()
/** `date` is the local day a history egg was earned on; its MM-DD picks the daemon it leans toward. */
export const zooEggSchema = z.object({ id: key, kind: key, grantedAt: isoTime, date: localDay.optional() }).strict()

export type ZooDaemon = Omit<z.infer<typeof zooDaemonSchema>, 'xp'> & { xp: number }
export type ZooEgg = z.infer<typeof zooEggSchema>
/** An egg earned while the nest was full, waiting for room. */
export interface ZooHeld { kind: string; date?: string }
/**
 * What counts toward the eggs earned from work (README, "Earning eggs and growing"). Server-written:
 * clients read it to show how close the next egg is and never send it (except a guest's, once, in
 * `zoo.seed`).
 */
export interface ZooProgress {
  /** Counted turns, all time (after the daily cap). A turn egg every `earn.turn.every`. */
  turns: number
  /** Counted turns per local day, the last two weeks. The daily cap and the week egg read this. */
  days: Record<string, number>
  /** ISO weeks whose week egg was earned, the last few. */
  weeks: string[]
  /** Local days with a counted turn in the night hours since the last night egg. */
  nights: string[]
  /** The first machines turns were reported from (up to `earn.marathon.machines`). */
  machines: string[]
  /** Marathon eggs earned, by reason: `turns`, `machines`. */
  marathon: string[]
  /** Local days whose history egg was earned, the last few. */
  history: string[]
  /** Eggs earned while the nest was full, oldest first. */
  held: ZooHeld[]
  /** The last `zoo.turn` batch ids applied. */
  batches: string[]
}
export interface Zoo {
  daemons: ZooDaemon[]
  eggs: ZooEgg[]
  pair: string | null
  habits: string[]
  firstEgg: boolean
  pity: number
  easter: string[]
  progress: ZooProgress
}
export interface ZooDoc { revision: number; zoo: Zoo }
export interface Hatched { eggId: string; daemonId: string; shiny: boolean }
/** An egg that arrived in the nest during this request (earned now, or held until there was room). */
export interface Grant { kind: string; eggId: string }
/** A daemon whose bond reached a new level during this request, and the version it is now. */
export interface LevelUp { id: string; level: number; version: string }

export const emptyProgress = (): ZooProgress =>
  ({ turns: 0, days: {}, weeks: [], nights: [], machines: [], marathon: [], history: [], held: [], batches: [] })
export const emptyZoo = (): Zoo =>
  ({ daemons: [], eggs: [], pair: null, habits: [], firstEgg: false, pity: 0, easter: [], progress: emptyProgress() })

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
  // Turns that finished on one machine, all in one local hour of one local day. harnessd sends it.
  z.object({
    op: z.literal('zoo.turn'),
    batchId: key,
    n: z.number().int().min(1).max(ZOO_TURN_MAX_N),
    day: localDay,
    hour: z.number().int().min(0).max(23),
    machineId: key,
  }).strict(),
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

/** Like uniqueStrings, but a memory: when there are too many, the newest (last) are the ones kept. */
function lastStrings(raw: unknown, keep: (s: string) => boolean, max: number): string[] {
  return uniqueStrings(Array.isArray(raw) ? raw : [], keep, Number.MAX_SAFE_INTEGER).slice(-max)
}

const wholeIn = (raw: unknown, max: number): number =>
  typeof raw === 'number' && Number.isInteger(raw) && raw >= 0 ? Math.min(raw, max) : 0

/** Forget per-day counts older than two weeks before the newest day counted. */
function pruneDays(days: Record<string, number>): void {
  const keys = Object.keys(days)
  if (!keys.length) return
  const newest = Math.max(...keys.map(dayNumber))
  for (const day of keys) if (dayNumber(day) <= newest - DAY_MEMORY) delete days[day]
}

/** The zoo's progress as stored (or seeded), piece by piece; a malformed piece reads as nothing yet. */
function parseProgress(raw: unknown, strict: boolean): ZooProgress {
  const src = record(raw)
  const days: Record<string, number> = {}
  for (const [day, n] of Object.entries(record(src.days))) {
    if (isLocalDay(day) && typeof n === 'number' && Number.isInteger(n) && n > 0) days[day] = Math.min(n, EARN.turn.dailyCap)
  }
  pruneDays(days)
  const held: ZooHeld[] = []
  if (Array.isArray(src.held)) {
    for (const item of src.held) {
      const h = record(item)
      if (typeof h.kind !== 'string' || !key.safeParse(h.kind).success) continue
      if (strict && !eggRule(h.kind)) continue
      held.push(typeof h.date === 'string' && isLocalDay(h.date) ? { kind: h.kind, date: h.date } : { kind: h.kind })
      if (held.length >= ZOO_MAX_HELD) break
    }
  }
  return {
    turns: wholeIn(src.turns, ZOO_MAX_TURNS),
    days,
    weeks: lastStrings(src.weeks, (w) => /^\d{4}-W\d{2}$/.test(w), WEEK_MEMORY),
    nights: lastStrings(src.nights, isLocalDay, EARN.night.nights - 1),
    machines: uniqueStrings(src.machines, () => true, EARN.marathon.machines),
    marathon: uniqueStrings(src.marathon, (r) => (MARATHON_REASONS as readonly string[]).includes(r), MARATHON_REASONS.length),
    history: lastStrings(src.history, isLocalDay, HISTORY_MEMORY),
    held,
    batches: lastStrings(src.batches, () => true, ZOO_BATCH_MEMORY),
  }
}

/** A daemon's bond and version follow its xp. A daemon stored before xp existed gets the least xp its
 *  stored bond needs, so reading never lowers a level. */
function grown(d: z.infer<typeof zooDaemonSchema>): ZooDaemon {
  const xp = d.xp ?? BOND_LEVELS[Math.min(d.bond, BOND_LEVELS.length - 1)]
  const bond = levelFor(xp)
  return { ...d, xp, bond, version: versionFor(bond) }
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
      daemons.push(grown(parsed.data))
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
    progress: parseProgress(src.progress, strict),
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

/**
 * The daemon a history egg from `date` gives: that date's daemon from `rules.historyDates`, when a
 * released drop holds it and you do not own it yet. Otherwise null, and the egg draws like any other.
 */
export function historyDaemon(zoo: Zoo, date: string | undefined): RosterDaemon | null {
  if (!date) return null
  const mmdd = date.slice(5)
  const id = Object.hasOwn(HISTORY_DATES, mmdd) ? HISTORY_DATES[mmdd] : null
  if (!id || zoo.daemons.some((d) => d.id === id)) return null
  return RELEASED.find((d) => d.id === id) ?? null
}

/** The draw for one egg: a history egg's own daemon when it has one to give, else the usual draw. */
function drawEgg(zoo: Zoo, egg: ZooEgg, rng: Rng): { id: string; rarity: string; shiny: boolean } | null {
  const own = egg.kind === 'history' ? historyDaemon(zoo, egg.date) : null
  if (own) return { id: own.id, rarity: own.rarity, shiny: rng(RULES.shinyOneIn) === 0 }
  return draw(zoo, egg.kind, rng)
}

// ── Ops ──────────────────────────────────────────────────────────────────────────────────────────
const EGG_ID_ALPHABET = 'abcdefghijkmnpqrstuvwxyz23456789'   // 32 symbols: no 0/o, 1/l
const EGG_ID_LENGTH = 10                                     // 50 bits: an id is never reused in practice

/** What one request produced besides the zoo itself. */
interface Outcome { hatched: Hatched[]; grants: Grant[]; levelUps: LevelUp[] }

/** What the route knows that the document does not. */
export interface ZooContext {
  /** Whether a machine id is one of the account's machines. Only those count as a machine seen (the
   *  second-machine marathon egg); every reported turn counts either way. Absent: every id counts. */
  ownsMachine?: (machineId: string) => boolean
}

/** A fresh egg id, unlike any egg in the zoo. Random, so a replayed hatch of an egg long gone can never
 *  land on a new egg that happens to share its name. */
function newEggId(zoo: Pick<Zoo, 'eggs'>, rng: Rng): string {
  for (;;) {
    let id = ''
    for (let i = 0; i < EGG_ID_LENGTH; i++) id += EGG_ID_ALPHABET[rng(EGG_ID_ALPHABET.length)]
    if (!zoo.eggs.some((e) => e.id === id)) return id
  }
}

function grantEgg(zoo: Zoo, kind: string, rng: Rng, now: Date, out: Outcome, date?: string): boolean {
  if (zoo.eggs.length >= ZOO_MAX_EGGS) return false
  const egg: ZooEgg = { id: newEggId(zoo, rng), kind, grantedAt: now.toISOString(), ...(date ? { date } : {}) }
  zoo.eggs.push(egg)
  out.grants.push({ kind, eggId: egg.id })
  return true
}

/** An egg earned from work. It joins the queue of held eggs, which `releaseHeld` empties into the nest
 *  while there is room — so an egg earned with a full nest waits its turn instead of being lost. */
function earnEgg(zoo: Zoo, kind: string, date?: string): void {
  if (zoo.progress.held.length >= ZOO_MAX_HELD) return
  zoo.progress.held.push(date ? { kind, date } : { kind })
}

/** Held eggs into the nest, oldest first, while there is room. Runs after every op, so a hatch that
 *  frees a place lets the next waiting egg in. */
function releaseHeld(zoo: Zoo, rng: Rng, now: Date, out: Outcome): boolean {
  let changed = false
  while (zoo.progress.held.length && zoo.eggs.length < ZOO_MAX_EGGS) {
    const next = zoo.progress.held.shift()!
    grantEgg(zoo, next.kind, rng, now, out, next.date)
    changed = true
  }
  return changed
}

/** The first egg, when enough habits are done and it has not been given. Checked on every habit op, so
 *  a grant that found the nest full happens on the next one. */
function maybeGrantFirstEgg(zoo: Zoo, rng: Rng, now: Date, out: Outcome): boolean {
  if (zoo.firstEgg) return false
  const done = zoo.habits.filter((h) => HABIT_KEYS.has(h)).length
  if (done < RULES.firstEgg.need) return false
  if (!grantEgg(zoo, 'first', rng, now, out)) return false
  zoo.firstEgg = true
  return true
}

/** xp for the paired daemon (the first one hatched with that id); a new level bumps bond and version. */
function addXp(zoo: Zoo, xp: number, out: Outcome): void {
  const d = zoo.pair === null ? undefined : zoo.daemons.find((x) => x.id === zoo.pair)
  if (!d || xp <= 0) return
  d.xp = Math.min(d.xp + xp, ZOO_MAX_XP)
  const level = levelFor(d.xp)
  if (level <= d.bond) return
  d.bond = level
  d.version = versionFor(level)
  out.levelUps.push({ id: d.id, level, version: d.version })
}

/** Whether a reported local day can be today somewhere on Earth (UTC-12 to UTC+14), or is at most
 *  `ZOO_TURN_LATE_DAYS` later than that. */
function dayInWindow(day: string, now: Date): boolean {
  const today = Math.floor(now.getTime() / DAY_MS)
  const at = dayNumber(day)
  return at >= today - 1 - ZOO_TURN_LATE_DAYS && at <= today + 1
}

type TurnOp = Extract<ZooOp, { op: 'zoo.turn' }>

/**
 * Turns finished on one machine (README, "Earning eggs and growing"). In order: the daily cap decides
 * how many count; counted turns earn turn eggs, the 500-turn marathon egg, a worked day toward the week
 * egg, a night toward the night egg, and a history date's egg; the paired daemon gets xp for each and
 * for the first counted turn of the day. A machine seen may earn the second-machine marathon egg.
 */
function applyTurn(zoo: Zoo, op: TurnOp, now: Date, out: Outcome, ctx: ZooContext): boolean {
  const p = zoo.progress
  if (p.batches.includes(op.batchId) || !dayInWindow(op.day, now)) return false
  let changed = false

  const machines = EARN.marathon.machines
  if (!p.machines.includes(op.machineId) && p.machines.length < machines && (ctx.ownsMachine?.(op.machineId) ?? true)) {
    p.machines.push(op.machineId)
    changed = true
    if (p.machines.length >= machines && !p.marathon.includes('machines')) {
      p.marathon.push('machines')
      earnEgg(zoo, 'marathon')
    }
  }

  const before = p.days[op.day] ?? 0
  const counted = Math.max(0, Math.min(op.n, EARN.turn.dailyCap - before))
  if (counted > 0) {
    changed = true
    p.days[op.day] = before + counted
    pruneDays(p.days)

    const turnsBefore = p.turns
    p.turns = Math.min(p.turns + counted, ZOO_MAX_TURNS)
    const every = EARN.turn.every
    for (let k = Math.floor(turnsBefore / every); k < Math.floor(p.turns / every); k++) earnEgg(zoo, 'turn')
    if (p.turns >= EARN.marathon.turns && !p.marathon.includes('turns')) {
      p.marathon.push('turns')
      earnEgg(zoo, 'marathon')
    }

    const week = isoWeek(op.day)
    if (!p.weeks.includes(week) && Object.keys(p.days).filter((d) => isoWeek(d) === week).length >= EARN.week.days) {
      p.weeks = [...p.weeks, week].slice(-WEEK_MEMORY)
      earnEgg(zoo, 'week')
    }

    if (op.hour >= EARN.night.fromHour && op.hour <= EARN.night.toHour && !p.nights.includes(op.day)) {
      p.nights.push(op.day)
      if (p.nights.length >= EARN.night.nights) {
        p.nights = []
        earnEgg(zoo, 'night')
      }
    }

    if (Object.hasOwn(HISTORY_DATES, op.day.slice(5)) && !p.history.includes(op.day)) {
      p.history = [...p.history, op.day].slice(-HISTORY_MEMORY)
      earnEgg(zoo, 'history', op.day)
    }

    addXp(zoo, counted * RULES.bond.xpPerTurn + (before === 0 ? RULES.bond.xpPerDay : 0), out)
  }

  // A batch that changed nothing (the day's cap was already reached) is not remembered: replayed, it
  // still changes nothing, and not writing it spares every client a re-fetch each minute past the cap.
  if (changed) p.batches = [...p.batches, op.batchId].slice(-ZOO_BATCH_MEMORY)
  return changed
}

const isEmpty = (zoo: Zoo): boolean => zoo.daemons.length === 0 && zoo.eggs.length === 0 && zoo.habits.length === 0

const cloneProgress = (p: ZooProgress): ZooProgress => ({
  turns: p.turns,
  days: { ...p.days },
  weeks: [...p.weeks],
  nights: [...p.nights],
  machines: [...p.machines],
  marathon: [...p.marathon],
  history: [...p.history],
  held: p.held.map((h) => ({ ...h })),
  batches: [...p.batches],
})

const clone = (zoo: Zoo): Zoo => ({
  daemons: zoo.daemons.map((d) => ({ ...d })),
  eggs: zoo.eggs.map((e) => ({ ...e })),
  pair: zoo.pair,
  habits: [...zoo.habits],
  firstEgg: zoo.firstEgg,
  pity: zoo.pity,
  easter: [...zoo.easter],
  progress: cloneProgress(zoo.progress),
})

/**
 * Apply one op to `zoo` IN PLACE (applyZooOps hands it a copy). Returns whether anything changed; what
 * it hatched, granted or levelled goes into `out`.
 *
 * Duplicates share their roster id, so `zoo.pair` and `zoo.nickname` name a daemon by id and address
 * the first one hatched with it.
 */
function applyZooOp(zoo: Zoo, op: ZooOp, rng: Rng, now: Date, out: Outcome, ctx: ZooContext): boolean {
  switch (op.op) {
    case 'zoo.habit': {
      if (!HABIT_KEYS.has(op.key)) return false
      let changed = false
      if (!zoo.habits.includes(op.key)) { zoo.habits.push(op.key); changed = true }
      if (maybeGrantFirstEgg(zoo, rng, now, out)) changed = true
      return changed
    }
    case 'zoo.hatch': {
      const i = zoo.eggs.findIndex((e) => e.id === op.eggId)
      if (i < 0 || zoo.daemons.length >= ZOO_MAX_DAEMONS) return false
      const egg = zoo.eggs[i]
      const drawn = drawEgg(zoo, egg, rng)
      if (!drawn) return false                                   // a kind this roster cannot draw
      zoo.eggs.splice(i, 1)
      zoo.daemons.push({ id: drawn.id, hatchedAt: now.toISOString(), egg: egg.kind, shiny: drawn.shiny, bond: 0, xp: 0, version: FIRST_VERSION })
      zoo.pity = drawn.rarity === 'secret' ? 0 : Math.min(zoo.pity + 1, ZOO_MAX_PITY)
      if (zoo.pair === null) zoo.pair = drawn.id
      out.hatched.push({ eggId: egg.id, daemonId: drawn.id, shiny: drawn.shiny })
      return true
    }
    case 'zoo.pair': {
      if (zoo.pair === op.id || !zoo.daemons.some((d) => d.id === op.id)) return false
      zoo.pair = op.id
      return true
    }
    case 'zoo.nickname': {
      const d = zoo.daemons.find((x) => x.id === op.id)
      if (!d || (d.nickname ?? null) === op.nickname) return false
      if (op.nickname === null) delete d.nickname
      else d.nickname = op.nickname
      return true
    }
    case 'zoo.easter': {
      if (!EASTER_WORDS.has(op.word) || zoo.easter.includes(op.word)) return false
      // A full nest leaves the word unspent, so saying it again later still works.
      if (!grantEgg(zoo, 'easter', rng, now, out)) return false
      zoo.easter.push(op.word)
      return true
    }
    case 'zoo.seed': {
      if (!isEmpty(zoo)) return false
      const seed = parseZoo(op.zoo, { roster: true })
      if (isEmpty(seed) && !seed.firstEgg && seed.easter.length === 0 && seed.pity === 0 && seed.progress.turns === 0) return false
      // Egg ids are the server's to give: a seeded egg is renamed on the way in.
      const eggs: ZooEgg[] = []
      for (const egg of seed.eggs) eggs.push({ ...egg, id: newEggId({ eggs }, rng) })
      // The guest's progress counts, but not its machine ids (a guest's are not the account's machines)
      // or batch ids. Turns this account already reported from a signed-in harnessd are kept instead.
      const fresh = zoo.progress.turns === 0 && zoo.progress.batches.length === 0
      const progress = fresh ? { ...seed.progress, machines: [], batches: [] } : zoo.progress
      Object.assign(zoo, seed, { eggs, pair: seed.pair ?? seed.daemons[0]?.id ?? null, progress })
      return true
    }
    case 'zoo.turn':
      return applyTurn(zoo, op, now, out, ctx)
  }
}

/** Apply `ops` in order to a copy of `zoo`. `changed` is false when every op was a no-op — the same
 *  request twice, or ops on things already gone — and then nothing needs writing. After every op any
 *  held egg that now fits is let into the nest. */
export function applyZooOps(
  zoo: Zoo, ops: ZooOp[], rng: Rng = cryptoRng, now: Date = new Date(), ctx: ZooContext = {},
): { changed: boolean; zoo: Zoo } & Outcome {
  const next = clone(zoo)
  const out: Outcome = { hatched: [], grants: [], levelUps: [] }
  let changed = false
  for (const op of ops) {
    if (applyZooOp(next, op, rng, now, out, ctx)) changed = true
    if (releaseHeld(next, rng, now, out)) changed = true
  }
  return { changed, zoo: next, ...out }
}
