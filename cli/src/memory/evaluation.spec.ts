import { mkdtempSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { afterEach, beforeEach, expect, it, vi } from 'vitest'
import { evaluateExtractionCase, type ExtractionCase } from './evaluation.js'
import { nativeMemoryUsage } from './inferenceProcess.js'
import type { MemoryDraft } from './types.js'

let directory: string
beforeEach(() => { directory = mkdtempSync(join(tmpdir(), 'memory-evaluation-')) })
afterEach(() => { rmSync(directory, { recursive: true, force: true }) })
const fixture: ExtractionCase = {
  id: 'synthetic', projectId: null,
  sources: [{ role: 'user', text: 'For debugging I prefer a small failing test first.' }],
  expected: { records: { min: 1, max: 1 }, scope: 'personal', rationale: 'null', review: ['SECRET_EXPECTATION_NOT_IN_PROMPT'] },
  probes: [{ id: 'expected', query: 'failing test', projectIds: ['alpha'], conditions: { taskType: 'debugging' }, expected: 'recall' },
    { id: 'negative', query: 'failing test', projectIds: ['alpha'], conditions: {}, expected: 'abstain' }],
}
const draft: MemoryDraft = {
  kind: 'working_preference', facet: 'debugging', assertionType: 'stated_preference', scope: { profileId: 'synthetic-owner' },
  claim: 'For debugging prefer a small failing test first.', rationale: null, futureAction: 'Start with a small failing test.',
  applicability: { taskType: 'debugging' }, exceptions: [], retrievalCues: ['test'], evidenceClass: 'user_stated',
  evidence: [{ sourceEventId: 'synthetic-0', quote: fixture.sources[0].text, paths: ['/claim', '/futureAction', '/applicability'] }],
  conflictKey: 'debugging_order', validity: { validFrom: null, validUntil: null, recheckWhen: [] },
}
function provider(proposals: MemoryDraft[]) {
  return { target: async () => ({ state: 'ready' as const, key: 'synthetic-context' }), run: vi.fn(async () => JSON.stringify({ proposals })) }
}

it('runs real admission and scoped recall without leaking its rubric or probes to inference', async () => {
  const inference = provider([draft])
  const result = await evaluateExtractionCase({ fixture, directory, engine: 'claude', inference })
  expect(result.outcome).toEqual({ state: 'learned', learned: 1 })
  expect(result.checks.every(check => check.passed)).toBe(true)
  expect(result.semanticReview.status).toBe('pending')
  const prompt = (inference.run.mock.calls[0] as unknown as [string])[0]
  expect(prompt).toContain(fixture.sources[0].text)
  expect(prompt).not.toContain('SECRET_EXPECTATION_NOT_IN_PROMPT')
  expect(prompt).not.toContain('"id":"negative"')
})

it('exposes independently specified condition mismatch instead of copying generated keys into the probe', async () => {
  const result = await evaluateExtractionCase({ fixture, directory, engine: 'codex',
    inference: provider([{ ...draft, applicability: { task: 'debugging' } }]) })
  expect(result.outcome.state).toBe('learned')
  expect(result.checks.find(check => check.name === 'recall:expected')?.passed).toBe(false)
})

it('never scores invalid output as successful abstention', async () => {
  const empty: ExtractionCase = { ...fixture, expected: { ...fixture.expected, records: { min: 0, max: 0 }, scope: 'none' }, probes: [] }
  const inference = provider([])
  inference.run = vi.fn(async () => 'not json')
  const result = await evaluateExtractionCase({ fixture: empty, directory, engine: 'claude', inference })
  expect(result.outcome.state).toBe('failed')
  expect(result.records).toEqual([])
  expect(result.checks.find(check => check.name === 'completed_extraction')?.passed).toBe(false)
  expect(result.checks.find(check => check.name === 'record_count')?.passed).toBeNull()
  expect(result.semanticReview.status).toBe('not_reviewable')
})

it('marks recall probes inconclusive when the selected provider is unavailable', async () => {
  const result = await evaluateExtractionCase({ fixture, directory, engine: 'claude', inference: {
    target: async () => ({ state: 'ready', key: 'synthetic-context' }), run: async () => null,
  } })
  expect(result.probes.every(probe => probe.status === 'not_run' && probe.passed === null)).toBe(true)
  expect(result.checks.filter(check => check.name !== 'completed_extraction').every(check => check.passed === null)).toBe(true)
})

it.each([undefined, {}, { input_tokens: 1 }, { input_tokens: -1, output_tokens: 2 },
  { input_tokens: 1.1, output_tokens: 2 }, { input_tokens: 2, output_tokens: '3' }])('keeps unknown/invalid native usage unknown', value => {
  expect(nativeMemoryUsage(value)).toBeUndefined()
})
