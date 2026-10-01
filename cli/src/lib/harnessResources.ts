import { execFile } from 'node:child_process'
import { promisify } from 'node:util'
import type { ProcessIdentity } from './terminalTypes.js'

const exec = promisify(execFile)
type Agent = { agentId: string; processIdentity?: ProcessIdentity | null }
export interface ResourceProcess {
  pid: number
  parent: number
  memoryBytes: number
  cpuMs: number
  start: string
}
export interface HarnessResource {
  agentId: string
  memoryBytes: number | null
  cpuPercent: number | null
  processCount: number | null
}
export interface HarnessResources {
  sampledAt: string
  agents: HarnessResource[]
}

// Reuses Harness Monitor's single process-table / subtree approach. The daemon
// already knows the owning PID, so no tmux probe, executable-name guessing or
// transcript scan is needed. Cumulative CPU counters give interval use on both
// macOS and Linux; ps %cpu would be a lifetime average on Linux.
export function parseResourceProcesses(text: string): ResourceProcess[] {
  const rows: ResourceProcess[] = []
  for (const line of text.split('\n')) {
    const match = /^\s*(\d+)\s+(\d+)\s+(\d+)\s+(?:(\d+)-)?(?:(\d+):)?(\d+):(\d+(?:\.\d+)?)\s+(\S+\s+\S+\s+\d+\s+\d{2}:\d{2}:\d{2}\s+\d{4})\s*$/.exec(line)
    if (!match) continue
    const cpuMs = (((Number(match[4] ?? 0) * 24 + Number(match[5] ?? 0)) * 60
      + Number(match[6])) * 60 + Number(match[7])) * 1000
    const memoryBytes = Number(match[3]) * 1024
    if (!Number.isFinite(cpuMs) || !Number.isSafeInteger(memoryBytes)) continue
    rows.push({ pid: Number(match[1]), parent: Number(match[2]), memoryBytes, cpuMs,
      start: match[8].replace(/\s+/g, ' ') })
  }
  return rows
}

async function sampleProcesses(): Promise<ResourceProcess[]> {
  const { stdout } = await exec('ps', ['-axo', 'pid=,ppid=,rss=,time=,lstart='], {
    encoding: 'utf8', timeout: 2000, maxBuffer: 8 * 1024 * 1024,
    env: { ...process.env, LC_ALL: 'C' },
  })
  const rows = parseResourceProcesses(stdout)
  if (!rows.length) throw new Error('Process readings unavailable')
  return rows
}

/** No timer, no retained history and no work until an owning client asks. */
export function createHarnessResourcesReader(agents: () => readonly Agent[], deps = {
  sample: sampleProcesses, now: Date.now,
}) {
  let previous: { at: number; rows: Map<number, ResourceProcess> } | undefined
  let cached: { at: number; value: HarnessResources } | undefined
  let pending: Promise<HarnessResources> | undefined
  async function read(): Promise<HarnessResources> {
    const snapshot = await deps.sample()
    const at = deps.now()
    const byPid = new Map(snapshot.map(row => [row.pid, row]))
    const children = new Map<number, number[]>()
    for (const row of snapshot) {
      const list = children.get(row.parent) ?? []
      list.push(row.pid)
      children.set(row.parent, list)
    }
    const current = agents()
    const owners = new Map<number, string[]>()
    for (const agent of current) {
      const identity = agent.processIdentity
      if (!identity || byPid.get(identity.pid)?.start !== identity.startMarker.replace(/\s+/g, ' ')) continue
      owners.set(identity.pid, [...owners.get(identity.pid) ?? [], agent.agentId])
    }
    const elapsed = previous ? at - previous.at : 0
    const readings = current.map(agent => {
      const unknown: HarnessResource = { agentId: agent.agentId, memoryBytes: null, cpuPercent: null, processCount: null }
      const root = agent.processIdentity?.pid
      // Refuse stale PIDs and duplicate ownership rather than double-counting.
      if (!root || owners.get(root)?.length !== 1 || owners.get(root)?.[0] !== agent.agentId) return unknown
      let memoryBytes = 0, cpuMs = 0, processCount = 0
      let cpuKnown = elapsed > 0 && elapsed <= 60_000
      const queue = [root], seen = new Set<number>()
      while (queue.length) {
        const pid = queue.pop()!
        if (seen.has(pid) || (pid !== root && owners.has(pid))) continue
        seen.add(pid)
        const row = byPid.get(pid)
        if (!row) continue
        memoryBytes += row.memoryBytes
        processCount++
        const before = previous?.rows.get(pid)
        if (before?.start === row.start && row.cpuMs >= before.cpuMs) cpuMs += row.cpuMs - before.cpuMs
        else cpuKnown = false
        queue.push(...children.get(pid) ?? [])
      }
      return { agentId: agent.agentId, memoryBytes, processCount,
        cpuPercent: cpuKnown ? Math.round(cpuMs / elapsed * 1000) / 10 : null }
    })
    previous = { at, rows: byPid }
    const value = { sampledAt: new Date(at).toISOString(), agents: readings }
    cached = { at, value }
    return value
  }
  return (): Promise<HarnessResources> => {
    if (pending) return pending
    if (cached && deps.now() - cached.at >= 0 && deps.now() - cached.at < 2500) return Promise.resolve(cached.value)
    pending = read().finally(() => { pending = undefined })
    return pending
  }
}
