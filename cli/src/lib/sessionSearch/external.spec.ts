import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

import { afterEach, describe, expect, it } from 'vitest'

import { ExternalSessions, OpenSessions, readClaudeHead, readCodexHead } from './external.js'

const dirs: string[] = []
afterEach(() => { for (const dir of dirs.splice(0)) rmSync(dir, { recursive: true, force: true }) })
function home(): string {
  const dir = mkdtempSync(join(tmpdir(), 'external-sessions-'))
  dirs.push(dir)
  return dir
}
function write(path: string, lines: unknown[]): string {
  mkdirSync(join(path, '..'), { recursive: true })
  writeFileSync(path, lines.map((line) => typeof line === 'string' ? line : JSON.stringify(line)).join('\n') + '\n')
  return path
}

const claudeLine = (sessionId: string, entrypoint: string, extra: Record<string, unknown> = {}) => ({
  type: 'user', sessionId, cwd: '/work/dial', entrypoint, timestamp: '2026-09-20T10:00:00Z',
  message: { role: 'user', content: 'fix the dial scroll' }, ...extra,
})
const codexMeta = (id: string, source: unknown, originator = 'codex-tui') => ({
  timestamp: '2026-09-20T10:00:00Z', type: 'session_meta',
  payload: { id, cwd: '/work/cohorts', originator, source, timestamp: '2026-09-20T10:00:00Z', base_instructions: 'x'.repeat(40_000) },
})
const A = '11111111-1111-4111-8111-111111111111'
const B = '22222222-2222-4222-8222-222222222222'
const C = '01a0c4ad-de5e-7000-8000-000000000001'
const D = '01a0c4ad-de5e-7000-8000-000000000002'

describe('what counts as a conversation a person started', () => {
  it('reads Claude Code: a terminal or the Claude app, not a program or a sub-agent', async () => {
    const dir = home()
    const file = (name: string, lines: unknown[]) => write(join(dir, `${name}.jsonl`), lines)
    // The first lines may carry no entrypoint: a title, a mode.
    expect(await readClaudeHead(file('t', [{ type: 'permission-mode', permissionMode: 'auto' }, claudeLine(A, 'cli')])))
      .toEqual({ sessionId: A, engine: 'claude', cwd: '/work/dial', origin: 'terminal' })
    expect(await readClaudeHead(file('d', [claudeLine(A, 'claude-desktop')]))).toMatchObject({ origin: 'claude-app' })
    expect(await readClaudeHead(file('s', [claudeLine(A, 'sdk-cli')]))).toBeNull()
    expect(await readClaudeHead(file('x', [claudeLine(A, 'cli', { isSidechain: true })]))).toBeNull()
    expect(await readClaudeHead(file('r', [claudeLine(A, 'cli', { cwd: 'relative/path' })]))).toBeNull()
    expect(await readClaudeHead(file('e', [{ type: 'summary', summary: 'nothing else' }]))).toBeNull()
  })

  it('reads Codex: the terminal, the Codex app and the editors, not scripts or sub-agent threads', async () => {
    const dir = home()
    const file = (name: string, meta: unknown) => write(join(dir, `${name}.jsonl`), [meta, { type: 'event_msg', payload: {} }])
    expect(await readCodexHead(file('cli', codexMeta(C, 'cli'))))
      .toEqual({ sessionId: C, engine: 'codex', cwd: '/work/cohorts', origin: 'terminal' })
    expect(await readCodexHead(file('app', codexMeta(C, 'vscode', 'Codex Desktop')))).toMatchObject({ origin: 'codex-app' })
    expect(await readCodexHead(file('ide', codexMeta(C, 'vscode', 'codex_vscode')))).toMatchObject({ origin: 'editor' })
    expect(await readCodexHead(file('exec', codexMeta(C, 'exec', 'codex_exec')))).toBeNull()
    expect(await readCodexHead(file('sub', codexMeta(C, { subagent: { other: 'guardian' } })))).toBeNull()
  })
})

describe('ExternalSessions', () => {
  it("finds both engines' conversations, titles Codex's, skips sub-agents, and forgets deleted files", async () => {
    const root = home()
    const claude = join(root, '.claude', 'projects')
    const codex = join(root, '.codex')
    write(join(claude, '-work-dial', `${A}.jsonl`), [claudeLine(A, 'cli')])
    write(join(claude, '-work-dial', `${B}.jsonl`), [claudeLine(B, 'sdk-cli')])
    write(join(claude, '-work-dial', A, 'subagents', 'agent-1.jsonl'), [claudeLine(A, 'cli')])
    write(join(codex, 'sessions', '2026', '09', '20', `rollout-2026-09-20T10-00-00-${C}.jsonl`), [codexMeta(C, 'cli')])
    const archived = write(join(codex, 'archived_sessions', `rollout-2026-09-19T10-00-00-${D}.jsonl`), [codexMeta(D, 'vscode', 'Codex Desktop')])
    write(join(codex, 'session_index.jsonl'), [
      { id: C, thread_name: 'Old name', updated_at: '2026-09-20T10:00:00Z' },
      { id: C, thread_name: 'Retention cohorts', updated_at: '2026-09-21T10:00:00Z' },
      'half a line',
    ])
    const sessions = new ExternalSessions({ claudeProjectsDir: claude, codexHome: codex })
    const found = await sessions.scan()
    expect(found.map((s) => [s.sessionId, s.engine, s.origin, s.title]).sort()).toEqual([
      [C, 'codex', 'terminal', 'Retention cohorts'],
      [D, 'codex', 'codex-app', ''],
      [A, 'claude', 'terminal', ''],
    ].sort())
    expect(sessions.get(C)).toMatchObject({ cwd: '/work/cohorts', transcriptPath: expect.stringContaining(C) })

    rmSync(archived)
    await sessions.scan()
    expect(sessions.get(D)).toBeUndefined()
    expect(sessions.list()).toHaveLength(2)
  })

  it('shares one scan between callers, and finds nothing where nothing is', async () => {
    const root = home()
    const sessions = new ExternalSessions({ claudeProjectsDir: join(root, 'none'), codexHome: join(root, 'none') })
    const [a, b] = [sessions.scan(), sessions.scan()]
    expect(a).toBe(b)
    expect(await a).toEqual([])
  })
})

describe('OpenSessions', () => {
  it('knows Claude sessions from their live process records, and Codex ones from open rollouts', async () => {
    const root = home()
    write(join(root, 'sessions', '101.json'), [{ pid: 101, sessionId: A }])
    write(join(root, 'sessions', '102.json'), [{ pid: 102, sessionId: B }])
    write(join(root, 'sessions', '103.json'), ['{ being written'])
    let now = 1_000
    let reads = 0
    const open = new OpenSessions({
      claudeHome: root,
      alive: (pid) => pid === 101,
      openRollouts: async () => { reads++; return [`/h/.codex/sessions/2026/09/20/rollout-2026-09-20T10-00-00-${C}.jsonl`] },
      now: () => now,
      maxAgeMs: 5_000,
    })
    expect(open.known().size).toBe(0)
    const ids = await open.fresh()
    expect([...ids].sort()).toEqual([A, C].sort())
    expect(reads).toBe(1)
    now += 1_000
    await open.fresh()
    expect(reads).toBe(1)
    now += 10_000
    await open.fresh()
    expect(reads).toBe(2)
    expect(open.known().has(C)).toBe(true)
  })
})
