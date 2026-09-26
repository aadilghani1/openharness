#!/usr/bin/env node
// Checks daemons/roster.json against the art rules and writes the copies each client reads.
// Run after changing the roster: node daemons/tools/generate.mjs   (CI: --check)
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs'
import { resolve, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { renderSprite, renderPortrait, statusCell, baseWidth } from './render.mjs'
import { cardLines } from './card.mjs'

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
// Earning and growing (README, "Earning eggs and growing"): whole positive numbers, an egg rule for every
// kind the server grants, levels that climb from 0, and a version for every level a daemon can reach.
const whole = (v, min = 1) => Number.isInteger(v) && v >= min
for (const kind of ['turn', 'week', 'marathon', 'night', 'history']) if (!rules.eggs[kind]) fail(`egg ${kind} is earned but has no egg rule`)
const earn = rules.earn ?? {}
for (const [path, v] of [['turn.every', earn.turn?.every], ['turn.dailyCap', earn.turn?.dailyCap], ['week.days', earn.week?.days],
  ['marathon.turns', earn.marathon?.turns], ['marathon.machines', earn.marathon?.machines], ['night.nights', earn.night?.nights]]) {
  if (!whole(v)) fail(`earn.${path} must be a whole number of at least 1`)
}
if (earn.week?.days > 7) fail('earn.week.days cannot be more than the 7 days of a week')
if (!whole(earn.night?.fromHour, 0) || !whole(earn.night?.toHour, 0) || earn.night.fromHour > earn.night.toHour || earn.night.toHour > 23) {
  fail('earn.night hours must be 0-23, fromHour <= toHour')
}
const levels = rules.bond?.levels ?? []
if (levels[0] !== 0 || levels.some((x, i) => !whole(x, 0) || (i > 0 && x <= levels[i - 1]))) fail('bond.levels must start at 0 and climb')
if (!whole(rules.bond?.xpPerTurn, 0) || !whole(rules.bond?.xpPerDay, 0)) fail('bond.xpPerTurn and bond.xpPerDay must be whole numbers')
for (const v of rules.versions) {
  const at = rules.bondForVersion[v]
  if (!whole(at, 0) || at >= levels.length) fail(`bondForVersion.${v} must be a level from 0 to ${levels.length - 1}`)
}
if (rules.bondForVersion[rules.versions[0]] !== 0) fail('the first version must need bond level 0')
// A history date may name a daemon no drop holds yet: its eggs draw from the usual pool until one does.
for (const [date, id] of Object.entries(rules.historyDates ?? {})) {
  const [m, d] = date.split('-').map(Number)
  const real = /^\d\d-\d\d$/.test(date) && m >= 1 && m <= 12 && d >= 1 && new Date(Date.UTC(2024, m - 1, d)).getUTCDate() === d
  if (!real) fail(`historyDates: ${date} is not a MM-DD calendar date`)
  if (id !== null && !/^[a-z][a-z0-9-]{0,15}$/.test(id)) fail(`historyDates.${date}: ${id} is not a daemon id or null`)
}
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

// The server needs only what decides a draw, a grant or a level: who exists, how rare, the egg rules,
// what earns an egg and how bond grows. Art stays in the clients.
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
    bondForVersion: rules.bondForVersion,
    bond: rules.bond,
    earn: rules.earn,
    historyDates: rules.historyDates,
  },
  drops: roster.drops.map(d => d.id),
  daemons: roster.daemons.map(d => ({ id: d.id, n: d.n, drop: d.drop, rarity: d.rarity })),
}
output('backend/src/lib/daemonRoster.g.ts', `${header}export const DAEMON_ROSTER = ${JSON.stringify(server, null, 2)} as const\n`)
// The pair brain's template voice (cli/src/pair/voice.ts): who exists and what each says per mood. The cli
// compiles only what is under cli/src, so it gets its own copy rather than reading this folder.
const pair = { daemons: roster.daemons.map(d => ({ id: d.id, lines: d.lines })) }
output('cli/src/pair/roster.g.ts', `${header}export const PAIR_ROSTER = ${JSON.stringify(pair, null, 2)} as const\n`)
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
// Status cells: the sprite placed in its slot, centred on the version's base width.
frames.cells = []
for (const d of roster.daemons) {
  for (const [vi, v] of rules.versions.entries()) {
    for (const mood of rules.moods) {
      for (const t of [0, 300]) {
        const s = renderSprite(roster, d, vi, mood, { t })
        frames.cells.push({ id: d.id, v, mood, t, out: statusCell(roster, s, baseWidth(roster, d, vi)) })
      }
    }
  }
}
// Cards every client draws the same way (daemons/tools/card.mjs).
frames.cards = []
for (const d of roster.daemons) {
  for (const version of rules.versions) {
    frames.cards.push({ id: d.id, version, out: cardLines(roster, d, { version }) })
    frames.cards.push({ id: d.id, version, shiny: true, serial: 42, nickname: 'pip', hatched: '2026-09-26', egg: 'first', out: cardLines(roster, d, { version, shiny: true, serial: 42, nickname: 'pip', hatched: '2026-09-26', egg: 'first' }) })
  }
}
output('daemons/frames.json', JSON.stringify(frames) + '\n')

// The lookbook draws from the roster itself, so art and odds never drift from what ships.
const lookbookPath = resolve(root, 'daemons/lookbook.html')
if (existsSync(lookbookPath)) {
  const page = readFileSync(lookbookPath, 'utf8')
  const start = '<!-- roster:start -->', end = '<!-- roster:end -->'
  const a = page.indexOf(start), b = page.indexOf(end)
  if (a < 0 || b < a) {
    console.error('daemons/lookbook.html has no roster markers')
    process.exit(1)
  }
  const data = JSON.stringify(roster).replace(/</g, '\\u003c')
  output('daemons/lookbook.html', page.slice(0, a + start.length) + `\n<script type="application/json" id="roster-data">${data}</script>\n` + page.slice(b))
}
console.log(check ? 'daemons: roster and copies are current' : `daemons: ${roster.daemons.length} daemons checked, copies written`)
