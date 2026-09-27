/**
 * More of what the person has said yes to (pair/gate.ts): the summary a rules request shows, repeated and
 * replaced requests, a lowering from a confirmed level, a file confirmed before coming back while another
 * waits, and a confirmation store that cannot be written.
 */
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { configSummary, hashConfig, PairGate, type GateEvent } from './gate.js'
import { EMPTY_PAIR_CONFIG, parsePairConfig, type PairConfig } from './rules.js'

let dir: string
beforeEach(() => { dir = mkdtempSync(join(tmpdir(), 'pair-gate-more-')) })
afterEach(() => { vi.restoreAllMocks(); rmSync(dir, { recursive: true, force: true }) })

function gate(file: string | null = join(dir, 'confirmed.json'), initial: 'watch' | 'act-within-rules' = 'watch') {
  const events: GateEvent[] = []
  let n = 0
  const g = new PairGate({ file, onEvent: (e) => events.push(e), newNonce: () => `n${++n}`, now: () => 5 }, initial)
  return { g, events }
}

const RULE = { question: 'npm test', choice: 'Yes' }
const text = (value: object) => JSON.stringify(value)
const load = (value: object) => ({ config: parsePairConfig(text(value), '/home/me'), text: text(value) })

describe('configSummary', () => {
  it('says what a pair.jsonc turns on, in a few words', () => {
    expect(configSummary(EMPTY_PAIR_CONFIG)).toBe('0 rules, model off')
    const one: PairConfig = { ...parsePairConfig(text({ rules: [RULE], model: true }), '/h') }
    expect(configSummary(one)).toBe('1 rule, model on')
    const learn = parsePairConfig(text({ learn: { borrow: true, export: ['agents', 'claude'], agentsMd: ['/a', '/b'] } }), '/h')
    expect(configSummary(learn)).toBe('0 rules, model off, learn borrow + export agents+claude + AGENTS.md in 2 projects')
    expect(configSummary(parsePairConfig(text({ learn: { agentsMd: ['/a'] } }), '/h'))).toBe('0 rules, model off, learn AGENTS.md in 1 project')
    expect(configSummary({ ...EMPTY_PAIR_CONFIG, learn: undefined as unknown as PairConfig['learn'] })).toBe('0 rules, model off')
  })
})

describe('autonomy', () => {
  it('asks once for a level that is already waiting, and not again', () => {
    const { g, events } = gate()
    g.setRequested('act-on-key')
    g.setRequested('act-on-key')
    expect(events.filter((e) => e.type === 'asked')).toHaveLength(1)
    expect(g.requests()).toEqual([expect.objectContaining({ kind: 'autonomy', level: 'act-on-key', nonce: 'n1', at: 5 })])
    expect(g.requests()[0]).not.toHaveProperty('config')
  })

  it('a request past suggest shows exactly what a yes turns on, and the floor', () => {
    const { g, events } = gate()
    g.setRequested('act-within-rules')
    const asked = events[0] as Extract<GateEvent, { type: 'asked' }>
    expect(asked.request.line).toBe('[y/n] let your daemon act at act-within-rules? it stays at watch until you say yes')
    expect(asked.request.detail).toContain('autonomy watch -> act-within-rules')
    expect(asked.request.detail).toContain('pair.jsonc rules')
    expect(asked.request.detail).toMatch(/never approved/)
    expect(asked.request.actions.map((a) => a.key)).toEqual(['y', 'n'])
  })

  it('reading the same level again announces nothing', () => {
    const { g, events } = gate()
    g.setRequested('suggest')
    g.setRequested('suggest')
    g.setRequested('watch')
    g.setRequested('watch')
    expect(events.map((e) => e.type === 'changed' ? e.line.split(':')[0] : e.type)).toEqual(['autonomy watch -> suggest', 'autonomy suggest -> watch'])
  })

  it('lowering from a confirmed act-within-rules to act-on-key keeps act-on-key confirmed, not the higher level', () => {
    const file = join(dir, 'confirmed.json')
    const { g } = gate(file)
    g.setRequested('act-within-rules')
    g.confirm('autonomy', 'n1', true)
    expect(JSON.parse(readFileSync(file, 'utf8'))).toMatchObject({ autonomy: 'act-within-rules' })
    g.setRequested('act-on-key')
    expect(g.autonomy()).toBe('act-on-key')
    expect(JSON.parse(readFileSync(file, 'utf8'))).toMatchObject({ autonomy: 'act-on-key' })
    // Back up to act-within-rules: asks again.
    g.setRequested('act-within-rules')
    expect(g.autonomy()).toBe('act-on-key')
    expect(g.requests()).toHaveLength(1)
    // A hold-down (no consent yet) is not the person lowering it: what they confirmed stands.
    g.setRequested('watch', { keepConfirmed: true })
    expect(JSON.parse(readFileSync(file, 'utf8'))).toMatchObject({ autonomy: 'act-on-key' })
    g.setRequested('act-on-key')
    expect(g.autonomy()).toBe('act-on-key')
  })

  it('a daemon started at a level applies it at once, and a nonce is random by default', () => {
    const events: GateEvent[] = []
    const g = new PairGate({ file: null, onEvent: (e) => events.push(e) }, 'act-within-rules')
    expect(g.autonomy()).toBe('act-within-rules')
    g.setRequested('watch')
    g.setRequested('act-on-key')
    const request = g.requests()[0]!
    expect(request.nonce).toMatch(/^[A-Za-z0-9_-]{12}$/)
    expect(request.at).toBeGreaterThan(0)
    expect(g.confirm('autonomy', 'guess', true)).toMatchObject({ ok: false, error: 'STALE_CONFIRM' })
  })
})

describe('the answer', () => {
  it('names only the two kinds, and only the nonce that is waiting', () => {
    const { g } = gate()
    expect(g.confirm('everything', 'n1', true)).toEqual({ ok: false, error: 'UNKNOWN_KIND' })
    expect(g.confirm('rules', 'n1', true)).toMatchObject({ ok: false, error: 'STALE_CONFIRM' })
    g.setRequested('act-on-key')
    expect(g.confirm('rules', 'n1', true)).toMatchObject({ ok: false, error: 'STALE_CONFIRM' })
    expect(g.confirm('autonomy', 'n1', true)).toEqual({ ok: true, kind: 'autonomy' })
    expect(g.confirm('autonomy', 'n1', true)).toMatchObject({ ok: false, error: 'STALE_CONFIRM' })
  })
})

describe('pair.jsonc', () => {
  it('a second file that asks for more replaces the first request', () => {
    const { g, events } = gate()
    g.rules(load({ rules: [RULE] }))
    g.rules(load({ model: true }))
    expect(events.map((e) => e.type)).toEqual(['asked', 'dropped', 'asked'])
    expect((events[1] as Extract<GateEvent, { type: 'dropped' }>).reason).toBe('replaced')
    expect(g.requests()).toEqual([expect.objectContaining({ kind: 'rules', nonce: 'n2' })])
    expect(g.requests()[0]!.line).toContain('until you say yes, none of it')
  })

  it('while a new file waits, the one confirmed before applies — and says so', () => {
    const { g } = gate()
    const first = load({ rules: [RULE] })
    g.rules(first)
    g.confirm('rules', 'n1', true)
    expect(g.rules(load({ rules: [RULE, RULE] }))).toBe(first.config)
    expect(g.requests()[0]!.line).toContain('until you say yes, what you confirmed before')
  })

  it('the confirmed file coming back while another waits drops the request and keeps the rules without a second announcement', () => {
    const { g, events } = gate()
    const confirmed = load({ rules: [RULE] })
    g.rules(confirmed)
    g.confirm('rules', 'n1', true)
    events.length = 0
    g.rules(load({ model: true }))
    expect(g.rules({ config: parsePairConfig(confirmed.text, '/home/me'), text: confirmed.text })).toEqual(confirmed.config)
    expect(events.map((e) => e.type)).toEqual(['asked', 'dropped'])
    expect(g.requests()).toEqual([])
  })

  it('a file with no text but rules in its config still asks, showing no text', () => {
    const { g, events } = gate()
    const config = parsePairConfig(text({ rules: [RULE] }), '/h')
    g.rules({ config, text: null })
    const asked = events[0] as Extract<GateEvent, { type: 'asked' }>
    expect(asked.request.detail).toBe('pair.jsonc (1 rule, model off):\n')
  })

  it('a hash kept in the store must look like one to count', () => {
    const file = join(dir, 'confirmed.json')
    writeFileSync(file, JSON.stringify({ autonomy: 'root', rules: 'not-a-hash' }))
    const { g, events } = gate(file)
    g.setRequested('act-on-key')
    expect(events[0]!.type).toBe('asked')
    g.rules(load({ rules: [RULE] }))
    expect(events[1]!.type).toBe('asked')
    writeFileSync(file, JSON.stringify({ rules: hashConfig(text({ rules: [RULE] })) }))
    const again = gate(file)
    again.g.rules(load({ rules: [RULE] }))
    expect(again.events.map((e) => e.type)).toEqual(['changed'])
  })
})

describe('the confirmation store', () => {
  it('is created with its folder, and a store that cannot be written warns and keeps the level', () => {
    const nested = join(dir, 'a', 'b', 'confirmed.json')
    const { g } = gate(nested)
    g.setRequested('act-on-key')
    g.confirm('autonomy', 'n1', true)
    expect(JSON.parse(readFileSync(nested, 'utf8'))).toEqual({ autonomy: 'act-on-key', rules: null })

    const blocker = join(dir, 'file')
    writeFileSync(blocker, 'x')
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => {})
    const broken = gate(join(blocker, 'confirmed.json'))
    broken.g.setRequested('act-on-key')
    expect(broken.g.confirm('autonomy', 'n1', true)).toEqual({ ok: true, kind: 'autonomy' })
    expect(broken.g.autonomy()).toBe('act-on-key')
    expect(warn).toHaveBeenCalledWith(expect.stringMatching(/^\[pair\] could not keep what was confirmed: /))
  })
})
