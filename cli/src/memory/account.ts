/** Observe native login identity without retaining or returning credentials. No network or refresh. */
import { createHash } from 'node:crypto'
import { open } from 'node:fs/promises'
import { homedir } from 'node:os'
import { join } from 'node:path'

export async function memoryAccountIdentity(input: { engine: string; codexHome?: string | null },
  home = homedir(), environment: NodeJS.ProcessEnv = process.env): Promise<string | null> {
  // These providers are not the selected native subscription supported by the initial adapter.
  if (input.engine === 'claude' && (environment.ANTHROPIC_BASE_URL || environment.ANTHROPIC_AUTH_TOKEN
    || environment.CLAUDE_CONFIG_DIR || environment.CLAUDE_CODE_OAUTH_TOKEN || environment.ANTHROPIC_API_KEY)) return null
  const path = input.engine === 'codex' ? join(input.codexHome || environment.CODEX_HOME || join(home, '.codex'), 'auth.json')
    : input.engine === 'claude' ? join(home, '.claude.json') : null
  if (!path) return null
  let handle
  try {
    handle = await open(path, 'r')
    const stat = await handle.stat()
    if (!stat.isFile() || stat.size > 8 * 1024 * 1024) return null
    const value: unknown = JSON.parse(await handle.readFile('utf8'))
    const record = object(value)
    const account = input.engine === 'codex' ? object(record.tokens).account_id : object(record.oauthAccount).accountUuid
    if (typeof account !== 'string' || !account) return null
    // Credential refreshes do not change this key. A login to another account in the same directory does.
    return createHash('sha256').update(JSON.stringify([input.engine, account])).digest('hex')
  } catch { return null } finally { await handle?.close().catch(() => {}) }
}

function object(value: unknown): Record<string, unknown> {
  return value && typeof value === 'object' && !Array.isArray(value) ? value as Record<string, unknown> : {}
}
