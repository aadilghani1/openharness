// Bakes every plate a client can show into daemons/plates.json, so no client runs a model: each prints
// text. For every daemon with `plate: true`, at the portrait and reveal widths (rules.plate), every
// version and mood gets its loop of frames; all frames of one width and version share one crop, so
// nothing jumps between moods. The file carries a hash of what it was baked from, and is baked again
// only when a model, the shader or rules.plate changes (a bake takes minutes).
import { readFileSync, existsSync } from 'node:fs'
import { resolve } from 'node:path'
import { createHash } from 'node:crypto'
import { pathToFileURL } from 'node:url'
import { plate, crop } from './plate.mjs'

export function plateSource(root, roster) {
  const h = createHash('sha256')
  h.update(readFileSync(resolve(root, 'daemons/tools/plate.mjs')))
  h.update(JSON.stringify(roster.rules.plate))
  for (const d of roster.daemons.filter(d => d.plate)) {
    h.update(d.id)
    h.update(readFileSync(resolve(root, `daemons/plates/${d.id}.mjs`)))
  }
  return h.digest('hex')
}

export async function bakePlates(root, roster) {
  const { rules } = roster
  const spec = rules.plate
  const source = plateSource(root, roster)
  const path = resolve(root, 'daemons/plates.json')
  if (existsSync(path)) {
    const old = JSON.parse(readFileSync(path, 'utf8'))
    if (old.source === source) return old
  }
  const out = { source, frameMs: spec.frameMs, daemons: {} }
  for (const d of roster.daemons.filter(d => d.plate)) {
    const m = await import(pathToFileURL(resolve(root, `daemons/plates/${d.id}.mjs`)).href)
    const entry = {}
    for (const [size, cols] of Object.entries(spec.cols)) {
      entry[size] = {}
      for (const age of rules.versions) {
        const keys = [], frames = []
        for (const mood of rules.moods) {
          const n = mood === 'idle' ? spec.frames.idle : spec.frames.other
          for (let i = 0; i < n; i++) {
            keys.push(mood)
            frames.push(plate(m.model({ t: (i / n) * Math.PI * 2, mood, age }), cols))
          }
        }
        const cropped = crop(frames)
        const byMood = {}
        cropped.forEach((rows, i) => (byMood[keys[i]] ??= []).push(rows.join('\n')))
        entry[size][age] = byMood
      }
    }
    out.daemons[d.id] = entry
    process.stderr.write(`  baked ${d.id}\n`)
  }
  return out
}

// The colour of one character of a plate, as every client draws it: row r of `rows` takes its colour
// from the daemon's gradient, top to bottom; a faint glyph mixes from the background toward it, a dense
// one is the row colour, and `@` mixes on toward white. Returns #rrggbb.
export function plateColor(roster, d, rows, r, ch, { bg = '#0c0c0c', shiny = false } = {}) {
  const g = shiny ? d.shinyGradient : d.gradient
  const rgb = h => [1, 3, 5].map(i => parseInt(h.slice(i, i + 2), 16))
  const mix = (a, b, t) => a.map((v, i) => Math.round(v + (b[i] - v) * t))
  const row = mix(rgb(g.top.hex), rgb(g.bottom.hex), rows > 1 ? r / (rows - 1) : 0)
  const level = roster.rules.plate.ink[ch]
  if (level === undefined) return null
  const c = level > 1 ? mix(row, [255, 255, 255], level - 1) : mix(rgb(bg), row, level)
  return '#' + c.map(v => v.toString(16).padStart(2, '0')).join('')
}
