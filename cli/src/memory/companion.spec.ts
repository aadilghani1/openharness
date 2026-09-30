import { expect, it, vi } from 'vitest'
import { companionMemoryInference } from './companion.js'

it('waits for a certified selected Codex runtime and preserves foreground priority', async () => {
  const intelligence = { extractionStatus: async () => ({ state: 'ready' as const, engine: 'codex', contextKey: 'selected' }),
    extract: vi.fn(async () => '{"proposals":[]}') }
  const capability = vi.fn(async () => ({ supported: false, version: 'untested' }))
  let busy = true
  const inference = companionMemoryInference(intelligence, () => busy, capability)
  expect(await inference.target()).toEqual({ state: 'unsupported' })
  expect(intelligence.extract).not.toHaveBeenCalled()
  capability.mockResolvedValue({ supported: true, version: '0.159.0' })
  expect(await inference.target()).toEqual({ state: 'ready', key: 'selected', foregroundBusy: true })
  busy = false
  expect((await inference.target()).foregroundBusy).toBe(false)
  const options = { signal: new AbortController().signal, timeoutMs: 1000 }
  expect(await inference.run('evidence', options)).toBe('{"proposals":[]}')
  expect(intelligence.extract).toHaveBeenCalledExactlyOnceWith('evidence', options)
})
