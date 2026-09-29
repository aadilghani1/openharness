/**
 * A QR code drawn with text, for `harness link qr` and `harness login` — it has to scan from a terminal
 * reached over SSH, where nothing but characters crosses.
 *
 * Two modules per character cell (upper and lower half blocks), so the square comes out roughly square
 * in a normal terminal font. Light modules are printed as the block and dark ones as a space, then the
 * whole thing sits on a light quiet zone: a phone camera needs dark-on-light, and terminals are dark far
 * more often than not, so drawing "light" with ink is what makes it scan on the common case. On a light
 * terminal the colours come out inverted, which scanners read too.
 */
import qrcode from 'qrcode-generator'

const QUIET = 2 // modules of margin on each side; the spec asks for 4, cameras cope with 2 on a dark field

/** The module matrix for `text` (true = dark), at the smallest version that fits, error correction M. */
export function qrMatrix(text: string): boolean[][] {
  const qr = qrcode(0, 'M')
  qr.addData(text, 'Byte')
  qr.make()
  const n = qr.getModuleCount()
  return Array.from({ length: n }, (_, r) => Array.from({ length: n }, (_, c) => qr.isDark(r, c)))
}

/** `text` as lines of half-block characters, ready to print. */
export function renderQr(text: string, indent = '  '): string[] {
  const m = qrMatrix(text)
  const size = m.length + QUIET * 2
  const dark = (r: number, c: number): boolean => {
    const rr = r - QUIET, cc = c - QUIET
    return rr >= 0 && cc >= 0 && rr < m.length && cc < m.length && m[rr][cc]
  }
  const lines: string[] = []
  for (let r = 0; r < size; r += 2) {
    let line = ''
    for (let c = 0; c < size; c++) {
      const top = !dark(r, c)                       // light → inked
      const bottom = r + 1 < size ? !dark(r + 1, c) : false
      line += top && bottom ? '█' : top ? '▀' : bottom ? '▄' : ' '
    }
    lines.push(indent + line)
  }
  return lines
}
