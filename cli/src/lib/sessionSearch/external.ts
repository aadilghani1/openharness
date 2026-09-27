/**
 * Conversations on this machine that Harness did not start: Claude Code and Codex sessions run in a
 * terminal or in their own desktop apps. Found where each engine keeps them, so Cmd-P can find them
 * and open one in Harness (`agent_create` with `resumeSessionId`).
 *
 * Only what a person started, told apart by what each engine records at the top of the file:
 *  - Claude Code's `entrypoint`: `cli` (a terminal) or `claude-desktop` (the Claude app). `sdk-cli`
 *    is a program driving Claude — Harness's own summaries among them — and a sub-agent's file lives
 *    in a folder of its own.
 *  - Codex's `source`: `cli` (a terminal) or `vscode` (the Codex app, which says so in `originator`,
 *    and the editor extensions). `exec` is a script and a `subagent` source is another thread's helper.
 *
 * A file's first lines never change, so each file is read once, however often it is scanned.
 */

import { execFile } from 'node:child_process'
import { open, readdir, readFile, stat } from 'node:fs/promises'
import { join } from 'node:path'

export type ExternalOrigin = 'terminal' | 'claude-app' | 'codex-app' | 'editor'
export type ExternalEngine = 'claude' | 'codex'

export interface ExternalSession {
  sessionId: string
  engine: ExternalEngine
  transcriptPath: string
  /** The folder it ran in, and so the folder it resumes in. */
  cwd: string
  origin: ExternalOrigin
  /** Codex's thread name (`session_index.jsonl`); Claude's comes from the transcript as it is indexed. */
  title: string
  /** When the file last changed, epoch ms. */
  mtime: number
}

type Head = Pick<ExternalSession, 'sessionId' | 'engine' | 'cwd' | 'origin'>

/** How much of a file is read to classify it: a Claude file's first lines, a Codex file's first line. */
const CLAUDE_HEAD_BYTES = 256 * 1024
const CODEX_HEAD_BYTES = 1024 * 1024
const SESSION_ID = /^[A-Za-z0-9-]{8,80}$/

export interface ExternalSessionsOptions {
  claudeProjectsDir: string
  codexHome: string
}

export class ExternalSessions {
  /** A verdict per file: its head, or null for a file that is not a person's conversation. */
  private readonly heads = new Map<string, Head | null>()
  private found: ExternalSession[] = []
  private byId = new Map<string, ExternalSession>()
  private scanning: Promise<ExternalSession[]> | null = null

  constructor(private readonly opts: ExternalSessionsOptions) {}

  /** What the last scan found, newest first. */
  list(): readonly ExternalSession[] { return this.found }

  get(sessionId: string): ExternalSession | undefined { return this.byId.get(sessionId) }

  /** Looks again. One scan at a time: a second caller shares the one in progress. */
  scan(): Promise<ExternalSession[]> {
    this.scanning ??= this.scanOnce().finally(() => { this.scanning = null })
    return this.scanning
  }

  private async scanOnce(): Promise<ExternalSession[]> {
    const found: ExternalSession[] = []
    const seen = new Set<string>()
    const consider = async (path: string, read: (path: string) => Promise<Head | null>, title = (_id: string) => '') => {
      seen.add(path)
      const file = await stat(path).catch(() => null)
      if (!file?.isFile()) return
      let head = this.heads.get(path)
      if (head === undefined) {
        head = await read(path).catch(() => null)
        this.heads.set(path, head)
      }
      if (head) found.push({ ...head, transcriptPath: path, title: title(head.sessionId), mtime: Math.floor(file.mtimeMs) })
      // A first scan reads a thousand files: let the daemon breathe between them.
      if (seen.size % 64 === 0) await new Promise<void>((resolve) => setImmediate(resolve))
    }

    for (const project of await entries(this.opts.claudeProjectsDir)) {
      if (!project.isDirectory()) continue
      const folder = join(this.opts.claudeProjectsDir, project.name)
      // Only the project's own files: a sub-agent's are in a folder beneath it.
      for (const file of await entries(folder)) {
        if (file.isFile() && file.name.endsWith('.jsonl')) await consider(join(folder, file.name), readClaudeHead)
      }
    }

    const titles = await codexTitles(join(this.opts.codexHome, 'session_index.jsonl'))
    for (const path of [
      ...await rollouts(join(this.opts.codexHome, 'sessions')),
      ...await rollouts(join(this.opts.codexHome, 'archived_sessions')),
    ]) await consider(path, readCodexHead, (id) => titles.get(id) ?? '')

    for (const path of [...this.heads.keys()]) if (!seen.has(path)) this.heads.delete(path)
    found.sort((a, b) => b.mtime - a.mtime)
    this.found = found
    this.byId = new Map(found.map((session) => [session.sessionId, session]))
    return found
  }
}

async function entries(dir: string) {
  return readdir(dir, { withFileTypes: true }).catch(() => [])
}

/** Every rollout file under a Codex sessions folder (`YYYY/MM/DD/rollout-*.jsonl`), at any depth. */
async function rollouts(dir: string): Promise<string[]> {
  const out: string[] = []
  const walk = async (at: string, depth: number): Promise<void> => {
    for (const entry of await entries(at)) {
      const path = join(at, entry.name)
      if (entry.isDirectory() && depth < 4) await walk(path, depth + 1)
      else if (entry.isFile() && entry.name.startsWith('rollout-') && entry.name.endsWith('.jsonl')) out.push(path)
    }
  }
  await walk(dir, 0)
  return out
}

async function readHead(path: string, bytes: number): Promise<string> {
  const handle = await open(path, 'r')
  try {
    const buffer = Buffer.alloc(bytes)
    const { bytesRead } = await handle.read(buffer, 0, bytes, 0)
    return buffer.subarray(0, bytesRead).toString('utf8')
  } finally {
    await handle.close()
  }
}

/** A Claude Code transcript's session, folder and entrypoint, from the first line that has them. */
export async function readClaudeHead(path: string): Promise<Head | null> {
  const text = await readHead(path, CLAUDE_HEAD_BYTES)
  for (const line of text.split('\n')) {
    if (!line.includes('"entrypoint"')) continue
    let record: { sessionId?: unknown; cwd?: unknown; entrypoint?: unknown; isSidechain?: unknown }
    try { record = JSON.parse(line) } catch { continue }
    if (record.isSidechain === true) return null
    const origin = record.entrypoint === 'cli' ? 'terminal' : record.entrypoint === 'claude-desktop' ? 'claude-app' : null
    if (!origin) return null
    if (typeof record.sessionId !== 'string' || !SESSION_ID.test(record.sessionId)) return null
    if (typeof record.cwd !== 'string' || !record.cwd.startsWith('/')) return null
    return { sessionId: record.sessionId, engine: 'claude', cwd: record.cwd, origin }
  }
  return null
}

/** A Codex rollout's session, folder and source, from its first line (`session_meta`). */
export async function readCodexHead(path: string): Promise<Head | null> {
  const text = await readHead(path, CODEX_HEAD_BYTES)
  const newline = text.indexOf('\n')
  if (newline < 0) return null
  let record: { type?: unknown; payload?: { id?: unknown; cwd?: unknown; source?: unknown; originator?: unknown } }
  try { record = JSON.parse(text.slice(0, newline)) } catch { return null }
  const meta = record.payload
  if (record.type !== 'session_meta' || !meta) return null
  const origin = meta.source === 'cli' ? 'terminal'
    : meta.source === 'vscode' ? (meta.originator === 'Codex Desktop' ? 'codex-app' : 'editor')
    : null
  if (!origin) return null
  if (typeof meta.id !== 'string' || !SESSION_ID.test(meta.id)) return null
  if (typeof meta.cwd !== 'string' || !meta.cwd.startsWith('/')) return null
  return { sessionId: meta.id, engine: 'codex', cwd: meta.cwd, origin }
}

/** Codex's thread names: `session_index.jsonl`, one `{id, thread_name}` a line, the last one winning. */
async function codexTitles(path: string): Promise<Map<string, string>> {
  const titles = new Map<string, string>()
  const text = await readFile(path, 'utf8').catch(() => '')
  for (const line of text.split('\n')) {
    try {
      const record = JSON.parse(line) as { id?: unknown; thread_name?: unknown }
      if (typeof record.id === 'string' && typeof record.thread_name === 'string' && record.thread_name.trim()) {
        titles.set(record.id, record.thread_name.trim())
      }
    } catch { /* a line being written */ }
  }
  return titles
}

export interface OpenSessionsOptions {
  /** `~/.claude`: running Claude Code processes each keep `sessions/<pid>.json` there. */
  claudeHome: string
  /** How long an answer is reused. */
  maxAgeMs?: number
  /** Whether a process is running; tests replace it. */
  alive?: (pid: number) => boolean
  /** The Codex rollouts open in a running process; tests replace it. */
  openRollouts?: () => Promise<string[]>
  now?: () => number
}

/**
 * Which sessions are open in a running process right now, so Cmd-P does not open one a second time
 * beside a terminal that still has it: both would write the same conversation.
 *
 * Claude Code says so itself — each running process keeps `~/.claude/sessions/<pid>.json` naming its
 * session. Codex keeps no such record, but holds its rollout file open while it runs, so the
 * operating system says which are (`lsof`).
 */
export class OpenSessions {
  private answer: { at: number; ids: Set<string> } | null = null
  private asking: Promise<Set<string>> | null = null

  constructor(private readonly opts: OpenSessionsOptions) {}

  /** The last answer, however old; empty before the first. Never waits. */
  known(): ReadonlySet<string> {
    const now = (this.opts.now ?? Date.now)()
    if (!this.answer || now - this.answer.at > (this.opts.maxAgeMs ?? 5_000)) void this.fresh()
    return this.answer?.ids ?? new Set()
  }

  /** An answer at most `maxAgeMs` old. */
  fresh(): Promise<Set<string>> {
    const now = (this.opts.now ?? Date.now)()
    if (this.answer && now - this.answer.at <= (this.opts.maxAgeMs ?? 5_000)) return Promise.resolve(this.answer.ids)
    this.asking ??= this.read().then((ids) => {
      this.answer = { at: (this.opts.now ?? Date.now)(), ids }
      return ids
    }).finally(() => { this.asking = null })
    return this.asking
  }

  private async read(): Promise<Set<string>> {
    const ids = new Set<string>()
    const alive = this.opts.alive ?? processAlive
    const dir = join(this.opts.claudeHome, 'sessions')
    for (const file of await entries(dir)) {
      if (!file.isFile() || !file.name.endsWith('.json')) continue
      try {
        const record = JSON.parse(await readFile(join(dir, file.name), 'utf8')) as { pid?: unknown; sessionId?: unknown }
        if (typeof record.pid === 'number' && typeof record.sessionId === 'string' && alive(record.pid)) ids.add(record.sessionId)
      } catch { /* one being written, or gone */ }
    }
    for (const path of await (this.opts.openRollouts ?? openCodexRollouts)().catch(() => [])) {
      const id = /-([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\.jsonl$/i.exec(path)?.[1]
      if (id) ids.add(id)
    }
    return ids
  }
}

function processAlive(pid: number): boolean {
  try { process.kill(pid, 0); return true } catch (error) { return (error as NodeJS.ErrnoException).code === 'EPERM' }
}

/** The rollout files Codex processes have open: `lsof` over processes named codex. */
function openCodexRollouts(): Promise<string[]> {
  return new Promise((resolve) => {
    execFile('lsof', ['-n', '-P', '-Fn', '-c', 'codex', '-c', 'Codex'], { timeout: 3_000, maxBuffer: 8 * 1024 * 1024 }, (_error, stdout) => {
      // lsof exits 1 when a name matches no process; what it printed is still the answer.
      resolve(String(stdout ?? '').split('\n')
        .filter((line) => line.startsWith('n') && line.includes('rollout-') && line.endsWith('.jsonl'))
        .map((line) => line.slice(1)))
    })
  })
}
