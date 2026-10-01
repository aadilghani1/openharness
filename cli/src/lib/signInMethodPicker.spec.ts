import { PassThrough } from 'node:stream'
import { describe, expect, it, vi } from 'vitest'
import { pickSignInMethod } from './signInMethodPicker.js'

function tty() {
  const input = new PassThrough() as unknown as NodeJS.ReadStream & { isTTY: boolean; setRawMode: (raw: boolean) => void }
  input.isTTY = true
  input.setRawMode = vi.fn()
  const chunks: string[] = []
  const output = new PassThrough()
  output.on('data', (chunk: Buffer) => chunks.push(chunk.toString()))
  const codes: Record<string, string> = { up: '\x1b[A', down: '\x1b[B', enter: '\r', esc: '\x1b', 'ctrl-c': '\x03' }
  return {
    input, output,
    written: () => chunks.join(''),
    press: (...keys: string[]) => { for (const key of keys) (input as unknown as PassThrough).write(codes[key] ?? key) },
  }
}
const tick = () => new Promise((resolve) => setTimeout(resolve, 5))

describe('pickSignInMethod', () => {
  it('starts on SSO, so Enter alone is the browser as it always was', async () => {
    const io = tty()
    const picked = pickSignInMethod(io)
    await tick()
    expect(io.written()).toContain('❯ SSO in your browser')
    io.press('enter')
    expect(await picked).toBe('sso')
    expect(io.input.setRawMode).toHaveBeenLastCalledWith(false)
  })

  it('moves with the arrows (and j/k), wrapping, and takes Enter', async () => {
    const io = tty()
    const picked = pickSignInMethod(io)
    await tick()
    io.press('down')
    await tick()
    expect(io.written().split('❯ ').at(-1)).toMatch(/^Scan a QR/)
    io.press('j', 'k', 'up', 'up', 'enter') // qr→sso→qr→sso→qr
    expect(await picked).toBe('qr')
  })

  it('1 and 2 take their row at once', async () => {
    const io = tty()
    const picked = pickSignInMethod(io)
    await tick()
    io.press('2')
    expect(await picked).toBe('qr')
  })

  it('Esc and Ctrl-C leave with nothing chosen', async () => {
    for (const key of ['esc', 'ctrl-c']) {
      const io = tty()
      const picked = pickSignInMethod(io)
      await tick()
      io.press(key)
      expect(await picked).toBeNull()
    }
  })
})
