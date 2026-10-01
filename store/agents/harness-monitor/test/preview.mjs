/** Synthetic browser-review fixture. No bridge, tmux, live inventory or model calls. */
import { mkdtemp } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { createViewer } from '../viewer.mjs'
import { mergeRows } from '../lib/inventory.mjs'
const workspace = await mkdtemp(join(tmpdir(), 'harness-monitor-preview-'))
process.env.HARNESS_MONITOR_CONFIG = join(workspace, 'policy.jsonc')
process.env.HARNESS_MONITOR_STATE = join(workspace, 'state')
const names = ['Replace Harness menu icon', 'Clarify completed-task form logic', 'Local debug', 'Ship workspace search', 'Review terminal reconnect', 'Add project browser', 'Render report', 'Fix session recovery']
const activities = ['working', 'needsInput', 'done', 'idle', 'working', 'idle', 'failed', 'idle']
const engines = ['codex', 'claude', 'opencode', 'cursor']
const rows = Array.from({ length: 202 }, (_, i) => mergeRows([{
  id: 'session-' + i, sessionId: 'conversation-' + i, name: names[i % names.length] + (i > 7 ? ' ' + (i + 1) : ''),
  engine: engines[i % engines.length], status: i % 7 === 6 ? 'stopped' : 'active',
  terminal: { available: true }, resumeMode: 'conversation', launch: { state: 'ready' },
  project: { name: i % 2 ? 'openharness' : 'autonomous-harness', cwd: '/home/demo/code/openharness', branch: i % 3 ? 'fix/session-recovery' : 'main' },
  selectedModel: i % 2 ? 'muse-spark-1.3-contributor-free' : 'gpt-6',
  createdAt: new Date(Date.now() - 86400000 * 3).toISOString(), updatedAt: new Date(Date.now() - i * 85000).toISOString(),
  tokenUsage: { totalTokens: i % 3 ? 57800000 : 3500000 },
  monitor: { activity: activities[i % activities.length], activityKnown: true, cpu: i % 6 ? 3.4 : null, rssBytes: (i % 6 + 1) * 260 * 1024 ** 2, pid: 3400 + i },
}], { machine: { machineId: i % 2 ? 'office' : 'm2', name: i % 2 ? 'office' : 'M2' }, local: false, online: i % 17 !== 16 })[0])
const viewer = createViewer({ workspace, port: Number(process.env.PREVIEW_PORT || 0), intervalMs: 3000,
  collect: async () => ({ rows, problems: [], machines: [] }),
  verbs: { pause: async row => {
    Object.assign(row, { state: 'paused', activity: 'stopped', canStop: false, cpu: 0, rssBytes: 0 })
    return { ok: true, action: 'pause', id: row.id, name: row.name }
  }, resume: async () => ({ ok: false, detail: 'Use the host integration fixture to resume.' }) },
})
console.log('Synthetic preview: http://127.0.0.1:' + await viewer.start())
for (const signal of ['SIGINT', 'SIGTERM']) process.once(signal, () => viewer.close().then(() => process.exit(0)))
