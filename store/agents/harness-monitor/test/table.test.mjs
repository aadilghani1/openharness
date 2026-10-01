import assert from 'node:assert/strict'
import { test } from 'node:test'
import { visibleRows, memory, number, age, storageTotal, sumReading, formatValue } from '../viewer/table.js'
const rows = [
  { id: 'm1/a', name: 'Agent 10', cpu: 5, activity: 'working', branch: 'fix/hello', machine: 'office' },
  { id: 'm2/a', name: 'Agent 2', cpu: 0, activity: 'idle', branch: 'main', machine: 'studio' },
  { id: 'm1/b', name: 'Unknown', cpu: null, activity: 'offline', live: true, online: false, branch: 'main', machine: 'office' },
]
test('sort is stable, numeric and keeps unknown measurements last in either direction', () => {
  assert.deepEqual(visibleRows(rows, { filter: 'all', sort: 'cpu', direction: -1 }).map(r => r.cpu), [5, 0, null])
  assert.deepEqual(visibleRows(rows, { filter: 'all', sort: 'cpu', direction: 1 }).map(r => r.cpu), [0, 5, null])
  assert.deepEqual(visibleRows(rows, { filter: 'all', sort: 'name', direction: 1 }).map(r => r.name), ['Agent 2', 'Agent 10', 'Unknown'])
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

test('opens with active sessions only and never treats saved history as processes', () => {
  const history = { id: 'saved', name: 'Old', state: 'stopped', activity: 'stopped', live: false }
  assert.deepEqual(visibleRows([...rows, history]).map(r => r.id).sort(), ['m1/a', 'm2/a'])
  assert.equal(visibleRows([...rows, history], { filter: 'all' }).length, 3)
  assert.deepEqual(visibleRows([...rows, history], { filter: 'stopped' }).map(r => r.id), ['saved'])
  assert.equal(visibleRows(rows, { machine: 'missing' }).length, 0)
})
test('shared and nested workspace paths count once on each owning machine', () => {
  const row = (machineId, workspacePath, workspaceBytes) => ({ machineId, workspacePath, workspaceBytes })
  assert.deepEqual(storageTotal([row('m', '/a', 100), row('m', '/a', 100), row('m', '/a/b', 50), row('m', '/abc', 25), row('n', '/a', 100)]), { value: 225, partial: false })
  assert.deepEqual(storageTotal([row('m', '/a', 100), row('m', '/other', null)]), { value: 100, partial: true })
  assert.deepEqual(sumReading([{ cpu: null }, { cpu: 0 }], 'cpu'), { value: 0, partial: true })
  assert.deepEqual(sumReading([{ cpu: null }], 'cpu'), { value: null, partial: true })
  assert.equal(formatValue('rssBytes', 10.4e9), '10 GB')
  assert.equal(formatValue('cpu', 126.4), '126%')
})
