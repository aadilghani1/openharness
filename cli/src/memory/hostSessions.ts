import { isAbsolute, parse, resolve } from 'node:path'
import type { MemoryHostSession } from './runtime.js'

interface RegisteredMemorySession {
  agentId: string; engine: string; sessionId: string; cwd: string | null; transcriptPath: string | null
  dsh?: string | null; forkedFrom?: unknown; registeredAt: number
}
// These bundled DSHs have explicit software-development workflows. A package's arbitrary category
// string, viewer, or use of a coding CLI cannot opt a general-domain DSH into personal coding memory.
const CODING_DSHS = new Set(['autonomous/web-studio', 'autonomous/firmware-studio'])

/** A short grace period finishes native records after a process exits, without scanning archives. */
export class MemorySessionRoster {
  private readonly recent = new Map<string, { session: MemoryHostSession; seenAt: number }>()
  constructor(private readonly home: string, private readonly now: () => number = Date.now) {}

  refresh(live: RegisteredMemorySession[], busy: (sessionId: string) => boolean, subagent: (sessionId: string) => boolean): MemoryHostSession[] {
    const observed = new Set(live.map(session => session.agentId))
    const current = new Set<string>()
    for (const session of live) {
      if (!['claude', 'codex'].includes(session.engine) || !session.sessionId || !session.cwd || !session.transcriptPath
        || !isAbsolute(session.cwd) || !isAbsolute(session.transcriptPath) || subagent(session.sessionId)
        || (session.dsh && !CODING_DSHS.has(session.dsh)) || resolve(session.cwd) === resolve(this.home)
        || resolve(session.cwd) === parse(resolve(session.cwd)).root) continue
      current.add(session.agentId)
      this.recent.set(session.agentId, { seenAt: this.now(), session: { agentId: session.agentId,
        engine: session.engine as 'claude' | 'codex', sessionId: session.sessionId, workspace: session.cwd,
        transcriptPath: session.transcriptPath, coding: true, busy: busy(session.sessionId),
        ...(session.forkedFrom ? { liveFrom: session.registeredAt } : {}) } })
    }
    for (const [agentId, row] of this.recent) {
      if ((observed.has(agentId) && !current.has(agentId)) || this.now() - row.seenAt > 120_000) this.recent.delete(agentId)
      else if (!current.has(agentId)) row.session = { ...row.session, busy: false }
    }
    while (this.recent.size > 128) this.recent.delete(this.recent.keys().next().value!)
    return [...this.recent.values()].map(row => ({ ...row.session }))
  }
}
