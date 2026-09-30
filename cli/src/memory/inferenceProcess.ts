import { spawn } from 'node:child_process'
import { StringDecoder } from 'node:string_decoder'
import type { OneShotOptions } from '../lib/oneshot.js'
import { MemoryError } from './types.js'

export interface InferenceFrame { text?: string; completed?: boolean; error?: string }

/** Bounded JSONL process transport shared by the two certified native adapters. */
export function runInferenceProcess(options: OneShotOptions, command: string, args: string[], env: NodeJS.ProcessEnv,
  decode: (event: Record<string, unknown>) => InferenceFrame): Promise<{ text: string }> {
  if (options.signal?.aborted) return Promise.reject(new MemoryError('inference_cancelled'))
  if (!options.model || Buffer.byteLength(options.prompt) > 120_000) return Promise.reject(new MemoryError('invalid_inference_input'))
  const child = spawn(command, args, { cwd: options.cwd, env, detached: true, stdio: ['pipe', 'pipe', 'pipe'] })
  return new Promise((resolve, reject) => {
    let pending = true
    let buffer = '', stderr = '', answer = '', totalBytes = 0
    let completed = false
    const decoder = new StringDecoder('utf8')
    const kill = (): void => {
      if (child.pid == null || child.exitCode !== null) return
      try { process.kill(-child.pid, 'SIGKILL') } catch { child.kill('SIGKILL') }
    }
    const settle = (error?: string): void => {
      if (!pending) return
      pending = false
      clearTimeout(timer)
      options.signal?.removeEventListener('abort', abort)
      if (error) { kill(); reject(new MemoryError(error)) }
      else resolve({ text: answer })
    }
    const abort = (): void => settle('inference_cancelled')
    const timer = setTimeout(() => settle('inference_timeout'), Math.max(1, Math.min(options.timeoutMs ?? 90_000, 90_000)))
    options.signal?.addEventListener('abort', abort, { once: true })
    if (options.signal?.aborted) abort()
    const line = (text: string): void => {
      if (!pending || !text.trim()) return
      try {
        const event: unknown = JSON.parse(text)
        if (!event || typeof event !== 'object' || Array.isArray(event)) { settle('invalid_inference_output'); return }
        const frame = decode(event as Record<string, unknown>)
        if (frame.error) { settle(frame.error); return }
        if (frame.text !== undefined) {
          if (typeof frame.text !== 'string') { settle('invalid_inference_output'); return }
          answer = frame.text
        }
        if (frame.completed) completed = true
      } catch { settle('invalid_inference_output') }
    }
    child.stdout.on('data', chunk => {
      if (!pending) return
      totalBytes += Buffer.byteLength(chunk)
      buffer += decoder.write(chunk)
      if (totalBytes > 1_000_000 || Buffer.byteLength(buffer) > 300_000) { settle('inference_output_too_large'); return }
      const lines = buffer.split('\n'); buffer = lines.pop() ?? ''
      for (const text of lines) line(text)
    })
    child.stderr.on('data', chunk => { stderr = (stderr + String(chunk)).slice(0, 8_000) })
    child.stdin.on('error', () => settle('inference_unavailable'))
    child.on('error', () => settle('inference_unavailable'))
    child.on('close', code => {
      buffer += decoder.end()
      if (buffer) line(buffer)
      if (code !== 0 || !completed || !answer) settle(/rate.?limit|quota|usage limit/i.test(stderr) ? 'inference_usage_limit' : 'inference_unavailable')
      else if (Buffer.byteLength(answer) > 280_000) settle('inference_output_too_large')
      else settle()
    })
    child.stdin.end(options.prompt)
  })
}
