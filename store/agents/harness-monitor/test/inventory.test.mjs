import assert from 'node:assert/strict'
import { test } from 'node:test'
import { collect, mergeRows, parseModel, resolveRef, rowId, tilde } from '../lib/inventory.mjs'
import { frame, HOME, HOUR } from './fixtures.mjs'
const now = Date.now(), machine = { machineId: 'm1', name: 'Office' }
const agent = extra => frame({ resumeMode: 'conversation', monitor: { activity: 'idle', activityKnown: true }, ...extra })
const merge = (extra = {}, options = {}) => mergeRows([agent(extra)], { machine, now, ...options })[0]

test('machine and agent form the identity, including stopped work', () => {
  const a = merge({ status: 'stopped' }), b = merge({}, { machine: { machineId: 'm2' } })
  assert.equal(a.id, rowId('m1', 'a1')); assert.notEqual(a.id, b.id)
  assert.equal(a.state, 'paused'); assert.equal(a.activity, 'stopped'); assert.equal(a.canStop, false); assert.equal(a.canOpen, true)
  assert.equal(a.engine, 'claude'); assert.equal(a.sessionId, 's1')
})
test('activity and last active use owning daemon facts, not process guesses', () => {
  const row = merge({ updatedAt: now - 2 * HOUR, monitor: { activity: 'needsInput', activityKnown: true, cpu: 0 } })
  assert.equal(row.needsInput, true); assert.equal(row.activity, 'needsInput'); assert.equal(row.idleMs, 2 * HOUR)
  assert.equal(merge({ monitor: undefined }).activity, 'unknown')
})
test('unknown is not zero, offline retains metadata and disables actions', () => {
  const unknown = merge(); assert.equal(unknown.cpu, null); assert.equal(unknown.rssBytes, null); assert.equal(unknown.tokens, null)
  const zero = merge({ monitor: { activity: 'idle', activityKnown: true, cpu: 0, rssBytes: 0 }, tokenUsage: { totalTokens: 0 } })
  assert.equal(zero.cpu, 0); assert.equal(zero.tokens, 0)
  const offline = merge({}, { online: false }); assert.equal(offline.activity, 'offline'); assert.equal(offline.canOpen, false); assert.equal(offline.canStop, false)
})
test('monitor cannot stop itself, and starts/failures outrank activity', () => {
  assert.equal(merge({ dsh: 'autonomous/harness-monitor' }).canStop, false)
  assert.equal(merge({ launch: { state: 'starting' } }).activity, 'starting')
  assert.equal(merge({ launch: { state: 'failed', error: 'RESUME_UNCONFIRMED' } }).activity, 'needsInput')
})
test('cached remote rows survive disconnect; reconnection refreshes and unlinked machines disappear', async () => {
  const remote = { at: 0, answers: new Map() }; let online = true, linked = true, reads = 0
  const options = { remote, remoteIntervalMs: 0, reportMachines: async () => ({ machines: linked ? [{ machineId: 'm1', name: 'Office', online }] : [] }),
    agentsFor: async () => { reads++; return [agent()] } }
  assert.equal((await collect(options)).rows[0].canOpen, true)
  online = false
  assert.equal((await collect(options)).rows[0].activity, 'offline'); assert.equal(reads, 1)
  online = true; await collect(options); assert.equal(reads, 2)
  linked = false; assert.equal((await collect(options)).rows.length, 0)
})
test('remote read failures keep rows but never leave enabled controls', async () => {
  const remote = { at: 0, answers: new Map([['m1', [agent()]]]) }
  const result = await collect({ remote, remoteIntervalMs: 0, reportMachines: async () => ({ machines: [{ ...machine, online: true }] }), agentsFor: async () => { throw Error('Disconnected') } })
  assert.equal(result.rows[0].activity, 'offline'); assert.equal(result.degraded, true)
})
test('reconnect and failed reads refresh before the regular remote interval', async () => {
  const remote = { at: 0, answers: new Map() }; let now = 1000, online = true, fail = false, reads = 0
  const options = { remote, remoteIntervalMs: 15_000, reportMachines: async () => ({ machines: [{ ...machine, online }] }),
    agentsFor: async () => { reads++; if (fail) throw Error('Disconnected'); return [agent()] } }
  const read = () => collect({ ...options, now: now++ })
  await read(); await read(); assert.equal(reads, 1)
  online = false; assert.equal((await read()).rows[0].activity, 'offline')
  online = true; fail = true; assert.equal((await read()).rows[0].canOpen, false); assert.equal(reads, 2)
  fail = false; assert.equal((await read()).rows[0].canOpen, true); assert.equal(reads, 3)
})
test('ambiguous IDs and pane numbers cannot choose another machine', () => {
  const a = merge(), b = merge({}, { machine: { machineId: 'm2' } })
  assert.match(resolveRef('a1', [a, b]).error, /matches 2/)
  assert.match(resolveRef('%1', [a, b]).error, /matches 2/)
  assert.equal(resolveRef(a.id, [a, b]).row, a)
  assert.equal(resolveRef('1', [a, b]).row, a)
})
test('model and home parsing preserve provider IDs and directory boundaries', () => {
  assert.deepEqual(parseModel('runtime-v1:a1:opencode:opencode/muse-spark-1.3-contributor-free@auto'), { model: 'opencode/muse-spark-1.3-contributor-free', effort: 'auto' })
  assert.equal(tilde(HOME + 'other/x', HOME), HOME + 'other/x'); assert.equal(tilde(HOME + '/x', HOME), '~/x')
})
