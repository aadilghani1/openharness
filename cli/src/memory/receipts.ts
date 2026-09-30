/** Content-free transport evidence. Printing a hook packet is not proof that a model received it. */
import { randomUUID } from 'node:crypto'
import { z } from 'zod'
import { digest } from './admission.js'
import type { Database } from './database.js'
import { visibleEvidenceSql } from './visibility.js'
import { parse, type MemoryAccess, type MemoryRecord, type RecallPacket, type RecallRequest } from './types.js'

const id = z.string().min(1).max(200).regex(/^[A-Za-z0-9_.:-]+$/)
const bindingSchema = z.object({ engine: z.enum(['claude', 'codex']), sessionId: id, projectId: id.nullable(),
  route: z.enum(['prompt_hook', 'mcp', 'manual']) }).strict()
/** Always constructed from the authenticated host session, never copied from agent arguments. */
export type MemoryDeliveryBinding = z.infer<typeof bindingSchema>
export interface RecallReceipt {
  id: string
  route: MemoryDeliveryBinding['route']
  preparedAt: number
  emittedAt: number | null
  delivery: 'unverified'
  queryDigest: string
  contextDigest: string
  packetDigest: string
  bytes: number
  estimatedTokens: number
  items: Array<{ id: string; revision: number; current: boolean }>
}
export interface PreparedRecall { packet: RecallPacket; receipt: RecallReceipt | null }
interface Deps {
  db: Database; profileId: string; now(): number
  transaction<T>(run: () => T): T
  recall(request: RecallRequest, access: MemoryAccess): RecallPacket
  read(id: string, access: MemoryAccess): MemoryRecord | null
  allowed(binding: MemoryDeliveryBinding, access: MemoryAccess): boolean
}
const RETENTION_MS = 30 * 86_400_000
const MAX_RECEIPTS = 5_000
export const RECEIPT_SCHEMA = `
  CREATE TABLE IF NOT EXISTS memory_receipts (
    id TEXT PRIMARY KEY, binding_key TEXT NOT NULL, prepared_at INTEGER NOT NULL, emitted_at INTEGER,
    route TEXT NOT NULL, query_digest TEXT NOT NULL, context_digest TEXT NOT NULL, packet_digest TEXT NOT NULL,
    bytes INTEGER NOT NULL, estimated_tokens INTEGER NOT NULL
  );
  CREATE INDEX IF NOT EXISTS memory_receipts_binding ON memory_receipts(binding_key, prepared_at);
  CREATE INDEX IF NOT EXISTS memory_receipts_age ON memory_receipts(prepared_at);
  CREATE TABLE IF NOT EXISTS memory_receipt_items (
    receipt_id TEXT NOT NULL REFERENCES memory_receipts(id) ON DELETE CASCADE,
    memory_id TEXT NOT NULL, revision INTEGER NOT NULL, PRIMARY KEY(receipt_id,memory_id)
  );
  CREATE INDEX IF NOT EXISTS memory_receipt_revisions ON memory_receipt_items(memory_id,revision);
`

export class MemoryReceipts {
  constructor(private readonly deps: Deps) {}

  prepare(request: RecallRequest, input: MemoryDeliveryBinding, access: MemoryAccess): PreparedRecall {
    const binding = parse(bindingSchema, input)
    return this.deps.transaction(() => {
      if (!this.deps.allowed(binding, access)) return { packet: empty('denied'), receipt: null }
      // Reserve the receipt field inside the same byte budget as the actual context. Empty recalls
      // do not allocate audit rows, and neither raw prompts nor recalled claims are stored here.
      const budget = typeof request.maxBytes === 'number' && Number.isFinite(request.maxBytes)
        ? Math.min(16_000, Math.max(0, Math.trunc(request.maxBytes))) : 3_000
      const withdrawn = this.withdrawn(binding)
      const withdrawal = withdrawn.references.length ? { withdrawn,
        withdrawalNotice: 'These previously supplied memory revisions are no longer current. Do not rely on them. If more is true, use only newly supplied memory. Earlier native conversation content has not been erased.' } : {}
      const reserved = 64 + Buffer.byteLength(JSON.stringify(withdrawal))
      const packet = this.deps.recall({ ...request, maxBytes: Math.max(0, budget - reserved) }, access)
      if (packet.status !== 'ok' || (!packet.items.length && !withdrawn.references.length) || reserved > budget) return { packet, receipt: null }
      const receiptId = randomUUID()
      packet.text = JSON.stringify({ ...(packet.text ? JSON.parse(packet.text) : { type: 'coding_memory_context', items: [] }),
        ...withdrawal, receiptId })
      const bytes = Buffer.byteLength(packet.text)
      if (bytes > budget) return { packet: empty('ok'), receipt: null }
      packet.estimatedTokens = Math.ceil(bytes / 3)
      const queryDigest = digest([this.deps.profileId, request.query])
      const contextDigest = digest([this.deps.profileId, binding, access, request.conditions ?? {}])
      const packetDigest = digest(packet.text)
      const preparedAt = this.deps.now()
      this.deps.db.prepare(`INSERT INTO memory_receipts
        (id,binding_key,prepared_at,emitted_at,route,query_digest,context_digest,packet_digest,bytes,estimated_tokens)
        VALUES(?,?,?,NULL,?,?,?,?,?,?)`).run(receiptId, this.key(binding), preparedAt, binding.route,
        queryDigest, contextDigest, packetDigest, bytes, packet.estimatedTokens)
      for (const item of packet.items) this.deps.db.prepare('INSERT INTO memory_receipt_items VALUES(?,?,?)')
        .run(receiptId, item.id, item.revision)
      this.prune()
      return { packet, receipt: { id: receiptId, route: binding.route, preparedAt, emittedAt: null, delivery: 'unverified',
        queryDigest, contextDigest, packetDigest, bytes, estimatedTokens: packet.estimatedTokens,
        items: packet.items.map(item => ({ id: item.id, revision: item.revision, current: true })) } }
    })
  }

  /** Only the verified transport's stdout/write completion may call this; there is no model-use claim. */
  emitted(receiptId: string, input: MemoryDeliveryBinding, access: MemoryAccess): boolean {
    const binding = parse(bindingSchema, input)
    if (!this.deps.allowed(binding, access)) return false
    const row = this.deps.db.prepare('SELECT emitted_at FROM memory_receipts WHERE id=? AND binding_key=? AND prepared_at>?')
      .get(receiptId, this.key(binding), this.deps.now() - RETENTION_MS)
    if (!row) return false
    if (row.emitted_at === null) this.deps.db.prepare('UPDATE memory_receipts SET emitted_at=? WHERE id=? AND emitted_at IS NULL')
      .run(this.deps.now(), receiptId)
    return true
  }

  list(input: MemoryDeliveryBinding, access: MemoryAccess, limit = 20): RecallReceipt[] {
    const binding = parse(bindingSchema, input)
    if (!this.deps.allowed(binding, access)) return []
    const count = Number.isFinite(limit) ? Math.min(100, Math.max(0, Math.trunc(limit))) : 20
    return this.deps.db.prepare(`SELECT * FROM memory_receipts WHERE binding_key=? AND prepared_at>?
      ORDER BY prepared_at DESC,rowid DESC LIMIT ?`).all(this.key(binding), this.deps.now() - RETENTION_MS, count).map(row => ({
      id: String(row.id), route: row.route as RecallReceipt['route'], preparedAt: Number(row.prepared_at),
      emittedAt: row.emitted_at === null ? null : Number(row.emitted_at), delivery: 'unverified',
      queryDigest: String(row.query_digest), contextDigest: String(row.context_digest), packetDigest: String(row.packet_digest),
      bytes: Number(row.bytes), estimatedTokens: Number(row.estimated_tokens),
      items: this.deps.db.prepare('SELECT memory_id,revision FROM memory_receipt_items WHERE receipt_id=?').all(row.id).map(item => {
        const record = this.deps.read(String(item.memory_id), access)
        return { id: String(item.memory_id), revision: Number(item.revision), current: !!record
          && record.revision === item.revision && record.state === 'active'
          && (record.validity.validFrom === null || record.validity.validFrom <= this.deps.now())
          && (record.validity.validUntil === null || record.validity.validUntil > this.deps.now()) }
      }),
    }))
  }

  prune(): void {
    this.deps.db.prepare('DELETE FROM memory_receipts WHERE prepared_at<=?').run(this.deps.now() - RETENTION_MS)
    this.deps.db.prepare(`DELETE FROM memory_receipts WHERE id IN
      (SELECT id FROM memory_receipts ORDER BY prepared_at DESC,rowid DESC LIMIT -1 OFFSET ?)`).run(MAX_RECEIPTS)
  }

  private withdrawn(binding: MemoryDeliveryBinding): { references: Array<{ id: string; revision: number }>; more: boolean } {
    // This is a notice about context already prepared for this exact native session, not fresh
    // disclosure of another session's knowledge. No claim or source text is retained or repeated.
    const rows = this.deps.db.prepare(`WITH previous AS MATERIALIZED (SELECT DISTINCT i.memory_id,i.revision FROM memory_receipts r
      JOIN memory_receipt_items i ON i.receipt_id=r.id WHERE r.binding_key=? AND r.prepared_at>?)
      SELECT i.memory_id,i.revision FROM previous i LEFT JOIN memories m ON m.id=i.memory_id
      WHERE m.id IS NULL OR m.revision!=i.revision OR m.state!='active'
        OR NOT (${visibleEvidenceSql()})
        OR json_extract(m.data,'$.validity.validFrom')>?
        OR json_extract(m.data,'$.validity.validUntil')<=? LIMIT 7`)
      .all(this.key(binding), this.deps.now() - RETENTION_MS, this.deps.now(), this.deps.now())
    return { references: rows.slice(0, 6).map(row => ({ id: String(row.memory_id), revision: Number(row.revision) })), more: rows.length > 6 }
  }

  private key(binding: MemoryDeliveryBinding): string { return digest([this.deps.profileId, binding]) }
}

function empty(status: RecallPacket['status']): RecallPacket { return { status, items: [], text: '', estimatedTokens: 0 } }
