/**
 * Claude Code: `~/.claude/projects/<folder>/<id>.jsonl`. A transcript's first lines say who wrote it:
 * `entrypoint` `cli` (a terminal) or `claude-desktop` (the Claude app). `sdk-cli` is a program driving
 * Claude (Harness's own summaries among them), and a sub-agent's file lives in a folder of its own.
 *
 * A running Claude Code keeps `~/.claude/sessions/<pid>.json` naming its session and saying `idle`
 * between turns: the owner and its state, exactly.
 */

import { join } from 'node:path'

import { absoluteFolder, entries, fileStamp, readHead, readJson, record, text } from './support.js'
import { type ExternalOrigin, type ExternalProvider, type ExternalSession, type OwnerClaim, type ProcessView, type ScanContext, UNSETTLED } from './types.js'

/** How much of a transcript is read to classify it: the first lines may carry no entrypoint. */
const HEAD_BYTES = 256 * 1024
const SESSION_ID = /^[A-Za-z0-9-]{8,80}$/

export interface ClaudeHead { sessionId: string; cwd: string; origin: ExternalOrigin }

/**
 * A transcript's session, folder and entrypoint, from the first line that has them. UNSETTLED when no
 * such line is there yet in a file shorter than what is read: Claude may still be writing it.
 */
export async function readClaudeHead(path: string): Promise<ClaudeHead | null | typeof UNSETTLED> {
  const head = await readHead(path, HEAD_BYTES)
  for (const line of head.split('\n')) {
    if (!line.includes('"entrypoint"')) continue
    let row: Record<string, unknown> | null
    try { row = record(JSON.parse(line)) } catch { continue }
    if (!row) continue
    if (row.isSidechain === true) return null
    const origin: ExternalOrigin | null = row.entrypoint === 'cli' ? 'terminal' : row.entrypoint === 'claude-desktop' ? 'claude-app' : null
    const cwd = absoluteFolder(row.cwd)
    if (!origin || !SESSION_ID.test(text(row.sessionId)) || !cwd) return null
    return { sessionId: text(row.sessionId), cwd, origin }
  }
  return Buffer.byteLength(head) < HEAD_BYTES ? UNSETTLED : null
}

export function claudeProvider(options: { projectsDir: string; home: string }): ExternalProvider {
  return {
    engine: 'claude',
    async scan(ctx: ScanContext): Promise<ExternalSession[]> {
      const found: ExternalSession[] = []
      for (const project of await entries(options.projectsDir)) {
        if (!project.isDirectory()) continue
        const folder = join(options.projectsDir, project.name)
        // Only the project's own files: a sub-agent's are in a folder beneath it.
        for (const file of await entries(folder)) {
          if (!file.name.endsWith('.jsonl')) continue
          const path = join(folder, file.name)
          // A file, or a link to one; not a folder, not a broken link.
          const stamp = await fileStamp(path)
          if (!stamp) continue
          // A transcript's first lines never change: its head is read once, however it grows.
          const head = await ctx.head(`claude:${path}`, stamp.stamp, () => readClaudeHead(path))
          await ctx.pace()
          if (!head || ctx.excluded(head.cwd)) continue
          found.push({ ...head, engine: 'claude', title: '', mtime: stamp.mtime, transcriptPath: path })
        }
      }
      return found
    },
    async owners(view: ProcessView): Promise<OwnerClaim[]> {
      const dir = join(options.home, 'sessions')
      const claims: OwnerClaim[] = []
      for (const file of await entries(dir)) {
        if (!file.isFile() || !file.name.endsWith('.json')) continue
        const path = join(dir, file.name)
        const row = record(await readJson(path))
        const pid = row?.pid
        if (typeof pid !== 'number' || !text(row?.sessionId) || !view.alive(pid)) continue
        claims.push({ sessionId: text(row?.sessionId), pid, record: path })
      }
      return claims
    },
    async busy(owner): Promise<boolean> {
      const row = record(await readJson(owner.record))
      // No record: the process ended with it, so it is not mid-turn.
      return row ? row.status !== 'idle' : false
    },
  }
}
