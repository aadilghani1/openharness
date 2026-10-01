import { emitKeypressEvents } from 'node:readline'

export type SignInMethod = 'sso' | 'qr'

const OPTIONS: Array<{ method: SignInMethod; label: string }> = [
  { method: 'sso', label: 'SSO in your browser' },
  { method: 'qr', label: 'Scan a QR with Harness on your phone' },
]

/**
 * `harness login` at a terminal with no flag: how to sign in. ↑/↓ (or k/j) move, Enter takes,
 * 1 or 2 take that row at once, Esc / q / Ctrl-C leave with null. Starts on SSO, as Enter always
 * did. Drawn in place like `harness remote`'s machine picker — the rows are rewritten on every move.
 */
export function pickSignInMethod(io: {
  input: NodeJS.ReadStream & { isTTY?: boolean }
  output: NodeJS.WritableStream
}): Promise<SignInMethod | null> {
  const { input, output } = io
  return new Promise((resolve) => {
    let index = 0
    let drawn = 0
    const draw = (): void => {
      if (drawn) output.write(`\x1b[${drawn}A\x1b[J`)
      const lines = [
        '  Sign in with:   ↑/↓ choose · Enter select · Esc cancel',
        ...OPTIONS.map((o, at) => `  ${at === index ? '❯' : ' '} ${o.label}`),
      ]
      output.write(lines.join('\n') + '\n')
      drawn = lines.length
    }
    const finish = (method: SignInMethod | null): void => {
      input.off('keypress', onKey)
      if (input.isTTY) input.setRawMode(false)
      input.pause()
      resolve(method)
    }
    const onKey = (text: string | undefined, key: { name?: string; ctrl?: boolean } = {}): void => {
      if ((key.ctrl && key.name === 'c') || key.name === 'escape' || key.name === 'q') { finish(null); return }
      if (key.name === 'return' || key.name === 'enter') { finish(OPTIONS[index]!.method); return }
      const n = Number(text)
      if (Number.isInteger(n) && n >= 1 && n <= OPTIONS.length) { index = n - 1; draw(); finish(OPTIONS[index]!.method); return }
      if (key.name === 'up' || key.name === 'k') index = (index - 1 + OPTIONS.length) % OPTIONS.length
      else if (key.name === 'down' || key.name === 'j') index = (index + 1) % OPTIONS.length
      else return
      draw()
    }
    emitKeypressEvents(input)
    if (input.isTTY) input.setRawMode(true)
    input.resume()
    input.on('keypress', onKey)
    output.write('\n')
    draw()
  })
}
