import assert from 'node:assert/strict'
import { test } from 'node:test'
import { visibleRows, memory, number, age } from '../viewer/table.js'
const rows = [
  { id: 'm1/a', name: 'Agent 10', cpu: 5, activity: 'working', branch: 'fix/hello', machine: 'office' },
  { id: 'm2/a', name: 'Agent 2', cpu: 0, activity: 'idle', branch: 'main', machine: 'studio' },
  { id: 'm1/b', name: 'Unknown', cpu: null, activity: 'offline', branch: 'main', machine: 'office' },
]
test('sort is stable, numeric and keeps unknown measurements last in either direction', () => {
  assert.deepEqual(visibleRows(rows, { sort: 'cpu', direction: -1 }).map(r => r.cpu), [5, 0, null])
  assert.deepEqual(visibleRows(rows, { sort: 'cpu', direction: 1 }).map(r => r.cpu), [0, 5, null])
  assert.deepEqual(visibleRows(rows, { sort: 'name', direction: 1 }).map(r => r.name), ['Agent 2', 'Agent 10', 'Unknown'])
  assert.equal(rows[0].name, 'Agent 10')
})
test('search matches metadata and combines with plain status filters', () => {
  assert.equal(visibleRows(rows, { query: 'HELLO' })[0].id, 'm1/a')
  assert.equal(visibleRows(rows, { query: 'office', filter: 'offline' })[0].id, 'm1/b')
  assert.equal(visibleRows(rows, { query: 'office', filter: 'idle' }).length, 0)
})
test('formatters distinguish zero from unknown and handle future timestamps', () => {
  assert.equal(memory(null), '—'); assert.equal(memory(0), '0 MB')
  assert.equal(number(null), '—'); assert.equal(number(0), '0')
  assert.equal(age(null), '—'); assert.equal(age(1100, 1000), 'now')
})
