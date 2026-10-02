import { afterEach, expect, it, vi } from 'vitest'
import { opencodeMemoryPluginSource } from './opencodeMemoryPlugin.js'

afterEach(() => { vi.restoreAllMocks(); vi.unstubAllEnvs() })
function fixture() {
  vi.stubEnv('TMUX_PANE', '%42')
  const posts: Record<string, any>[] = []
  const fetch = vi.spyOn(globalThis, 'fetch').mockImplementation(async (_url, init) => {
    posts.push(JSON.parse(String(init?.body)))
    return new Response(JSON.stringify({ observe: true, challenge: 'one-use-grant' }), { status: 200 })
  })
  const health = vi.fn(async () => ({ data: { version: '1.18.34' } }))
  const hook = new Function('client', 'hookToken', `${opencodeMemoryPluginSource(12345)}; return memoryParams`)({ _client: { get: health } }, () => 'synthetic-hook-token')
  const input = { sessionID: 'native', message: { model: { providerID: 'selected', modelID: 'alias', variant: 'high' } },
    provider: { id: 'selected', name: 'Selected', key: 'native-api-account', options: { baseURL: 'https://selected.invalid/v1' } },
    model: { providerID: 'selected', id: 'alias', name: 'Alias', api: { id: 'provider-native-id', npm: '@ai-sdk/openai-compatible', url: 'https://catalog.invalid/v1' },
      capabilities: { temperature: false, reasoning: true, attachment: false, toolcall: true, input: { text: true }, output: { text: true }, interleaved: false },
      limit: { context: 10000, output: 1000 }, options: {}, variants: { high: { reasoningEffort: 'high' } }, headers: {},
    } }
  return { hook, input, health, fetch, posts }
}

it('hands over the actual resolved model alias, route, API account and variant only after the host grant', async () => {
  const f = fixture(), before = structuredClone(f.input)
  await f.hook(f.input)
  expect(f.posts).toHaveLength(2)
  expect(f.posts[0]).toMatchObject({ engine: 'opencode', callerPid: process.pid, sessionId: 'native', input: { kind: 'probe' } })
  expect(f.posts[1].input).toMatchObject({ kind: 'observe', nativeVersion: '1.18.34', snapshot: {
    model: 'selected/alias', variant: 'high', auth: { type: 'api', key: 'native-api-account' }, provider: {
      options: { baseURL: 'https://selected.invalid/v1' }, models: { alias: { id: 'provider-native-id', variants: { high: { reasoningEffort: 'high' } } } },
    },
  } })
  expect(f.input).toEqual(before)
})

it('does not inspect provider credentials or request health when the owner has not opted in', async () => {
  const f = fixture()
  f.fetch.mockResolvedValue(new Response('{"observe":false}'))
  Object.defineProperty(f.input, 'provider', { get() { throw new Error('credentials must not be read') } })
  await f.hook(f.input)
  expect(f.posts).toHaveLength(0)
  expect(f.fetch).toHaveBeenCalledOnce()
  expect(f.health).not.toHaveBeenCalled()
})

it('uses an explicit provider credential override instead of a different native login', async () => {
  const f = fixture()
  Object.assign(f.input.provider.options, { apiKey: 'selected-provider-account' })
  await f.hook(f.input)
  expect(f.posts[1].input.snapshot.auth.key).toBe('selected-provider-account')
  expect(f.posts[1].input.snapshot.provider.options.apiKey).toBeUndefined()
})

it.each(['version', 'model', 'oauth', 'fetch'] as const)('declines unrepresentable %s context without changing the foreground request', async kind => {
  const f = fixture()
  if (kind === 'version') f.health.mockResolvedValue({ data: { version: '2.0.0' } })
  if (kind === 'model') f.input.message.model.modelID = 'another-model'
  if (kind === 'oauth') f.input.provider.key = 'OAUTH_DUMMY_KEY'
  if (kind === 'fetch') Object.assign(f.input.provider.options, { fetch: () => {} })
  await f.hook(f.input)
  expect(f.posts).toHaveLength(kind === 'model' ? 0 : 1)
})

it('bounds an unresponsive native health request', async () => {
  const f = fixture()
  f.health.mockImplementation(() => new Promise(() => {}))
  await f.hook(f.input)
  expect(f.posts).toHaveLength(1)
})
