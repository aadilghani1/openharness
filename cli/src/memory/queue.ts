/** Durable episode intake and inference leases. No provider calls or raw transcripts in job metadata. */
import { randomUUID } from 'node:crypto'
import { z } from 'zod'
import { digest } from './admission.js'
import type { Database } from './database.js'
import { MemoryError, parse, sourceSchema, type MemoryAccess, type MemoryDraft, type MemoryRecord, type SourceEvent } from './types.js'

export const QUEUE_SCHEMA = `
  CREATE TABLE IF NOT EXISTS memory_streams (
    id TEXT PRIMARY KEY, engine TEXT NOT NULL, session_id TEXT NOT NULL, project_id TEXT,
    cursor TEXT NOT NULL, cursor_digest TEXT NOT NULL, updated_at INTEGER NOT NULL
  );
  CREATE TABLE IF NOT EXISTS memory_jobs (
    id TEXT PRIMARY KEY, stream_id TEXT NOT NULL REFERENCES memory_streams(id), project_id TEXT,
    state TEXT NOT NULL, priority INTEGER NOT NULL, attempts INTEGER NOT NULL DEFAULT 0, failures INTEGER NOT NULL DEFAULT 0,
    available_at INTEGER NOT NULL DEFAULT 0, lease_token TEXT, lease_until INTEGER NOT NULL DEFAULT 0,
    generation INTEGER, context_key TEXT, source_digest TEXT, last_error TEXT,
    created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL
  );
  CREATE INDEX IF NOT EXISTS memory_jobs_ready ON memory_jobs(state, available_at, priority, created_at);
  CREATE TABLE IF NOT EXISTS memory_job_sources (
    job_id TEXT NOT NULL REFERENCES memory_jobs(id) ON DELETE CASCADE,
    source_id TEXT NOT NULL REFERENCES sources(id) ON DELETE CASCADE, ordinal INTEGER NOT NULL,
    PRIMARY KEY(job_id, source_id)
  );
  CREATE INDEX IF NOT EXISTS memory_job_source ON memory_job_sources(source_id);
  CREATE TABLE IF NOT EXISTS memory_inference_calls (
    id TEXT PRIMARY KEY, started_at INTEGER NOT NULL, context_key TEXT NOT NULL
  );
  CREATE INDEX IF NOT EXISTS memory_calls_time ON memory_inference_calls(started_at);
  CREATE TABLE IF NOT EXISTS memory_queue_totals (key TEXT PRIMARY KEY,value INTEGER NOT NULL);
`
const id = z.string().min(1).max(200).regex(/^[A-Za-z0-9_.:-]+$/)
const cursor = z.string().min(1).max(256)
const captureSchema = z.object({
  streamId: id, engine: id, sessionId: id, projectId: id.nullable(), episodeId: id,
  from: cursor.nullable(), to: cursor, events: z.array(sourceSchema).max(64),
  boundary: z.enum(['open', 'complete', 'incomplete']), priority: z.enum(['routine', 'important']).default('routine'),
  generation: z.number().int().nonnegative().optional(),
}).strict()
const checkpointSchema = captureSchema.pick({ streamId: true, engine: true, sessionId: true, projectId: true, from: true, to: true })
  .extend({ generation: z.number().int().nonnegative() }).strict()
export type CaptureBatch = z.input<typeof captureSchema>
export type JobState = 'open' | 'queued' | 'reviewing' | 'waiting_for_model' | 'budget_deferred' | 'source_incomplete'
  | 'failed' | 'learned' | 'no_useful_memory' | 'cancelled' | 'expired'
export const TERMINAL_JOB_STATES = "('learned','no_useful_memory','cancelled','expired')"
export const MAX_PENDING_EPISODES = 256
export const PENDING_RETENTION_MS = 7 * 24 * 60 * 60 * 1_000
export interface InferenceTarget {
  state: 'ready' | 'waiting' | 'off' | 'unsupported'
  /** Opaque host-derived identity of the selected account, collection, model, and effort. */
  key?: string
  foregroundBusy?: boolean
}
export interface LearningLease {
  jobId: string; token: string; until: number; generation: number; contextKey: string
  sources: SourceEvent[]; access: MemoryAccess
}
export type ClaimResult = { state: 'claimed'; lease: LearningLease }
  | { state: 'idle' | 'learning_off' | 'foreground_busy' | 'waiting_for_model' | 'budget_deferred' | 'source_incomplete'; retryAt?: number }
export type FinishResult = { state: 'learned' | 'no_useful_memory'; records: MemoryRecord[] }
  | { state: 'stale' | 'failed'; reason: string }

interface QueueDeps {
  db: Database; profileId: string; now: () => number
  transaction: <T>(operation: () => T) => T
  controls: () => { learn: boolean; generation: number }
  included: (projectId: string | null) => boolean
  sessionIncluded: (engine: string, sessionId: string) => boolean
  ingest: (event: SourceEvent, generation: number) => { disposition: string }
  source: (id: string) => SourceEvent | null
  propose: (draft: MemoryDraft, access: MemoryAccess, generation: number) => { record: MemoryRecord }
  compact: (sourceIds: string[]) => void
}

const HOUR = 3_600_000
const LEASE_MS = 120_000
const MAX_CALLS_PER_HOUR = 6
const RETRYABLE = "('queued', 'waiting_for_model', 'budget_deferred', 'failed')"

export class MemoryQueue {
  constructor(private readonly deps: QueueDeps) {}

  capture(input: CaptureBatch): { disposition: 'captured' | 'duplicate'; sourceCount: number; state: JobState } {
    const batch = parse(captureSchema, input)
    const { db, now, profileId } = this.deps
    const fingerprint = digest(batch)
    return this.deps.transaction(() => {
      const controls = this.deps.controls()
      if (!controls.learn) throw new MemoryError('learning_off')
      if (batch.generation !== undefined && batch.generation !== controls.generation) throw new MemoryError('generation_changed')
      if (!this.deps.included(batch.projectId) || !this.deps.sessionIncluded(batch.engine, batch.sessionId)) throw new MemoryError('source_ineligible')
      const stream = db.prepare('SELECT * FROM memory_streams WHERE id = ?').get(batch.streamId)
      if (stream && (stream.engine !== batch.engine || stream.session_id !== batch.sessionId || stream.project_id !== batch.projectId)) throw new MemoryError('stream_identity_conflict')
      const job = db.prepare('SELECT * FROM memory_jobs WHERE id = ?').get(batch.episodeId)
      if (stream?.cursor === batch.to && stream.cursor_digest === fingerprint && job) {
        return { disposition: 'duplicate' as const, sourceCount: this.sources(batch.episodeId).length, state: job.state as JobState }
      }
      if ((stream?.cursor ?? null) !== batch.from || batch.from === batch.to) throw new MemoryError('cursor_conflict')
      if (job && (job.stream_id !== batch.streamId || !['open', 'source_incomplete'].includes(String(job.state)))) throw new MemoryError('episode_closed')
      if (!job && Number(db.prepare(`SELECT COUNT(*) AS count FROM memory_jobs WHERE state NOT IN ${TERMINAL_JOB_STATES}`).get()!.count)
        >= MAX_PENDING_EPISODES) throw new MemoryError('memory_backlog_full')
      if (batch.events.some(event => event.profileId !== profileId || event.engine !== batch.engine || event.sessionId !== batch.sessionId
        || event.projectId !== batch.projectId)) throw new MemoryError('episode_scope')
      db.prepare(`INSERT INTO memory_streams(id, engine, session_id, project_id, cursor, cursor_digest, updated_at) VALUES(?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET cursor=excluded.cursor, cursor_digest=excluded.cursor_digest, updated_at=excluded.updated_at`)
        .run(batch.streamId, batch.engine, batch.sessionId, batch.projectId, batch.to, fingerprint, now())
      if (!job) db.prepare(`INSERT INTO memory_jobs(id, stream_id, project_id, state, priority, created_at, updated_at)
        VALUES(?, ?, ?, 'open', ?, ?, ?)`).run(batch.episodeId, batch.streamId, batch.projectId, batch.priority === 'important' ? 1 : 0, now(), now())
      let ordinal = Number(db.prepare('SELECT COALESCE(MAX(ordinal), -1) AS n FROM memory_job_sources WHERE job_id = ?').get(batch.episodeId)!.n) + 1
      for (const event of batch.events) {
        if (['suppressed', 'retired'].includes(this.deps.ingest(event, controls.generation).disposition)) continue
        db.prepare('INSERT OR IGNORE INTO memory_job_sources(job_id, source_id, ordinal) VALUES(?, ?, ?)').run(batch.episodeId, event.id, ordinal++)
      }
      const sources = this.sources(batch.episodeId)
      commonScope(sources)
      if (sources.length > 128 || Buffer.byteLength(JSON.stringify(sources)) > 96_000) throw new MemoryError('episode_too_large')
      const state: JobState = batch.boundary === 'open' ? 'open' : batch.boundary === 'incomplete' ? 'source_incomplete'
        : sources.length ? 'queued' : 'cancelled'
      db.prepare('UPDATE memory_jobs SET state = ?, priority = MAX(priority, ?), updated_at = ? WHERE id = ?')
        .run(state, batch.priority === 'important' ? 1 : 0, now(), batch.episodeId)
      return { disposition: 'captured' as const, sourceCount: sources.length, state }
    })
  }

  /** Advance over metadata or establish a live-only baseline without manufacturing source events. */
  checkpoint(input: z.infer<typeof checkpointSchema>): void {
    const batch = parse(checkpointSchema, input)
    this.deps.transaction(() => {
      const controls = this.deps.controls()
      if (!controls.learn) throw new MemoryError('learning_off')
      if (controls.generation !== batch.generation) throw new MemoryError('generation_changed')
      if (!this.deps.included(batch.projectId) || !this.deps.sessionIncluded(batch.engine, batch.sessionId)) throw new MemoryError('source_ineligible')
      const stream = this.deps.db.prepare('SELECT * FROM memory_streams WHERE id = ?').get(batch.streamId)
      if (stream && (stream.engine !== batch.engine || stream.session_id !== batch.sessionId || stream.project_id !== batch.projectId)) throw new MemoryError('stream_identity_conflict')
      const fingerprint = digest(batch)
      if (stream?.cursor === batch.to && stream.cursor_digest === fingerprint) return
      if ((stream?.cursor ?? null) !== batch.from || batch.from === batch.to) throw new MemoryError('cursor_conflict')
      this.deps.db.prepare(`INSERT INTO memory_streams(id, engine, session_id, project_id, cursor, cursor_digest, updated_at) VALUES(?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET cursor=excluded.cursor, cursor_digest=excluded.cursor_digest, updated_at=excluded.updated_at`)
        .run(batch.streamId, batch.engine, batch.sessionId, batch.projectId, batch.to, fingerprint, this.deps.now())
    })
  }

  /** Cheap local check before account lookup or any native CLI version probe. */
  pendingReview(): 'ready' | 'idle' | 'learning_off' {
    if (!this.deps.controls().learn) return 'learning_off'
    return this.nextJob() ? 'ready' : 'idle'
  }

  private nextJob(): Record<string, unknown> | undefined {
    const { db, now } = this.deps
    return db.prepare(`SELECT j.* FROM memory_jobs j WHERE
      ((j.state IN ${RETRYABLE} AND j.available_at<=? AND j.failures<3) OR (j.state='reviewing' AND j.lease_until<=?))
      AND j.created_at>?
      AND (j.project_id IS NULL OR j.project_id IN (SELECT id FROM projects WHERE included=1))
      AND NOT EXISTS (SELECT 1 FROM memory_jobs active WHERE active.id!=j.id AND active.project_id IS j.project_id
        AND active.state='reviewing' AND active.lease_until>?)
      ORDER BY j.priority DESC,j.created_at,j.id LIMIT 1`).get(now(), now(), now() - PENDING_RETENTION_MS, now())
  }

  /** Reserving a call and acquiring the project lease share one transaction. */
  claim(target: InferenceTarget): ClaimResult {
    const { db, now } = this.deps
    return this.deps.transaction(() => {
      const controls = this.deps.controls()
      if (!controls.learn) return { state: 'learning_off' as const }
      this.expire()
      if (target.foregroundBusy) return { state: 'foreground_busy' as const }
      const job = this.nextJob()
      if (!job) return { state: 'idle' as const }
      const jobId = String(job.id)
      if (target.state !== 'ready' || !target.key) {
        this.release(jobId, 'waiting_for_model', target.state === 'unsupported' ? 'model_unsupported' : 'model_unavailable', now() + 60_000)
        return { state: 'waiting_for_model' as const }
      }
      const usage = db.prepare('SELECT COUNT(*) AS count, MIN(started_at) AS first FROM memory_inference_calls WHERE started_at > ?').get(now() - HOUR)!
      if (Number(usage.count) >= MAX_CALLS_PER_HOUR) {
        const retryAt = Number(usage.first) + HOUR + 1
        this.release(jobId, 'budget_deferred', 'hourly_budget', retryAt)
        return { state: 'budget_deferred' as const, retryAt }
      }
      const sources = this.sources(jobId)
      if (!sources.length) {
        this.release(jobId, 'source_incomplete', 'sources_unavailable', 0)
        return { state: 'source_incomplete' as const }
      }
      const contextKey = digest(target.key)
      const token = randomUUID()
      const until = now() + LEASE_MS
      const access: MemoryAccess = { profileId: this.deps.profileId,
        projectIds: job.project_id === null ? [] : [String(job.project_id)], includeProfile: true,
        ...commonScope(sources),
      }
      db.prepare(`UPDATE memory_jobs SET state='reviewing', lease_token=?, lease_until=?, generation=?, context_key=?, source_digest=?,
        attempts=attempts+1, updated_at=?, last_error=NULL WHERE id=?`).run(token, until, controls.generation, contextKey, digest(sources), now(), jobId)
      db.prepare('INSERT INTO memory_inference_calls(id, started_at, context_key) VALUES(?, ?, ?)').run(token, now(), contextKey)
      return { state: 'claimed' as const, lease: { jobId, token, until, generation: controls.generation, contextKey, sources, access } }
    })
  }

  finish(lease: LearningLease, proposals: MemoryDraft[], target: InferenceTarget): FinishResult {
    const { db, now } = this.deps
    return this.deps.transaction(() => {
      this.expire()
      const job = db.prepare('SELECT * FROM memory_jobs WHERE id = ?').get(lease.jobId)
      const controls = this.deps.controls()
      if (!job || job.state !== 'reviewing' || job.lease_token !== lease.token) return { state: 'stale' as const, reason: 'lease_changed' }
      if (!controls.learn || !this.deps.included(job.project_id as string | null) || controls.generation !== job.generation
        || Number(job.lease_until) <= now() || target.state !== 'ready' || !target.key || digest(target.key) !== job.context_key
        || digest(this.sources(lease.jobId)) !== job.source_digest) {
        this.release(lease.jobId, 'queued', 'context_changed', now())
        return { state: 'stale' as const, reason: 'context_changed' }
      }
      try {
        const records = this.deps.transaction(() => {
          if (!Array.isArray(proposals) || proposals.length > 8) throw new MemoryError('invalid_proposals')
          const sourceIds = new Set(this.sources(lease.jobId).map(source => source.id))
          const access: MemoryAccess = { profileId: this.deps.profileId,
            projectIds: job.project_id === null ? [] : [String(job.project_id)], includeProfile: true,
            ...commonScope(this.sources(lease.jobId)),
          }
          const records = proposals.map(proposal => {
            if (!Array.isArray(proposal?.evidence) || proposal.evidence.some(evidence => !sourceIds.has(evidence.sourceEventId))) throw new MemoryError('episode_evidence')
            return this.deps.propose(proposal, access, Number(job.generation)).record
          })
          this.release(lease.jobId, records.length ? 'learned' : 'no_useful_memory', null, 0)
          this.deps.compact([...sourceIds])
          return records
        })
        const state = records.length ? 'learned' as const : 'no_useful_memory' as const
        return { state, records }
      } catch (error) {
        const reason = error instanceof MemoryError ? error.code : 'store_unavailable'
        this.release(lease.jobId, 'failed', reason, now() + 300_000)
        return { state: 'failed' as const, reason }
      }
    })
  }

  defer(lease: LearningLease, reason: 'waiting_for_model' | 'budget_deferred' | 'failed' | 'source_incomplete'): void {
    this.deps.transaction(() => {
      const job = this.deps.db.prepare('SELECT state, lease_token FROM memory_jobs WHERE id = ?').get(lease.jobId)
      if (job?.state !== 'reviewing' || job.lease_token !== lease.token) return
      this.release(lease.jobId, reason, reason, this.deps.now() + (reason === 'budget_deferred' ? HOUR : 60_000))
    })
  }

  cursor(streamId: string): string | null {
    return this.deps.db.prepare('SELECT cursor FROM memory_streams WHERE id = ?').get(streamId)?.cursor as string | undefined ?? null
  }

  /** An open transcript cursor may outlive its episode after correction, forgetting, or privacy. */
  episodeOpen(streamId: string, episodeId: string): boolean {
    const job = this.deps.db.prepare('SELECT stream_id,state FROM memory_jobs WHERE id=?').get(episodeId)
    return job?.stream_id === streamId && ['open', 'source_incomplete'].includes(String(job.state))
  }

  status(): { jobs: Partial<Record<JobState, number>>; oldestPendingAt: number | null; callsLastHour: number; capturedStreams: number;
    retention: { expiredEpisodes: number; lastExpiredAt: number | null; maxPendingEpisodes: number; pendingRetentionMs: number } } {
    const { db, now } = this.deps
    const counts = db.prepare('SELECT state, COUNT(*) AS count FROM memory_jobs GROUP BY state').all()
    return { jobs: Object.fromEntries(counts.map(row => [row.state, Number(row.count)])),
      oldestPendingAt: db.prepare(`SELECT MIN(created_at) AS at FROM memory_jobs WHERE state NOT IN ${TERMINAL_JOB_STATES}`).get()!.at as number | null,
      callsLastHour: Number(db.prepare('SELECT COUNT(*) AS count FROM memory_inference_calls WHERE started_at > ?').get(now() - HOUR)!.count),
      capturedStreams: Number(db.prepare('SELECT COUNT(*) AS count FROM memory_streams').get()!.count),
      retention: { expiredEpisodes: Number(db.prepare("SELECT value FROM memory_queue_totals WHERE key='expired'").get()?.value ?? 0),
        lastExpiredAt: db.prepare("SELECT value FROM memory_queue_totals WHERE key='last_expired'").get()?.value as number | undefined ?? null,
        maxPendingEpisodes: MAX_PENDING_EPISODES, pendingRetentionMs: PENDING_RETENTION_MS },
    }
  }

  /** Called by the host's maintenance pass. Expiry is a visible gap, never successful learning. */
  expire(): number {
    const cutoff = this.deps.now() - PENDING_RETENTION_MS
    const count = Number(this.deps.db.prepare(`SELECT COUNT(*) AS count FROM memory_jobs
      WHERE state NOT IN ${TERMINAL_JOB_STATES} AND created_at<=?`).get(cutoff)!.count)
    this.deps.db.prepare(`UPDATE memory_jobs SET state='expired',lease_token=NULL,lease_until=0,source_digest=NULL,
      last_error='source_retention_expired',updated_at=? WHERE state NOT IN ${TERMINAL_JOB_STATES} AND created_at<=?`)
      .run(this.deps.now(), cutoff)
    if (count) {
      this.deps.db.prepare("INSERT INTO memory_queue_totals(key,value) VALUES('expired',?) ON CONFLICT(key) DO UPDATE SET value=value+excluded.value").run(count)
      this.deps.db.prepare("INSERT INTO memory_queue_totals(key,value) VALUES('last_expired',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value").run(this.deps.now())
    }
    return count
  }

  pruneMetadata(): void {
    this.deps.db.prepare(`DELETE FROM memory_jobs WHERE state IN ${TERMINAL_JOB_STATES} AND updated_at<?`)
      .run(this.deps.now() - 30 * 24 * HOUR)
    this.deps.db.prepare('DELETE FROM memory_inference_calls WHERE started_at<=?').run(this.deps.now() - HOUR)
  }

  /** Called inside correction/forget transactions, before any deleted input could be reused. */
  invalidateSources(sourceIds: Iterable<string>): void {
    for (const sourceId of sourceIds) this.deps.db.prepare(`UPDATE memory_jobs SET state='cancelled', lease_token=NULL, lease_until=0,
      source_digest=NULL, last_error='source_changed', updated_at=? WHERE id IN (SELECT job_id FROM memory_job_sources WHERE source_id=?)`)
      .run(this.deps.now(), sourceId)
  }

  private sources(jobId: string): SourceEvent[] {
    const sources = this.deps.db.prepare('SELECT source_id FROM memory_job_sources WHERE job_id = ? ORDER BY ordinal').all(jobId)
      .map(row => this.deps.source(String(row.source_id)))
    // Never quietly turn a partly private or missing episode into a different conversation.
    return sources.every((source): source is SourceEvent => source !== null) ? sources : []
  }

  private release(id: string, state: JobState, error: string | null, availableAt: number): void {
    this.deps.db.prepare(`UPDATE memory_jobs SET state=?, last_error=?, available_at=?, lease_token=NULL, lease_until=0,
      source_digest=NULL, failures=CASE WHEN ?='failed' THEN failures+1 ELSE 0 END, updated_at=? WHERE id=?`)
      .run(state, error, availableAt, state, this.deps.now(), id)
  }
}

function commonScope(sources: SourceEvent[]): { taskId?: string; branchId?: string } {
  const result: { taskId?: string; branchId?: string } = {}
  for (const key of ['taskId', 'branchId'] as const) {
    const values = new Set(sources.map(source => source[key]).filter(Boolean))
    if (values.size > 1) throw new MemoryError('episode_scope')
    if (values.size === 1) result[key] = [...values][0]
  }
  return result
}
