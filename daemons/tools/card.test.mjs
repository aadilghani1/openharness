// node --test daemons/tools/card.test.mjs
import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { cardLines, cardNumber, shelfLines, cardSvg, shelfSvg } from './card.mjs'

const roster = JSON.parse(readFileSync(new URL('../roster.json', import.meta.url), 'utf8'))
const printable = s => /^[\x20-\x7e]*$/.test(s)

test('every card, every version, is 42 printable columns', () => {
  for (const d of roster.daemons) {
    for (const version of roster.rules.versions) {
      for (const lines of [cardLines(roster, d, { version }), cardLines(roster, d, { version, shiny: true, serial: 9999, nickname: 'pip', hatched: '2026-09-26', egg: 'first' })]) {
        for (const l of lines) {
          assert.equal(l.length, 42, `${d.id} ${version}: "${l}"`)
          assert.ok(printable(l), `${d.id} ${version}: not ASCII`)
        }
      }
    }
  }
})

test('secrets sit outside the numbered set', () => {
  const secret = roster.daemons.find(d => d.rarity === 'secret')
  const regular = roster.daemons.filter(d => d.rarity !== 'secret')
  assert.match(cardNumber(roster, secret), /^#S\/\d\d$/)
  assert.equal(cardNumber(roster, regular[0]), `#01/${String(regular.length).padStart(2, '0')}`)
})

test('a shelf shows owned sprites and numbered empty slots', () => {
  const lines = shelfLines(roster, ['tim'])
  assert.match(lines[0], /^zoo: drop 1 unix {2}1\/\d+$/)
  assert.ok(lines.some(l => l.includes('[ ? ]')))
  assert.ok(lines.some(l => l.includes('[ ! ]')))
  for (const l of lines) assert.ok(printable(l))
})

test('the svg escapes markup and colours owned cells', () => {
  const svg = cardSvg(roster, roster.daemons[0], { version: '2.0' })
  assert.ok(svg.startsWith('<svg') && svg.trim().endsWith('</svg>'))
  assert.ok(!/<text[^>]*>[^<]*[<>][^<]*<\/text>/.test(svg.replace(/&lt;|&gt;/g, '')))
  const shelf = shelfSvg(roster, ['tim'])
  assert.ok(shelf.includes(roster.daemons.find(d => d.id === 'tim').color.hex))
})
