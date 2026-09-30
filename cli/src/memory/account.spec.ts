import { mkdtemp, mkdir, writeFile, rm } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { afterEach, beforeEach, expect, it } from 'vitest'
import { memoryAccountIdentity } from './account.js'

let home: string
beforeEach(async () => { home = await mkdtemp(join(tmpdir(), 'memory-account-')) })
afterEach(async () => { await rm(home, { recursive: true, force: true }) })
it('tracks the selected Codex home and notices another login without retaining the token', async () => {
  const selected = join(home, 'selected')
  await mkdir(selected)
  const runtime = { engine: 'codex', codexHome: selected }
  await writeFile(join(selected, 'auth.json'), JSON.stringify({ tokens: { account_id: 'first', access_token: 'secret-a' } }))
  const first = await memoryAccountIdentity(runtime, home, {})
  expect(first).toMatch(/^[a-f0-9]{64}$/)
  await writeFile(join(selected, 'auth.json'), JSON.stringify({ tokens: { account_id: 'first', access_token: 'secret-b' } }))
  expect(await memoryAccountIdentity(runtime, home, {})).toBe(first)
  await writeFile(join(selected, 'auth.json'), JSON.stringify({ tokens: { account_id: 'second', access_token: 'secret-b' } }))
  expect(await memoryAccountIdentity(runtime, home, {})).not.toBe(first)
  expect(await memoryAccountIdentity({ engine: 'codex' }, home, {})).toBeNull()
})
it('waits when identity is missing or a custom Claude provider would be used', async () => {
  expect(await memoryAccountIdentity({ engine: 'claude' }, home, {})).toBeNull()
  await writeFile(join(home, '.claude.json'), JSON.stringify({ oauthAccount: { accountUuid: 'first' } }))
  expect(await memoryAccountIdentity({ engine: 'claude' }, home, {})).toMatch(/^[a-f0-9]{64}$/)
  expect(await memoryAccountIdentity({ engine: 'claude' }, home, { ANTHROPIC_AUTH_TOKEN: 'custom' })).toBeNull()
  await writeFile(join(home, '.claude.json'), 'malformed')
  expect(await memoryAccountIdentity({ engine: 'claude' }, home, {})).toBeNull()
})
