import { spawn, spawnSync } from 'child_process'
import { createServer, type Server } from 'http'
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync, mkdirSync } from 'fs'
import { tmpdir } from 'os'
import { join } from 'path'
import { fileURLToPath } from 'url'
import { afterEach, describe, expect, it } from 'vitest'

const CLI_ROOT = fileURLToPath(new URL('..', import.meta.url))
const CLI_SOURCE = join(CLI_ROOT, 'src', 'cli.ts')
const TSX = join(CLI_ROOT, 'node_modules', 'tsx', 'dist', 'cli.mjs')
const dirs: string[] = []
const servers: Server[] = []

afterEach(async () => {
  for (const dir of dirs.splice(0)) rmSync(dir, { recursive: true, force: true })
  for (const server of servers.splice(0)) {
    // http.Server#close() only stops NEW connections — it waits forever for any keep-alive socket the
    // CLI's own `fetch` left open (undici pools connections for reuse) unless those are force-closed too.
    server.closeAllConnections?.()
    await new Promise<void>((resolve) => server.close(() => resolve()))
  }
})

function tempRoot(): string {
  const root = mkdtempSync(join(tmpdir(), 'harness-cli-auth-'))
  dirs.push(root)
  return root
}

function seedSession(root: string, opts: { expiresInMs?: number } = {}): void {
  const authDir = join(root, 'auth')
  mkdirSync(authDir, { recursive: true })
  writeFileSync(join(authDir, 'session.json'), JSON.stringify({
    version: 1,
    accessToken: 'tok_seeded',
    refreshToken: 'refresh_seeded',
    expiresAt: Date.now() + (opts.expiresInMs ?? 60 * 60_000), // an hour out — accessToken() must not attempt a refresh
    autonomousEnv: 'prod',
    computerId: 'a'.repeat(32),
    machineId: 'm_seeded',
    updatedAt: Date.now(),
  }))
}

function envFor(root: string, backendUrl?: string): NodeJS.ProcessEnv {
  return {
    ...process.env,
    HOME: root,
    HARNESS_AUTH_DIR: join(root, 'auth'),
    ADAPTER_DATA_DIR: join(root, 'data'),
    ADAPTER_RUNTIME_DIR: join(root, 'runtime'),
    ADAPTER_CLI_DIR: join(root, 'cli'),
    ADAPTER_COMPUTER_ID_FILE: join(root, 'computer-id'),
    ADAPTER_UPDATE_DISABLE: 'true',
    // Sign-in should exercise the fake backend, never a developer's Grid binary or its installer.
    HARNESS_GRID_BIN: join(root, 'grid-unavailable'),
    DISABLE_GRID_INSTALL: 'true',
    ...(backendUrl ? { BACKEND_WS_URL: backendUrl } : {}),
  }
}

/** A `grid` that records every call it gets, at the path [envFor] hands the child — for pinning that
 *  signing in to Harness runs none. Returns where the calls land (absent while there were none). */
function recordingGrid(root: string): string {
  const calls = join(root, 'grid-calls')
  writeFileSync(join(root, 'grid-unavailable'), `#!/bin/sh\necho "$*" >> '${calls}'\nexit 0\n`, { mode: 0o755 })
  return calls
}

function runSync(root: string, args: string[], backendUrl?: string) {
  return spawnSync(process.execPath, [TSX, CLI_SOURCE, ...args], {
    cwd: CLI_ROOT,
    encoding: 'utf8',
    env: envFor(root, backendUrl),
  })
}

/** Async spawn — REQUIRED (not spawnSync) whenever the child talks back to a fake backend hosted in
 *  this same test process: spawnSync blocks this process's entire event loop until the child exits,
 *  so a fake server living here could never answer the child's request and the pair would deadlock. */
function runAsync(root: string, args: string[], backendUrl?: string): Promise<{ status: number | null; stdout: string; stderr: string }> {
  return new Promise((resolve) => {
    const child = spawn(process.execPath, [TSX, CLI_SOURCE, ...args], { cwd: CLI_ROOT, env: envFor(root, backendUrl) })
    let stdout = ''
    let stderr = ''
    child.stdout.on('data', (c: Buffer) => { stdout += c.toString() })
    child.stderr.on('data', (c: Buffer) => { stderr += c.toString() })
    child.once('exit', (status) => resolve({ status, stdout, stderr }))
  })
}

/** A minimal fake backend for the two `/api/auth/*` + resolve-computer calls `harness login`/
 *  `auth status` make — real network shape, canned answers, so the CLI's own code runs unmodified.
 *  `routes` stubs any other path (the QR sign-in's `/api/auth/qr/*`). A handler may answer with a
 *  promise, so a test can hold a step open. `calls` records every request in arrival order. */
function fakeBackend(handlers: {
  authorizeNative?: (body: any) => any
  exchange?: (body: any) => any
  resolveComputer?: (body: any) => any
  routes?: Record<string, (body: any) => unknown | Promise<unknown>>
}): Promise<{ server: Server; base: string; calls: Array<{ url: string; body: unknown }> }> {
  const calls: Array<{ url: string; body: unknown }> = []
  return new Promise((resolve) => {
    const server = createServer((req, res) => {
      let raw = ''
      req.on('data', (c) => { raw += c })
      req.on('end', () => {
        const body = raw ? JSON.parse(raw) : {}
        calls.push({ url: req.url ?? '', body })
        const send = (data: unknown): void => {
          res.writeHead(200, { 'content-type': 'application/json' })
          res.end(JSON.stringify({ success: true, data }))
        }
        const answer = (h: (body: any) => unknown): void => { void Promise.resolve(h(body)).then(send) }
        if (req.url === '/api/auth/authorize-native' && handlers.authorizeNative) { answer(handlers.authorizeNative); return }
        if (req.url === '/api/auth/exchange' && handlers.exchange) { answer(handlers.exchange); return }
        if (req.url === '/api/machines/resolve-computer' && handlers.resolveComputer) { answer(handlers.resolveComputer); return }
        const route = req.url ? handlers.routes?.[req.url] : undefined
        if (route) { answer(route); return }
        res.writeHead(404, { 'content-type': 'application/json' })
        res.end(JSON.stringify({ success: false, error: { message: 'not stubbed' } }))
      })
    })
    servers.push(server)
    server.listen(0, '127.0.0.1', () => {
      const address = server.address()
      const port = typeof address === 'object' && address ? address.port : 0
      resolve({ server, base: `http://127.0.0.1:${port}`, calls })
    })
  })
}

/** Resolves [value] after [ms] — a backend step that takes a moment, so a test can act inside it. */
function later<T>(ms: number, value: T): Promise<T> {
  return new Promise((resolve) => setTimeout(() => resolve(value), ms))
}

describe('harness auth status --json', () => {
  it('reports loggedIn:false with no saved session, and never touches the network', () => {
    const root = tempRoot()
    const result = runSync(root, ['auth', 'status', '--json'], 'http://127.0.0.1:1') // port 1: would fail fast if ever called
    expect(result.status).toBe(0)
    // The computer id travels even signed out: the daemon serves this computer under it until a
    // sign-in hands out a machineId, and the app keys the local machine by whichever it is told.
    const body = JSON.parse(result.stdout.trim()) as { loggedIn: boolean; computerId?: string }
    expect(body.loggedIn).toBe(false)
    expect(body.computerId).toMatch(/^[0-9a-f-]{36}$/)
  })

  it('falls back to human text without --json', () => {
    const root = tempRoot()
    const result = runSync(root, ['auth', 'status'])
    expect(result.status).toBe(0)
    expect(result.stdout).toContain('Not signed in')
  })

  it('reports loggedIn:true from a saved, non-expiring session without a network round trip', () => {
    const root = tempRoot()
    seedSession(root)
    const result = runSync(root, ['auth', 'status', '--json'], 'http://127.0.0.1:1')
    expect(result.status).toBe(0)
    expect(JSON.parse(result.stdout.trim())).toEqual({
      loggedIn: true,
      computerId: 'a'.repeat(32),
      machineId: 'm_seeded',
      autonomousEnv: 'prod',
      expiresAt: expect.any(Number),
      method: 'sso',
    })
  })

  it('reports loggedIn:true and offline:true when the token needs a refresh the service cannot serve', () => {
    // Near expiry forces a refresh; port 1 refuses it. That is a signed-in computer with no network —
    // not a signed-out one. It used to read as loggedIn:false and send the desktop app to a login
    // screen that could not have succeeded without the network either.
    const root = tempRoot()
    seedSession(root, { expiresInMs: 30_000 })
    const result = runSync(root, ['auth', 'status', '--json'], 'http://127.0.0.1:1')
    expect(result.status).toBe(0)
    expect(JSON.parse(result.stdout.trim())).toMatchObject({ loggedIn: true, offline: true, machineId: 'm_seeded' })
  })
})

/** A `harness … --json` child driven the way the desktop app drives it: stdin left open (closing it is
 *  the app going away), stdout read one JSON line at a time. */
function jsonChild(root: string, backendUrl: string, args: string[]) {
  const child = spawn(process.execPath, [TSX, CLI_SOURCE, ...args], { cwd: CLI_ROOT, env: envFor(root, backendUrl) })
  const lines: Record<string, unknown>[] = []
  const waiters: Array<(line: Record<string, unknown>) => void> = []
  let buffer = ''
  child.stdout.on('data', (chunk: Buffer) => {
    buffer += chunk.toString()
    while (buffer.includes('\n')) {
      const idx = buffer.indexOf('\n')
      const line = buffer.slice(0, idx).trim()
      buffer = buffer.slice(idx + 1)
      if (!line) continue
      const parsed = JSON.parse(line) as Record<string, unknown>
      const waiter = waiters.shift()
      if (waiter) waiter(parsed)
      else lines.push(parsed)
    }
  })
  const exit = new Promise<number | null>((resolve) => child.once('exit', resolve))
  // 'exit' can beat the last of stdout; 'close' is when every line is in.
  const closed = new Promise<void>((resolve) => child.once('close', () => resolve()))
  return {
    child,
    exit,
    next: (): Promise<Record<string, unknown>> => {
      const queued = lines.shift()
      return queued ? Promise.resolve(queued) : new Promise((resolve) => waiters.push(resolve))
    },
    /** Every line not yet taken by `next`, once the child's output has ended. */
    rest: async (): Promise<Record<string, unknown>[]> => { await closed; return lines.splice(0) },
  }
}

describe('harness login --json', () => {
  it('a sign-in whose app has gone stops and frees the lock; the one waiting on it says so, then goes on', async () => {
    const root = tempRoot()
    const { base } = await fakeBackend({
      authorizeNative: () => ({ authorizeUrl: 'https://sso.example.test/authorize?tx=abc', tx: 'tx_abc' }),
    })
    const first = jsonChild(root, base, ['login', '--force', '--json'])
    expect(await first.next()).toMatchObject({ type: 'authorize_url' })
    // A second sign-in while the first waits on its browser: it waits on the spawn lock, and says so
    // where the app reads — not only on stderr, which left a sign-in screen blank (2026-10-01).
    const second = jsonChild(root, base, ['login', '--force', '--json'])
    expect(await second.next()).toEqual({ type: 'waiting', message: expect.stringContaining('Another sign-in') })
    // The first one's app goes away (quit, restart): its end of stdin closes, and the sign-in stops.
    first.child.stdin.end()
    expect(await first.next()).toMatchObject({ type: 'result', status: 'error', code: 'CANCELLED' })
    expect(await first.exit).toBe(1)
    expect(await second.next()).toMatchObject({ type: 'authorize_url' })
    second.child.kill()
    await second.exit
  }, 30_000)

  /** The QR backend for a sign-in that waits on a phone which never answers. */
  const pendingQr = () => ({
    '/api/auth/qr/start': () => ({ code: 'hnq_x', pollToken: 'hnp_poll', expiresIn: 120 }),
    '/api/auth/qr/poll': () => ({ status: 'pending' }),
    '/api/auth/qr/cancel': () => ({ cancelled: true }),
  })

  it('a QR sign-in whose app goes away while it waits on the phone says CANCELLED and takes its code back', async () => {
    // Left running, the code would stay scannable on a screen nobody is watching, and the sign-in
    // would hold the spawn lock for minutes.
    const root = tempRoot()
    const { base, calls } = await fakeBackend({ routes: pendingQr() })
    const login = jsonChild(root, base, ['login', '--force', '--qr', '--json'])
    expect(await login.next()).toMatchObject({ type: 'qr' })
    login.child.stdin.end()
    expect(await login.next()).toMatchObject({ type: 'result', status: 'error', code: 'CANCELLED' })
    expect(await login.exit).toBe(1)
    expect(calls).toContainEqual({ url: '/api/auth/qr/cancel', body: { pollToken: 'hnp_poll' } })
  }, 30_000)

  it('a QR sign-in stopped by SIGTERM while it waits on the phone takes its code back', async () => {
    // The app's Cancel and its quit both send SIGTERM; the code must not outlive either.
    const root = tempRoot()
    const { base, calls } = await fakeBackend({ routes: pendingQr() })
    const login = jsonChild(root, base, ['login', '--force', '--qr', '--json'])
    expect(await login.next()).toMatchObject({ type: 'qr' })
    login.child.kill('SIGTERM')
    expect(await login.exit).toBe(1)
    expect(calls).toContainEqual({ url: '/api/auth/qr/cancel', body: { pollToken: 'hnp_poll' } })
  }, 30_000)

  it('a QR sign-in the person said yes to finishes though its app goes away right after', async () => {
    // Once the person has said yes the sign-in is theirs: the session write is quick, and taking the
    // code back then would race its claim and leave them signed out for no reason.
    const root = tempRoot()
    const { base, calls } = await fakeBackend({
      routes: {
        '/api/auth/qr/start': () => ({ code: 'hnq_x', pollToken: 'hnp_poll', expiresIn: 120 }),
        '/api/auth/qr/poll': () => ({ status: 'approved', email: 'dee@example.com' }),
        '/api/auth/qr/claim': () => ({ token: 'tok_qr', refreshToken: 'r', expiresIn: 3600, email: 'dee@example.com' }),
        '/api/auth/qr/cancel': () => ({ cancelled: true }),
      },
      // Held open so the app's pipe has closed well before the sign-in is done.
      resolveComputer: () => later(500, { machine: { machineId: 'm_qr' } }),
    })
    const login = jsonChild(root, base, ['login', '--force', '--qr', '--json'])
    expect(await login.next()).toMatchObject({ type: 'qr' })
    expect(await login.next()).toEqual({ type: 'confirm', email: 'dee@example.com' })
    login.child.stdin.end('yes\n')
    expect(await login.next()).toEqual({ type: 'result', status: 'success', email: 'dee@example.com' })
    expect(await login.exit).toBe(0)
    const session = JSON.parse(readFileSync(join(root, 'auth', 'session.json'), 'utf8')) as Record<string, unknown>
    expect(session).toMatchObject({ accessToken: 'tok_qr', method: 'qr' })
    expect(calls.map((c) => c.url)).not.toContain('/api/auth/qr/cancel')
  }, 30_000)

  it('already signed in, an app that closes its pipe at once still gets the one success line', async () => {
    // Nothing waits on a person here, so the app going away is no reason to stop: the answer it
    // asked for is already on its way, and a CANCELLED here would read as a failed sign-in.
    const root = tempRoot()
    seedSession(root)
    const { base } = await fakeBackend({
      resolveComputer: () => later(500, { machine: { machineId: 'm_seeded' } }),
    })
    const login = jsonChild(root, base, ['login', '--json'])
    login.child.stdin.end()
    expect(await login.next()).toEqual({ type: 'result', status: 'success', alreadySignedIn: true })
    expect(await login.exit).toBe(0)
    expect(await login.rest()).toEqual([])
  }, 15_000)

  it('already-signed-in short-circuit emits a single success result line', async () => {
    const root = tempRoot()
    seedSession(root)
    const gridCalls = recordingGrid(root)
    const { base } = await fakeBackend({
      resolveComputer: () => ({ machine: { machineId: 'm_seeded' } }),
    })
    const result = await runAsync(root, ['login', '--json'], base)
    expect(result.status).toBe(0)
    const lines = result.stdout.trim().split('\n').map((l) => JSON.parse(l))
    // Harness only: grid is an add-on, signed in the first time a grid feature is used — so the line
    // says nothing about grid, and not one `grid` command ran, though a `grid` was right there.
    expect(lines).toEqual([{ type: 'result', status: 'success', alreadySignedIn: true }])
    expect(existsSync(gridCalls)).toBe(false)
  })

  it('emits a BACKEND_ERROR result line (not a stack trace) when authorize-native is unreachable', async () => {
    const root = tempRoot()
    const result = await runAsync(root, ['login', '--json'], 'http://127.0.0.1:1')
    expect(result.status).toBe(1)
    const lines = result.stdout.trim().split('\n').filter(Boolean).map((l) => JSON.parse(l))
    expect(lines).toEqual([{ type: 'result', status: 'error', code: 'BACKEND_ERROR', message: expect.any(String) }])
  })

  it('drives the full loopback flow: emits authorize_url, then a success result once the callback lands', async () => {
    const root = tempRoot()
    let capturedRedirectUri = ''
    const { base } = await fakeBackend({
      authorizeNative: (body) => { capturedRedirectUri = body.redirectUri; return { authorizeUrl: 'https://sso.example.test/authorize?tx=abc', tx: 'tx_abc' } },
      exchange: () => ({ token: 'tok_new', refreshToken: 'refresh_new', expiresIn: 3600, autonomousEnv: 'prod' }),
      resolveComputer: () => ({ machine: { machineId: 'm_new' } }),
    })

    const gridCalls = recordingGrid(root)
    const child = spawn(process.execPath, [TSX, CLI_SOURCE, 'login', '--json'], {
      cwd: CLI_ROOT,
      env: envFor(root, base),
    })
    let stdout = ''
    const lines: Record<string, unknown>[] = []
    const gotUrl = new Promise<void>((resolve) => {
      child.stdout.on('data', (chunk: Buffer) => {
        stdout += chunk.toString()
        while (stdout.includes('\n')) {
          const idx = stdout.indexOf('\n')
          const line = stdout.slice(0, idx).trim()
          stdout = stdout.slice(idx + 1)
          if (line) { lines.push(JSON.parse(line)); resolve() }
        }
      })
    })

    await gotUrl
    expect(lines[0]).toEqual({ type: 'authorize_url', url: 'https://sso.example.test/authorize?tx=abc' })
    expect(capturedRedirectUri).toMatch(/^http:\/\/127\.0\.0\.1:\d+\/callback$/)

    // Simulate the browser completing SSO: hit this CLI's own loopback callback server.
    await fetch(`${capturedRedirectUri}?code=code_123&state=state_456`)

    const exitCode = await new Promise<number | null>((resolve) => child.once('exit', resolve))
    expect(exitCode).toBe(0)
    // Drain any trailing buffered line after exit.
    if (stdout.trim()) lines.push(JSON.parse(stdout.trim()))
    // Same contract as the already-signed-in line: a fresh Harness sign-in signs in to Harness alone.
    expect(lines[1]).toEqual({ type: 'result', status: 'success' })
    expect(existsSync(gridCalls)).toBe(false)
  }, 15_000)
})
