/**
 * `harness tui` — Harness in a terminal. The TUI itself is a native binary (`tui/` at the repo root,
 * Rust); this is only how the CLI finds it and hands it the terminal. It is a client of the same
 * daemon the desktop app talks to, so there is nothing to configure: the machines, the relay and
 * the desk are the daemon's.
 *
 * Where the binary comes from, first hit wins:
 *   1. `HARNESS_TUI_BIN`
 *   2. `~/.harness/bin/harness-tui` — what `harness tui --install` downloads (checksum-verified)
 *   3. a dev checkout: `tui/target/{release,debug}/harness-tui` beside this CLI's source
 *   4. `harness-tui` on PATH
 */
import { spawnSync } from 'node:child_process'
import { existsSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

import { installedTuiPath, installTui } from './install.js'
export { installTui, platformKey, TUI_MANIFEST_URL } from './install.js'

export function findTuiBinary(): string | null {
  const fromEnv = process.env.HARNESS_TUI_BIN
  if (fromEnv && existsSync(fromEnv)) return fromEnv
  if (existsSync(installedTuiPath())) return installedTuiPath()
  try {
    const here = dirname(fileURLToPath(import.meta.url))
    for (const up of ['../../../tui', '../../tui', '../tui']) {
      for (const profile of ['release', 'debug']) {
        const candidate = resolve(here, up, 'target', profile, 'harness-tui')
        if (existsSync(candidate)) return candidate
      }
    }
  } catch { /* bundled without a file URL */ }
  const which = spawnSync('sh', ['-c', 'command -v harness-tui'], { encoding: 'utf8' })
  const onPath = which.stdout?.trim()
  return which.status === 0 && onPath ? onPath : null
}

/** Read only the global flags needed for bootstrap; hn validates the full command line. */
function clientPort(argv: string[], fallback: number): number | null {
  let port = fallback
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i]
    if (a === '--') return i + 1 >= argv.length ? port : null
    if (!a.startsWith('-') || a === '-') return null
    if (a === '--port') {
      const value = argv[++i]
      if (!value || !/^\+?\d+$/.test(value) || Number(value) > 65535 || Number(value) === 0) return null
      port = Number(value)
      continue
    }
    if (a.startsWith('--')) return null
    const flags = a.slice(1)
    for (let j = 0; j < flags.length; j++) {
      // Help, shell commands, control mode and invalid flags need no daemon.
      if ('hVCc'.includes(flags[j])) return null
      if ('fLST'.includes(flags[j])) {
        if (j + 1 === flags.length && argv[++i] === undefined) return null
        break
      }
      if (!'2ulvND'.includes(flags[j])) return null
    }
  }
  return port
}

/** Only opening the default client bootstraps Harness; scripts and information commands do not. */
export function opensClient(argv: string[]): boolean {
  return clientPort(argv, 1) !== null
}

async function daemonUp(port: number): Promise<boolean> {
  try { return (await fetch(`http://127.0.0.1:${port}/api/status`, { signal: AbortSignal.timeout(2_000) })).ok } catch { return false }
}

/** This CLI, run again: `harness login`, `harness start`. Their output is the person's to read. */
function runSelf(args: string[], port: number): number {
  const script = process.argv[1]
  const result = spawnSync(process.execPath, [...process.execArgv, ...(script ? [script] : []), ...args], { stdio: 'inherit', env: { ...process.env, PORT: String(port), HARNESS_SELF: '1' } })
  return result.status ?? 1
}

/**
 * One command on a fresh server: sign in if this computer never has (over SSH the login prints a URL
 * and takes the pasted callback), start the daemon if it is down, then open.
 */
async function ensureDaemon(port: number, signedIn: () => boolean): Promise<boolean> {
  if (!signedIn()) {
    console.log('\n  This computer is not signed in to Harness yet.')
    if (runSelf(['login'], port) !== 0 || !signedIn()) return false
  }
  if (await daemonUp(port)) return true
  console.log('  Starting the Harness daemon…')
  if (runSelf(['start'], port) !== 0) return false
  for (let i = 0; i < 60; i++) {
    if (await daemonUp(port)) return true
    await new Promise((resolve) => setTimeout(resolve, 250))
  }
  console.error('  ✗ The Harness daemon did not come up. See `harness status`.')
  return false
}

export async function tuiCommand(argv: string[], opts: { port: number; signedIn?: () => boolean }): Promise<number> {
  if (argv[0] === '--install' || argv[0] === 'install') {
    try { await installTui((line) => console.log(line)); return 0 } catch (error) { console.error(`  ✗ ${(error as Error).message}`); return 1 }
  }
  if (argv[0] === '--where') { console.log(findTuiBinary() ?? '(not installed)'); return 0 }
  const port = clientPort(argv, opts.port)
  if (port !== null && opts.signedIn && !(await ensureDaemon(port, opts.signedIn))) {
    console.log('  Opening a local shell; Harness will reconnect when available.')
  }
  let binary = findTuiBinary()
  if (!binary) {
    try { binary = await installTui((line) => console.log(line)) } catch (error) {
      console.error(`  ✗ ${(error as Error).message}`)
      return 1
    }
  }
  const result = spawnSync(binary, argv, {
    stdio: 'inherit',
    // How the TUI runs this CLI back (`harness link connect` for a machine it has to link).
    env: { ...process.env, PORT: String(port ?? opts.port), HARNESS_CLI: process.execPath, HARNESS_SELF: '1', HARNESS_CLI_ARGS: JSON.stringify([...process.execArgv, process.argv[1] ?? '']) },
  })
  if (result.error) { console.error(`  ✗ Could not start ${binary}: ${result.error.message}`); return 1 }
  return result.status ?? 0
}
