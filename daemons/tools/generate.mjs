#!/usr/bin/env node
// Checks daemons/roster.json against the art rules and writes the copies each client reads.
// Run after changing the roster: node daemons/tools/generate.mjs   (CI: --check)
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs'
import { resolve, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { renderSprite, renderPortrait } from './render.mjs'

const root = fileURLToPath(new URL('../../', import.meta.url))
const check = process.argv.includes('--check')
const text = readFileSync(resolve(root, 'daemons/roster.json'), 'utf8')
const roster = JSON.parse(text)
const { rules } = roster

const problems = []
const fail = msg => problems.push(msg)
const printable = s => /^[\x20-\x7e]*$/.test(s)

const ids = new Set()
const drops = new Set(roster.drops.map(d => d.id))
for (const d of roster.daemons) {
  if (ids.has(d.id)) fail(`${d.id}: duplicate id`)
  ids.add(d.id)
  if (!/^[a-z][a-z0-9-]{0,15}$/.test(d.id)) fail(`${d.id}: id must be a short lowercase command name`)
  if (!rules.rarities.includes(d.rarity)) fail(`${d.id}: unknown rarity ${d.rarity}`)
  if (!drops.has(d.drop)) fail(`${d.id}: unknown drop ${d.drop}`)
  if (!d.first || !printable(d.first)) fail(`${d.id}: first words missing or not ASCII`)
  for (const mood of rules.moods) {
    if (!d.lines?.[mood]) fail(`${d.id}: no line for ${mood}`)
    else if (!printable(d.lines[mood])) fail(`${d.id}: line for ${mood} is not ASCII`)
  }
  for (const v of rules.versions) if (!d.sprites?.[v]) fail(`${d.id}: no sprite for ${v}`)
  if (!d.portraits?.['2.0']) fail(`${d.id}: no 2.0 portrait`)
  // Every mood, every version, every frame of motion, plus both blink lids.
  const times = [0, 100, 200, 300, 400, 500, 600, 700, 800, 900, 1000, 1100, 1200]
  for (const mood of rules.moods) {
    for (const [vi, v] of rules.versions.entries()) {
      for (const t of times) {
        for (const lid of [null, '-', '_']) {
          const s = renderSprite(roster, d, vi, mood, { t, lid })
          if (s.length > rules.statusCells) fail(`${d.id} ${v} ${mood}: sprite "${s}" is wider than ${rules.statusCells} cells`)
          if (!printable(s)) fail(`${d.id} ${v} ${mood}: sprite "${s}" is not printable ASCII`)
        }
      }
    }
    for (const v of Object.keys(d.portraits || {})) {
      for (const t of times) {
        const lines = renderPortrait(roster, d, v, mood, { t })
        if (lines.length > rules.portraitMaxRows) fail(`${d.id} ${v}: portrait has ${lines.length} rows`)
        for (const line of lines) {
          if (/\{[a-zA-Z]+\}/.test(line)) fail(`${d.id} ${v} ${mood}: unfilled placeholder in "${line}"`)
          if (!printable(line)) fail(`${d.id} ${v} ${mood}: portrait line "${line}" is not printable ASCII`)
          if (line.length > rules.portraitMaxCols) fail(`${d.id} ${v}: portrait line is ${line.length} columns`)
        }
      }
    }
  }
}
for (const [kind, egg] of Object.entries(rules.eggs)) {
  for (const r of rules.rarities) if (typeof egg.weights[r] !== 'number') fail(`egg ${kind}: no weight for ${r}`)
  for (const id of Object.keys(egg.boost || {})) if (!ids.has(id)) fail(`egg ${kind}: boosts unknown daemon ${id}`)
}
if (rules.firstEgg.need > rules.firstEgg.habits.length) fail('first egg needs more habits than exist')
if (text.includes("'''")) fail("roster.json may not contain ''' (the Dart copy is a raw string)")
if (problems.length) {
  console.error(problems.map(p => '  ' + p).join('\n'))
  console.error(`daemons/roster.json: ${problems.length} problem(s)`)
  process.exit(1)
}

function output(path, content) {
  const full = resolve(root, path)
  if (check) {
    if (!existsSync(full) || readFileSync(full, 'utf8') !== content) {
      console.error(`${path} is stale; run node daemons/tools/generate.mjs`)
      process.exit(1)
    }
  } else {
    mkdirSync(dirname(full), { recursive: true })
    writeFileSync(full, content)
  }
}

const header = '// Generated from daemons/roster.json by daemons/tools/generate.mjs. Do not edit.\n'
output('desktop/lib/daemons/roster.g.dart', `${header}// ignore_for_file: prefer_single_quotes\nconst daemonRosterJson = r'''\n${text}''';\n`)

// The server needs only what decides a draw: who exists, how rare, and the egg rules. Art stays in the clients.
const server = {
  version: roster.version,
  rules: {
    rarities: rules.rarities,
    shinyOneIn: rules.shinyOneIn,
    pityPerMiss: rules.pityPerMiss,
    firstEgg: { need: rules.firstEgg.need, habits: rules.firstEgg.habits.map(h => h.key) },
    eggs: Object.fromEntries(Object.entries(rules.eggs).map(([k, e]) => [k, { weights: e.weights, ...(e.boost ? { boost: e.boost } : {}) }])),
    easterWords: rules.easterWords,
    versions: rules.versions,
  },
  drops: roster.drops.map(d => d.id),
  daemons: roster.daemons.map(d => ({ id: d.id, n: d.n, drop: d.drop, rarity: d.rarity })),
}
output('backend/src/lib/daemonRoster.g.ts', `${header}export const DAEMON_ROSTER = ${JSON.stringify(server, null, 2)} as const\n`)
// Frames every port must reproduce exactly (desktop and hn tests read this file).
const frames = { sprites: [], portraits: [] }
for (const d of roster.daemons) {
  for (const mood of rules.moods) {
    for (const t of [0, 300]) {
      for (const [vi, v] of rules.versions.entries()) {
        for (const lid of [null, '-']) frames.sprites.push({ id: d.id, v, mood, t, lid, out: renderSprite(roster, d, vi, mood, { t, lid }) })
        frames.portraits.push({ id: d.id, v, mood, t, out: renderPortrait(roster, d, v, mood, { t }) })
      }
    }
  }
}
output('daemons/frames.json', JSON.stringify(frames) + '\n')
console.log(check ? 'daemons: roster and copies are current' : `daemons: ${roster.daemons.length} daemons checked, copies written`)
