/**
 * `harness search <words>` — the session index from a shell: which conversation on this computer
 * said these words, and where. Reads the index the daemon keeps; never contacts it or a machine.
 */

import { existsSync } from 'node:fs'
import { join } from 'node:path'

import { MARK_CLOSE, MARK_OPEN, SessionSearchStore } from './store.js'

export const SESSION_SEARCH_FILE = 'session-search.db'

export interface SearchCommandOptions {
  argv: string[]
  dataDir: string
  output: (line: string) => void
  error: (line: string) => void
  /** Bold the matched words (a terminal) or leave them plain (a pipe). */
  color?: boolean
  now?: number
}

const USAGE = 'usage: harness search <words> [--limit=N] [--json]'

function age(at: number | null, now: number): string {
  if (at === null) return ''
  const minutes = Math.max(0, Math.round((now - at) / 60_000))
  if (minutes < 60) return `${minutes}m ago`
  if (minutes < 48 * 60) return `${Math.round(minutes / 60)}h ago`
  return `${Math.round(minutes / 1440)}d ago`
}

export function searchCommand(opts: SearchCommandOptions): number {
  const words = opts.argv.filter((arg) => !arg.startsWith('--'))
  const json = opts.argv.includes('--json')
  const limitFlag = opts.argv.find((arg) => arg.startsWith('--limit='))
  const limit = limitFlag ? Number(limitFlag.slice('--limit='.length)) : 10
  if (!words.length || !Number.isFinite(limit) || limit < 1) {
    opts.error(USAGE)
    return 2
  }
  const path = join(opts.dataDir, SESSION_SEARCH_FILE)
  if (!existsSync(path)) {
    opts.error('No session index yet. The daemon builds it in the background after `harness start`.')
    return 1
  }
  const store = SessionSearchStore.open(path)
  if (!store) {
    opts.error('Session search needs node:sqlite (Node 22.13 or later).')
    return 1
  }
  try {
    const now = opts.now ?? Date.now()
    const hits = store.search(words.join(' '), { limit, now }).map((hit) => ({
      ...hit,
      name: store.session(hit.sessionId)?.header.split(' · ')[0] ?? hit.sessionId,
    }))
    if (json) {
      opts.output(JSON.stringify({ hits }, null, 2))
      return 0
    }
    if (!hits.length) {
      opts.output(`Nothing on this computer mentions ${JSON.stringify(words.join(' '))}.`)
      return 0
    }
    const bold = (text: string) => opts.color
      ? text.replaceAll(MARK_OPEN, '\x1b[1m').replaceAll(MARK_CLOSE, '\x1b[22m')
      : text.replaceAll(MARK_OPEN, '').replaceAll(MARK_CLOSE, '')
    const lead: Record<string, string> = { ask: '> ', tools: '$ ', answer: '  ', name: '  ' }
    for (const hit of hits) {
      opts.output(`${hit.name}  ${[age(hit.at ?? hit.lastAt, now), hit.agentId.slice(0, 8)].filter(Boolean).join(' · ')}`)
      if (hit.field !== 'name') opts.output(`  ${lead[hit.field]}${bold(hit.snippet)}`)
    }
    return 0
  } finally {
    store.close()
  }
}
