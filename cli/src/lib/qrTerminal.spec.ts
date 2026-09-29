import { describe, it, expect } from 'vitest'
import * as jsqrModule from 'jsqr'

// jsqr is CommonJS with a default export; under this project's ESM settings the callable is `.default`.
type Decode = (data: Uint8ClampedArray, width: number, height: number) => { data: string } | null
const jsQR = ((jsqrModule as unknown as { default?: Decode }).default ?? jsqrModule) as unknown as Decode
import { qrMatrix, renderQr } from './qrTerminal.js'

/** The printed lines back into light/dark cells (true = light, i.e. inked), two rows per line. */
function unrender(lines: string[]): boolean[][] {
  const rows: boolean[][] = []
  for (const line of lines.map((l) => l.replace(/^ {2}/, ''))) {
    const top: boolean[] = [], bottom: boolean[] = []
    for (const ch of line) { top.push(ch === '█' || ch === '▀'); bottom.push(ch === '█' || ch === '▄') }
    rows.push(top, bottom)
  }
  return rows
}

/** What a camera would see: ink (light) as white pixels, the rest black, scaled up. */
function decode(cells: boolean[][]): string | null {
  const scale = 6, h = cells.length * scale, w = cells[0].length * scale
  const px = new Uint8ClampedArray(w * h * 4)
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const v = cells[Math.floor(y / scale)][Math.floor(x / scale)] ? 255 : 0
    px.set([v, v, v, 255], (y * w + x) * 4)
  }
  return jsQR(px, w, h)?.data ?? null
}

describe('renderQr', () => {
  const url = 'https://harness.autonomous.ai/pair#m=816c1a03ae8a2105c06366ce1d37841b&c=ABCDEFGHJKMNPQRS&f=5F80.61C4.6142.ADCF&n=machine-remote-2'

  it('prints a code a camera decodes back to the same text', () => {
    expect(decode(unrender(renderQr(url)))).toBe(url)
  })

  it('keeps every module of the matrix, inside a light quiet zone', () => {
    const m = qrMatrix(url)
    const cells = unrender(renderQr(url))
    for (let r = 0; r < m.length; r++) for (let c = 0; c < m.length; c++) expect(cells[r + 2][c + 2]).toBe(!m[r][c])
    expect(cells[0].every(Boolean)).toBe(true)
    expect(cells.map((row) => row[0]).slice(0, m.length + 4).every(Boolean)).toBe(true)
  })

  it('is small enough for an 80-column terminal', () => {
    for (const line of renderQr(url)) expect([...line].length).toBeLessThanOrEqual(80)
  })
})
