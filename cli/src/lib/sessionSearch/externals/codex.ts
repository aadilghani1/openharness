/**
 * Codex: every local session is a rollout under `~/.codex/sessions/YYYY/MM/DD/` (or
 * `archived_sessions/`). Its first line (`session_meta`) says who wrote it: `source` `cli` (a
 * terminal) or `vscode` (the Codex app, whose `originator` is "Codex Desktop", and the editor
 * extensions). `exec` is a script and a `subagent` source is another thread's helper. Thread names
 * are in `session_index.jsonl`.
 *
 * Codex keeps no process record, but holds its rollout open while it runs, so `lsof` names the
 * owner; the rollout's last turn event says whether a turn is running.
 */

import { join } from 'node:path'

import { absoluteFolder, entries, fileStamp, firstLine, parseLine, readTail, readText, record, text } from './support.js'
import type { ExternalOrigin, ExternalProvider, ExternalSession, OwnerClaim, ProcessView, ScanContext } from './types.js'

/** How much of a rollout is read for its first line: `session_meta` carries the base instructions. */
const HEAD_BYTES = 1024 * 1024
const SESSION_ID = /^[A-Za-z0-9-]{8,80}$/
const ROLLOUT_ID = /-([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\.jsonl$/i

export interface CodexHead { sessionId: string; cwd: string; origin: ExternalOrigin }

/** A rollout's session, folder and source, from its first line. */
export async function readCodexHead(path: string): Promise<CodexHead | null> {
  const line = await firstLine(path, HEAD_BYTES)
  const row = record(line === null ? null : parseLine(line))
  const meta = record(row?.payload)
  if (row?.type !== 'session_meta' || !meta) return null
  const origin: ExternalOrigin | null = meta.source === 'cli' ? 'terminal'
    : meta.source === 'vscode' ? (meta.originator === 'Codex Desktop' ? 'codex-app' : 'editor')
    : null
  const cwd = absoluteFolder(meta.cwd)
  if (!origin || !SESSION_ID.test(text(meta.id)) || !cwd) return null
  return { sessionId: text(meta.id), cwd, origin }
}

/** Thread names: `session_index.jsonl`, one `{id, thread_name}` a line, the last one winning. */
export async function codexTitles(path: string, ctx: ScanContext): Promise<Map<string, string>> {
  const stamp = await fileStamp(path)
  if (!stamp) return new Map()
  return ctx.memo(`codex:titles:${path}`, stamp.stamp, async () => {
    const titles = new Map<string, string>()
    for (const line of (await readText(path)).split('\n')) {
      const row = record(parseLine(line))
      const name = text(row?.thread_name).trim()
      if (text(row?.id) && name) titles.set(text(row?.id), name)
    }
    return titles
  })
}

/** Every rollout file under a sessions folder (`YYYY/MM/DD/rollout-*.jsonl`), at any depth up to 4. */
export async function rollouts(dir: string): Promise<string[]> {
  const out: string[] = []
  const walk = async (at: string, depth: number): Promise<void> => {
    for (const entry of await entries(at)) {
      const path = join(at, entry.name)
      if (entry.isDirectory() && depth < 4) await walk(path, depth + 1)
      // A file or a link to one; the scan's stat drops a broken link.
      else if (!entry.isDirectory() && entry.name.startsWith('rollout-') && entry.name.endsWith('.jsonl')) out.push(path)
    }
  }
  await walk(dir, 0)
  return out
}

const TURN_MARK = /"(task_started|task_complete|turn_aborted)"/

/**
 * Whether a rollout's last turn is still running: the last `task_started`, `task_complete` or
 * `turn_aborted` event near its end says. What was said can name the events; only events count.
 * A file that cannot say counts as busy.
 */
export async function codexTurnOpen(path: string): Promise<boolean> {
  for (const bytes of [256 * 1024, 4 * 1024 * 1024]) {
    const lines = (await readTail(path, bytes)).split('\n')
    for (let i = lines.length - 1; i > 0; i--) {
      const line = lines[i]
      if (!line.includes('"event_msg"') || !TURN_MARK.test(line)) continue
      const kind = record(record(parseLine(line))?.payload)?.type
      if (kind === 'task_started') return true
      if (kind === 'task_complete' || kind === 'turn_aborted') return false
    }
  }
  return true
}

export function codexProvider(options: { home: string }): ExternalProvider {
  return {
    engine: 'codex',
    async scan(ctx: ScanContext): Promise<ExternalSession[]> {
      const titles = await codexTitles(join(options.home, 'session_index.jsonl'), ctx)
      const found: ExternalSession[] = []
      for (const path of [
        ...await rollouts(join(options.home, 'sessions')),
        ...await rollouts(join(options.home, 'archived_sessions')),
      ]) {
        const stamp = await fileStamp(path)
        if (!stamp) continue
        // A rollout's first line never changes: read once, however the file grows.
        const head = await ctx.memo(`codex:${path}`, 'head', () => readCodexHead(path))
        await ctx.pace()
        if (!head || ctx.excluded(head.cwd)) continue
        found.push({ ...head, engine: 'codex', title: titles.get(head.sessionId) ?? '', mtime: stamp.mtime, transcriptPath: path })
      }
      return found
    },
    async owners(view: ProcessView): Promise<OwnerClaim[]> {
      const claims: OwnerClaim[] = []
      for (const [pid, files] of await view.openFilesOf(['codex', 'Codex'])) {
        for (const path of files) {
          const id = ROLLOUT_ID.exec(path)?.[1]
          if (id && path.includes('rollout-')) claims.push({ sessionId: id, pid, record: path })
        }
      }
      return claims
    },
    busy: (owner) => codexTurnOpen(owner.record),
  }
}
