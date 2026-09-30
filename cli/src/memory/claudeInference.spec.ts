import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { afterEach, beforeEach, expect, it, vi } from 'vitest'
import { claudeMemoryCapability, runClaudeMemoryInference } from './claudeInference.js'

let directory: string, binary: string
beforeEach(() => { directory = mkdtempSync(join(tmpdir(), 'claude-memory-inference-')); binary = join(directory, 'claude-fixture'); vi.stubEnv('CLAUDE_PATH', binary) })
afterEach(() => { vi.unstubAllEnvs(); rmSync(directory, { recursive: true, force: true }) })
function program(body: string, version = '2.1.285'): void {
  writeFileSync(binary, `#!${process.execPath}
if(process.argv.includes('--version')) { console.log('${version} (Claude Code)'); process.exit(0); }
let input = ''; process.stdin.on('data', chunk => input += chunk);
process.stdin.on('end', () => { ${body} });
`, { mode: 0o700 })
}
const emit = (event: unknown) => `console.log(${JSON.stringify(JSON.stringify(event))});`
const success = emit({ type: 'result', subtype: 'success', is_error: false, result: '{"proposals":[]}' })

it('uses a fresh native process with the selected model/effort and an empty tool catalog', async () => {
  const capture = join(directory, 'launch.json')
  program(`require('node:fs').writeFileSync(${JSON.stringify(capture)}, JSON.stringify({args:process.argv.slice(2),
    foreignToken:process.env.ANTHROPIC_AUTH_TOKEN, tmux:process.env.TMUX, prompt:input}));
    ${emit({ type: 'system', subtype: 'init', tools: [] })} ${success}`)
  vi.stubEnv('ANTHROPIC_AUTH_TOKEN', 'not-the-selected-account')
  vi.stubEnv('TMUX', 'parent-terminal')
  expect(await runClaudeMemoryInference({ cwd: directory, prompt: 'synthetic evidence', model: 'selected-model', effort: 'high' }))
    .toEqual({ text: '{"proposals":[]}' })
  const launch = JSON.parse(readFileSync(capture, 'utf8'))
  expect(launch.args).toEqual(expect.arrayContaining(['--model', 'selected-model', '--effort', 'high', '--tools', '',
    '--safe-mode', '--strict-mcp-config', '--mcp-config', '{"mcpServers":{}}', '--no-session-persistence']))
  expect(launch.prompt).toBe('synthetic evidence')
  expect(launch.foreignToken).toBeUndefined()
  expect(launch.tmux).toBeUndefined()
})

it.each([
  { type: 'system', subtype: 'init', tools: ['Bash'] },
  { type: 'assistant', message: { content: [{ type: 'tool_use', name: 'Bash', input: { command: 'false' } }] } },
  { type: 'system', subtype: 'hook_started' },
])('rejects tool availability or a tool attempt before accepting any result', async event => {
  program(`${emit(event)} ${success}`)
  await expect(runClaudeMemoryInference({ cwd: directory, prompt: 'evidence', model: 'selected-model' })).rejects.toThrow('inference_tool_or_error')
})

it('does not treat an error result or partial assistant prose as a completed extraction', async () => {
  program(`${emit({ type: 'assistant', message: { content: [{ type: 'text', text: '{"proposals":[]}' }] } })}
    ${emit({ type: 'result', subtype: 'error_during_execution', is_error: true, errors: ['quota exhausted'] })}`)
  await expect(runClaudeMemoryInference({ cwd: directory, prompt: 'evidence', model: 'selected-model' })).rejects.toThrow('inference_usage_limit')
})

it('waits on an uncertified native release', async () => {
  program('throw new Error("must not invoke")', '2.99.0')
  expect(await claudeMemoryCapability()).toEqual({ supported: false, version: '2.99.0' })
  await expect(runClaudeMemoryInference({ cwd: directory, prompt: 'evidence', model: 'selected-model' })).rejects.toThrow('claude_version_uncertified')
})

it('preserves a Unicode response split across pipe chunks', async () => {
  const result = JSON.stringify({ type: 'result', subtype: 'success', is_error: false, result: '{"claim":"café"}' }) + '\n'
  program(`const bytes=Buffer.from(${JSON.stringify(result)}); const split=bytes.indexOf(Buffer.from('é'))+1;
    process.stdout.write(bytes.subarray(0,split)); setTimeout(()=>process.stdout.write(bytes.subarray(split)),20);`)
  expect((await runClaudeMemoryInference({ cwd: directory, prompt: 'evidence', model: 'selected-model' })).text).toBe('{"claim":"café"}')
})
