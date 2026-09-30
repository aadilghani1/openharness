/** Synthetic, local-only storage/recall benchmark. Never opens the user's actual memory database. */
import { mkdtemp, rm } from 'node:fs/promises'
import { tmpdir, platform, arch } from 'node:os'
import { join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { monitorEventLoopDelay, performance } from 'node:perf_hooks'
import { build } from 'esbuild'
import { CodingMemoryStore } from '../src/memory/store.js'
import { MemoryClient } from '../src/memory/client.js'
import type { SourceEvent, MemoryDraft } from '../src/memory/types.js'

const directory = await mkdtemp(join(tmpdir(), 'harness-memory-benchmark-'))
let client: MemoryClient | undefined
try {
  const opened = CodingMemoryStore.open({ directory, profileId: 'benchmark' })
  if (!opened.ok) throw new Error(opened.reason)
  const store = opened.store
  const count = 10_000
  const seededAt = performance.now()
  try {
    store.setControls({ learn: true, recall: true })
    for (let project = 0; project < 10; project++) store.registerProject(`project_${project}`)
    for (let i = 0; i < count; i++) {
      const projectId = `project_${i % 10}`
      const event: SourceEvent = { id: `source_${i}`, profileId: 'benchmark', projectId, engine: i % 2 ? 'codex' : 'claude',
        sessionId: `session_${i}`, nativeEventId: `event_${i}`, role: 'user', eligibility: 'coding', observedAt: Date.now(), rootIds: [`source_${i}`],
        text: `For fixture_${i} debugging, start with a failing test because reviewing small repairs is easier.` }
      store.ingest(event)
      const draft: MemoryDraft = { kind: 'working_preference', facet: 'debugging', assertionType: 'stated_preference',
        scope: { profileId: 'benchmark', projectId }, claim: event.text, rationale: 'Reviewing small repairs is easier.',
        futureAction: 'Start with a failing test.', applicability: { taskType: 'debugging' }, exceptions: [], retrievalCues: [`fixture_${i}`, 'debugging'],
        evidenceClass: 'user_stated', evidence: [{ sourceEventId: event.id, quote: event.text,
          paths: ['/claim', '/rationale', '/futureAction', '/applicability'] }], conflictKey: `fixture_${i}`,
        validity: { validFrom: null, validUntil: null, recheckWhen: [] } }
      store.propose(draft, { profileId: 'benchmark', projectIds: [projectId], includeProfile: false })
    }
  } finally { store.close() }
  const seedMs = performance.now() - seededAt
  const bundle = await build({ entryPoints: [fileURLToPath(new URL('../src/memory/worker.ts', import.meta.url))],
    bundle: true, write: false, platform: 'node', format: 'cjs', target: 'node20', logLevel: 'silent' })
  const workerSource = bundle.outputFiles[0].text
  const cold: number[] = []
  let timeouts = 0
  const access = { profileId: 'benchmark', projectIds: ['project_1'], includeProfile: false }
  const query = { query: 'fixture_5321', conditions: { taskType: 'debugging' } }
  for (let i = 0; i < 10; i++) {
    client = new MemoryClient({ directory, profileId: 'benchmark', source: workerSource })
    const start = performance.now()
    const packet = await client.recall(query, access)
    cold.push(performance.now() - start)
    if (packet.status === 'timeout') timeouts++
    else if (packet.status !== 'ok' || !packet.items.some(item => item.claim.includes('fixture_5321'))) throw new Error('cold_recall_mismatch')
    await client.close(); client = undefined
  }
  client = new MemoryClient({ directory, profileId: 'benchmark', source: workerSource })
  await client.request('controls', [])
  const lag = monitorEventLoopDelay({ resolution: 1 }); lag.enable()
  const warm: number[] = []
  let largestPacket = 0
  try {
    for (let i = 0; i < 300; i++) {
      const start = performance.now()
      const packet = await client.recall(i % 2 ? query : { query: 'debugging', conditions: { taskType: 'debugging' } }, access)
      warm.push(performance.now() - start)
      if (packet.status === 'timeout') timeouts++
      else if (packet.status !== 'ok' || !packet.items.length || packet.items.some(item => item.scope.projectId !== 'project_1')) throw new Error('warm_recall_mismatch')
      largestPacket = Math.max(largestPacket, Buffer.byteLength(packet.text))
    }
  } finally { lag.disable() }
  const summary = (values: number[]) => {
    values.sort((a, b) => a - b)
    return { p50Ms: values[Math.ceil(values.length * .5) - 1], p95Ms: values[Math.ceil(values.length * .95) - 1], maxMs: values.at(-1) }
  }
  console.log(JSON.stringify({ kind: 'synthetic-memory-performance', records: count, projects: 10, node: process.version,
    platform: platform(), arch: arch(), seedMs, cold: summary(cold), warm: summary(warm), requests: cold.length + warm.length,
    timeouts, largestPacketBytes: largestPacket, parentEventLoopP95Ms: lag.percentile(95) / 1e6,
    limitations: ['Synthetic lexical matches, not a retrieval-quality benchmark.', 'Cold means a new worker, not an emptied OS disk cache.',
      'One local machine; provider extraction and native hook delivery are not measured.'] }, null, 2))
} finally { await client?.close(); await rm(directory, { recursive: true, force: true }) }
