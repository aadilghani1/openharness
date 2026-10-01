/** Some Codex goal interruptions never write task_complete/turn_aborted to the
 * rollout. An open transcript is then only historical evidence of work. Use
 * the live stopped-goal footer to repair that state, without touching Codex. */
import { stripVTControlCharacters } from 'node:util'
import type { CodexNormalizer } from '../engines/codex/normalizer.js'
import { inspectRuntimePane } from './runtimeProfileController.js'

/** Read only the UI below the current empty composer, never output/history.
 * An empty composer alone says nothing: Codex accepts drafts while working. */
export function codexStoppedGoal(screen: string | null): boolean {
  if (!screen || !inspectRuntimePane('codex', screen).idle) return false
  const lines = stripVTControlCharacters(screen).split(/\r?\n/)
  const prompt = lines.findLastIndex(line => /^\s*›(?:\s|$)/u.test(line))
  if (prompt < 0) return false
  // A live turn can still display the previous goal state during a redraw.
  if (lines.slice(-16).some(line => /\besc to interrupt\b/i.test(line))) return false
  const footer = lines.slice(prompt + 1).filter(line => line.trim())
  return footer.length <= 4
    && footer.some(line => /\bGoal (?:stalled|paused) \(\/goal resume\)\s*$/.test(line))
    && footer.some(line => /\? for shortcuts\b/.test(line))
}

export interface CodexTurnSnapshot {
  normalizer: CodexNormalizer
  /** Includes agent and terminal identity, so a replacement cannot reuse a read. */
  runtimeKey: string
}

export interface CodexTurnRecoveryDeps {
  snapshot(sessionId: string): CodexTurnSnapshot | undefined
  drain(sessionId: string): Promise<void>
  capture(sessionId: string): Promise<string | null>
  recovered(sessionId: string): void
  now?: () => number
}

interface Check extends CodexTurnSnapshot {
  revision: number
  quietSince: number
  checkedAt: number
  pending: boolean
  confirmed: boolean
}

// Quietness only schedules inspection. Two explicit stopped footers, at least
// five seconds apart, are required; time alone never ends a turn.
const QUIET_MS = 30_000
const CHECK_INTERVAL_MS = 5_000

export class CodexTurnRecovery {
  private readonly checks = new Map<string, Check>()
  private readonly now: () => number
  constructor(private readonly deps: CodexTurnRecoveryDeps) { this.now = deps.now ?? Date.now }

  forget(sessionId: string): void { this.checks.delete(sessionId) }

  async check(sessionId: string): Promise<void> {
    const snapshot = this.deps.snapshot(sessionId)
    if (!snapshot?.normalizer.turnOpen) { this.forget(sessionId); return }
    let check = this.checks.get(sessionId)
    if (!check || check.normalizer !== snapshot.normalizer || check.runtimeKey !== snapshot.runtimeKey
      || check.revision !== snapshot.normalizer.activityRevision) {
      check = { ...snapshot, revision: snapshot.normalizer.activityRevision, quietSince: this.now(),
        checkedAt: -Infinity, pending: false, confirmed: false }
      this.checks.set(sessionId, check)
    }
    if (check.pending || this.now() - check.quietSince < QUIET_MS
      || this.now() - check.checkedAt < CHECK_INTERVAL_MS) return
    check.pending = true
    check.checkedAt = this.now()
    const current = () => {
      const latest = this.deps.snapshot(sessionId)
      return this.checks.get(sessionId) === check && latest?.normalizer === check.normalizer
        && latest.runtimeKey === check.runtimeKey && check.normalizer.turnOpen
        && check.normalizer.activityRevision === check.revision
    }
    try {
      await this.deps.drain(sessionId)
      if (!current()) return
      const stopped = codexStoppedGoal(await this.deps.capture(sessionId))
      await this.deps.drain(sessionId)
      if (!current()) return
      if (!stopped) { check.confirmed = false; return }
      if (!check.confirmed) { check.confirmed = true; return }
      check.normalizer.closeTurn()
      this.forget(sessionId)
      this.deps.recovered(sessionId)
    } catch {
      check.confirmed = false // Unavailable terminals are unknown, never idle.
    } finally { check.pending = false }
  }
}
