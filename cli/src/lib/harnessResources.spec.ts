import { describe, expect, it, vi } from 'vitest'
import { createHarnessResourcesReader, parseResourceProcesses, type ResourceProcess } from './harnessResources.js'

const start = 'Wed Sep 30 10:00:00 2026'
const row = (pid: number, parent = 1, memoryBytes = 100, cpuMs = 10): ResourceProcess => ({ pid, parent, memoryBytes, cpuMs, start })
const agent = (agentId: string, pid: number) => ({ agentId, processIdentity: { pid, startMarker: start, executable: 'engine' } })

describe('Harness Monitor readings', () => {
  it('parses macOS and Linux counters, retaining start identities and valid zero', () => {
    expect(parseResourceProcesses(`1 0 12 0:01.20 Wed Sep 30 10:00:00 2026
2 1 0 02:03:04 Wed Sep 30 10:00:00 2026
3 1 200 1-02:03:04 Wed Sep 30 10:00:00 2026
not a process`)).toEqual([
      { ...row(1, 0, 12288, 1200) },
      { ...row(2, 1, 0, 7384000) },
      { ...row(3, 1, 204800, 93784000) },
    ])
  })

  it('counts each process once across helpers, nested agents and unrelated applications', async () => {
    const sample = vi.fn(async () => [row(10), row(11, 10), row(12, 11), row(13, 12), row(90)])
    const read = createHarnessResourcesReader(() => [agent('parent', 10), agent('child', 12)], { sample, now: () => 10_000 })
    expect(sample).not.toHaveBeenCalled()
    expect((await read()).agents).toEqual([
      { agentId: 'parent', memoryBytes: 200, processCount: 2, cpuPercent: null },
      { agentId: 'child', memoryBytes: 200, processCount: 2, cpuPercent: null },
    ])
  })

  it('reports interval CPU, including more than one core, with no second sample on demand', async () => {
    let now = 10_000, cpuMs = 100
    const read = createHarnessResourcesReader(() => [agent('a', 10)], {
      sample: async () => [row(10, 1, 0, cpuMs)], now: () => now,
    })
    expect((await read()).agents[0].cpuPercent).toBeNull()
    now += 5000; cpuMs += 12_500
    expect((await read()).agents[0]).toMatchObject({ cpuPercent: 250, memoryBytes: 0 })
    now += 5000
    expect((await read()).agents[0].cpuPercent).toBe(0)
    now += 61_000
    expect((await read()).agents[0].cpuPercent).toBeNull()
  })

  it('never attributes reused PIDs, duplicate roots or missing identities to an agent', async () => {
    const read = createHarnessResourcesReader(() => [
      agent('old', 10), agent('duplicate1', 20), agent('duplicate2', 20), { agentId: 'missing' },
    ], { sample: async () => [{ ...row(10), start: 'new process' }, row(20)], now: () => 10_000 })
    for (const result of (await read()).agents) {
      expect(result).toMatchObject({ memoryBytes: null, cpuPercent: null, processCount: null })
    }
  })

  it('coalesces concurrent clients, expires cached data and retries failed reads', async () => {
    let now = 10_000
    let finish!: (rows: ResourceProcess[]) => void
    const sample = vi.fn(() => new Promise<ResourceProcess[]>(resolve => { finish = resolve }))
    const read = createHarnessResourcesReader(() => [agent('a', 10)], { sample, now: () => now })
    const first = read()
    expect(read()).toBe(first)
    finish([row(10)])
    const value = await first
    now += 2499
    expect(await read()).toBe(value)
    expect(sample).toHaveBeenCalledTimes(1)
    now++
    sample.mockRejectedValueOnce(new Error('denied'))
    await expect(read()).rejects.toThrow('denied')
    sample.mockResolvedValueOnce([row(10)])
    expect((await read()).agents[0].memoryBytes).toBe(100)
  })

  it('does not follow corrupt parent cycles indefinitely or reuse prior samples after exits', async () => {
    let now = 10_000
    const sample = vi.fn(async () => [row(10, 11), row(11, 10)])
    const read = createHarnessResourcesReader(() => [agent('a', 10)], { sample, now: () => now })
    expect((await read()).agents[0].memoryBytes).toBe(200)
    now += 3000; sample.mockResolvedValueOnce([])
    expect((await read()).agents[0].memoryBytes).toBeNull()
  })
})

it('counts a detached shared server once, without assigning its whole RAM to every session', async () => {
  const agents = [agent('a', 10), agent('b', 20)]
  let time = 10_000
  const shared = vi.fn(async () => [
    { pid: 50, start, agentIds: ['a', 'b'] },
    { pid: 50, start, agentIds: ['a', 'b'] },
    { pid: 60, start: 'recycled', agentIds: ['a'] },
    { pid: 11, start, agentIds: ['a'] },
  ])
  const read = createHarnessResourcesReader(() => agents, {
    sample: async () => [row(10), row(11, 10), row(20), row(50), row(51, 50), row(60)],
    now: () => time,
  }, shared)
  const first = await read()
  expect(first.agents.map(row => row.memoryBytes)).toEqual([200, 100])
  expect(first.shared).toEqual([{ kind: 'codex', agentIds: ['a', 'b'], memoryBytes: 200, processCount: 2, cpuPercent: null }])
  time += 3000
  expect((await read()).shared![0].cpuPercent).toBe(0)
})
