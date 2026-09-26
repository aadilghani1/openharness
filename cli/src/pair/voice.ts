/**
 * The daemon's voice, as the pair brain speaks it (daemons/README.md "Voice", BRAIN.md "Three tiers").
 *
 * Two halves:
 *   - TEMPLATE LINES (tier 0): the paired daemon's own roster line for the mood, with the example facts in
 *     it swapped for real ones. Roster lines are written about an example harness ("codex@office wants to
 *     run the migration"); a line is used only when, once its example harness is replaced by the real one,
 *     it claims nothing else that might be false. Otherwise the fact is said plainly. Every line carries
 *     information: the harness, and what it wants or did.
 *   - PairVoice: whether a line may be said at all. Silent by default; it speaks for need, done (20 s
 *     cooldown), fail and back; never the same line twice (a reconnect is not a reason to repeat); and a
 *     line about a question answered elsewhere is taken back (`daemon_unsay`).
 *
 * Everything goes out through `sendLocal` — loopback only. `send()` would upload it, unencrypted.
 */
import { PAIR_ROSTER } from './roster.g.js'
import { statusText, type DaemonMood, type DaemonSay } from './protocol.js'

type Mood = keyof (typeof PAIR_ROSTER.daemons)[number]['lines']

export function rosterLine(daemonId: string, mood: Mood): string | null {
  const daemon = PAIR_ROSTER.daemons.find((d) => d.id === daemonId)
  return daemon ? daemon.lines[mood] : null
}

export function isRosterDaemon(id: unknown): id is string {
  return typeof id === 'string' && PAIR_ROSTER.daemons.some((d) => d.id === id)
}

/** The example harness the roster's lines are written about. */
const WHO = /\bcodex@office\b|\bclaude\b|\bcodex\b/i
/** Facts only the example had. A line still holding one after the swap would be telling a story. */
const EXAMPLE_FACTS = /\d|\b(migration|refactor|auth|billing|flaky|tuesday|files?|tests?|lines?|yes|write|written)\b/i

export interface LineFacts {
  /** The harness, as the person names it: `api`, or `api@laptop` when it is on another machine. */
  who: string
}

/**
 * Swap the example harness for the real one; null when anything else in the line would be invented.
 * The daemon's own words are lowercased (that is its voice); the facts put into them — a harness name,
 * a question, a recap, a path — are never touched, because a person may have to read them exactly.
 */
function voiced(line: string, who: string, strip: RegExp[] = []): { text: string; hasWho: boolean } | null {
  let text = line.toLowerCase()
  for (const pattern of strip) text = text.replace(pattern, ' ')
  const hasWho = WHO.test(text)
  text = text.replace(WHO, '\u0000')
  if (EXAMPLE_FACTS.test(text) || WHO.test(text)) return null
  return { text: text.replace('\u0000', who).replace(/\s+/g, ' ').trim(), hasWho }
}

function keys(actions: { key: string }[]): string {
  const has = (k: string): boolean => actions.some((a) => a.key === k)
  return has('y') && has('n') ? ' [y/n]' : has('y') ? ' [y]' : has('n') ? ' [n]' : ''
}

/** Tier 0 for a question: the daemon's need line when it can be told truthfully, then what is asked. */
export function needLine(daemonId: string, facts: LineFacts & { question: string; index?: number; count?: number },
  actions: { key: string }[]): string {
  // fzf counts what needs you ("1/1"): a real count here, so it is kept as a slot rather than refused.
  const roster = (rosterLine(daemonId, 'need') ?? '').replace(/\b\d+\/\d+\b/, '\u0001')
  // A template never recommends (that is a judgement), and its keys come from the real actions.
  const line = voiced(roster, facts.who, [/\[y\/n\]/gi, /i'd say \w+\./gi])
  const q = statusText(facts.question, 70)
  const base = line ? line.text.replace('\u0001', `${facts.index ?? 1}/${facts.count ?? 1}`) : `${facts.who} needs you.`
  const joined = (head: string): string => /[.!?]$/.test(head) ? `${head} ${q}` : `${head}: ${q}`
  const told = line && !line.hasWho ? joined(`${base} ${facts.who}`) : joined(base)
  return statusText(`${told}${keys(actions)}`, 140)
}

export function doneLine(daemonId: string, facts: LineFacts & { recap?: string | null }): string {
  const line = voiced(rosterLine(daemonId, 'done') ?? '', facts.who)
  const base = line?.hasWho ? line.text : `${facts.who} finished.`
  return statusText(facts.recap ? `${base} ${facts.recap}` : base, 140)
}

export function failLine(daemonId: string, facts: LineFacts & { reason: string }): string {
  const line = voiced(rosterLine(daemonId, 'fail') ?? '', facts.who)
  const base = line?.hasWho ? line.text : `${facts.who} failed.`
  return statusText(`${base} ${facts.reason}`, 140)
}

export interface BackFacts {
  done: number
  waiting: number
  /** How long the oldest open question has waited. */
  oldestWaitMs: number | null
  awayMs: number
  /** Harnesses that failed while you were away, by name. */
  failed: string[]
  /** Machines whose journal could not be read, by name. */
  unreachable: string[]
  /** Machines asked, this one included — ping's "0% loss". */
  machines: number
  /** Harnesses with anything to report, and how many are watched — fzf's "4/7 things changed". */
  changed: number
  total: number
}

/**
 * The line on return: "welcome back. 2 done, 1 waiting 40m. nothing on fire." A failure or an
 * unreachable machine replaces "nothing on fire"; a daemon whose line has no slot for a fact gets the
 * fact appended, so every daemon says the same things in its own words.
 */
export function backLine(daemonId: string, facts: BackFacts): string {
  const slots = { done: false, waiting: false, fire: false, loss: false }
  const waited = facts.waiting && facts.oldestWaitMs != null ? ` ${ago(facts.oldestWaitMs)}` : ''
  let line = (rosterLine(daemonId, 'back') ?? 'welcome back.').toLowerCase()
  line = line.replace(/\b\d+ done\b/, () => { slots.done = true; return `${facts.done} done` })
  line = line.replace(/\b\d+ replies\b/, () => { slots.done = true; return `${facts.done} ${facts.done === 1 ? 'reply' : 'replies'}` })
  line = line.replace(/\b\d+ waiting( \d+[smhd])?/, () => { slots.waiting = true; return `${facts.waiting} waiting${waited}` })
  line = line.replace(/\b\d+\/\d+ things changed/, () => { slots.done = slots.waiting = true; return `${facts.changed}/${facts.total} things changed` })
  line = line.replace(/\b\d+% loss/, () => {
    slots.loss = true
    return `${Math.round((facts.unreachable.length / Math.max(1, facts.machines)) * 100)}% loss`
  })
  line = line.replace(/(away|:earlier) \d+[smhd]/, (_m, word: string) => `${word} ${ago(facts.awayMs)}`)
  const fire = [
    ...facts.failed.map((name) => `${name} failed.`),
    ...(slots.loss ? [] : facts.unreachable.map((machine) => `${machine} unreachable.`)),
  ].join(' ')
  line = line.replace(/nothing on fire\./, () => { slots.fire = true; return fire || 'nothing on fire.' })
  const extra: string[] = []
  if (!slots.done && facts.done) extra.push(`${facts.done} done`)
  if (!slots.waiting && facts.waiting) extra.push(`${facts.waiting} waiting${waited}`)
  let out = extra.length ? `${line} ${extra.join(', ')}.` : line
  if (!slots.fire && fire) out = `${out} ${fire}`
  return statusText(out, 160)
}

export function ago(ms: number): string {
  const minutes = Math.round(ms / 60_000)
  if (minutes < 1) return `${Math.max(1, Math.round(ms / 1000))}s`
  if (minutes < 120) return `${minutes}m`
  const hours = Math.round(minutes / 60)
  return hours < 48 ? `${hours}h` : `${Math.round(hours / 24)}d`
}

// ── when it may speak ───────────────────────────────────────────────────────────────────────────────

export const DONE_COOLDOWN_MS = 20_000
export const SAY_WINDOW_MS = 60_000
export const SAY_WINDOW_MAX = 6
const SPOKEN_MAX = 500

export interface PairVoiceDeps {
  /** Loopback only: backendSocket.sendLocal. */
  sendLocal: (frame: Record<string, unknown>) => void
  now: () => number
}

interface Live { say: DaemonSay; at: number }

export class PairVoice {
  private readonly live = new Map<string, Live>()
  /** Every id ever said, bounded — a line is said once, whatever reconnects in between. */
  private readonly spoken = new Set<string>()
  private readonly recent: number[] = []
  private lastDone = -Infinity

  constructor(private readonly deps: PairVoiceDeps) {}

  /** Say it, unless it was said already or the voice is over its limits. True when it went out. */
  say(say: DaemonSay): boolean {
    const now = this.deps.now()
    this.sweep(now)
    if (this.spoken.has(say.id)) return false
    if (say.mood === 'done' && now - this.lastDone < DONE_COOLDOWN_MS) return false
    while (this.recent.length && now - this.recent[0] >= SAY_WINDOW_MS) this.recent.shift()
    // A question is the one thing worth saying over the limit: it is what the voice is for.
    if (this.recent.length >= SAY_WINDOW_MAX && say.mood !== 'need') return false
    this.recent.push(now)
    if (say.mood === 'done') this.lastDone = now
    this.remember(say.id)
    this.live.set(say.id, { say, at: now })
    this.deps.sendLocal({ type: 'daemon_say', payload: say })
    return true
  }

  /** Take back a line still showing — answered elsewhere, or the harness went away. */
  unsay(id: string, reason: string): boolean {
    if (!this.live.delete(id)) return false
    this.deps.sendLocal({ type: 'daemon_unsay', payload: { id, reason } })
    return true
  }

  /** Every live line about this harness (and question, when given). */
  unsayAbout(machineId: string, agentId: string, reason: string, requestId?: string): void {
    for (const [id, { say }] of [...this.live]) {
      if (say.about.machineId !== machineId || say.about.agentId !== agentId) continue
      if (requestId !== undefined && say.about.requestId !== requestId) continue
      this.unsay(id, reason)
    }
  }

  /** A line still showing, for `daemon_act`. Expired lines are gone. */
  get(id: string): DaemonSay | null {
    this.sweep(this.deps.now())
    return this.live.get(id)?.say ?? null
  }

  wasSaid(id: string): boolean { return this.spoken.has(id) }

  private sweep(now: number): void {
    for (const [id, { say, at }] of [...this.live]) if (now - at >= say.ttlMs) this.live.delete(id)
  }

  private remember(id: string): void {
    this.spoken.add(id)
    if (this.spoken.size > SPOKEN_MAX) this.spoken.delete(this.spoken.values().next().value as string)
  }
}

export type { DaemonMood }
