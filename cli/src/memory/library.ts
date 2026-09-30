/** Owner-facing library contracts. These are not model tools or scope capabilities. */
import { z } from 'zod'
import { conditionsSchema, draftSchema, type MemoryRecord, type MemorySupport, type SourceEvent } from './types.js'

const id = z.string().min(1).max(200).regex(/^[A-Za-z0-9_.:-]+$/)
export const libraryQuerySchema = z.object({
  cursor: z.string().max(2_000).optional(),
  limit: z.number().int().min(1).max(50).optional(),
  scope: z.enum(['all', 'personal', 'project']).optional(),
  projectId: id.optional(),
  state: z.enum(['active', 'tentative', 'needs_verification', 'superseded', 'archived']).optional(),
}).strict()
export type LibraryQuery = z.infer<typeof libraryQuerySchema>

export type MemorySummary = Pick<MemoryRecord,
  'id' | 'revision' | 'state' | 'scope' | 'kind' | 'facet' | 'assertionType' | 'claim' | 'evidenceClass' | 'createdAt' | 'updatedAt'>
export interface LibraryPage {
  items: MemorySummary[]
  nextCursor: string | null
  /** Privacy and corrections invalidate a page cursor rather than mixing two snapshots. */
  version: { generation: number; knowledge: number; preferences: string }
}
export interface LibraryDetail {
  record: MemoryRecord
  support: MemorySupport | null
  sources: Array<Pick<SourceEvent, 'id' | 'engine' | 'sessionId' | 'role' | 'observedAt'>>
}

/** Scope, evidence, verification, identity and conflict keys cannot be rewritten by a form payload. */
export const correctionSchema = z.object({
  claim: z.string().trim().min(1).max(2_000),
  rationale: z.string().trim().min(1).max(2_000).nullable(),
  futureAction: z.string().trim().min(1).max(2_000),
  applicability: conditionsSchema,
  exceptions: draftSchema.shape.exceptions,
  retrievalCues: draftSchema.shape.retrievalCues,
  validity: draftSchema.shape.validity,
  details: draftSchema.shape.details,
}).strict()
export type MemoryCorrection = z.infer<typeof correctionSchema>

const revision = z.number().int().positive().safe()
const preferences = z.object({ learn: z.boolean(), recall: z.boolean() }).strict()
export const libraryCommandSchema = z.discriminatedUnion('kind', [
  z.object({ kind: z.literal('correct'), id, revision, fields: correctionSchema,
    supersede: z.array(z.object({ id, revision }).strict()).max(32).optional() }).strict(),
  z.object({ kind: z.literal('forget'), id, revision }).strict(),
  z.object({ kind: z.literal('configure'), preferences, expected: preferences }).strict(),
])
export type LibraryCommand = z.infer<typeof libraryCommandSchema>
export interface LibraryPreview {
  version: LibraryPage['version']
  command: LibraryCommand
  /** All effects are computed in a rolled-back transaction; nothing is learned or deleted. */
  effects: {
    record?: MemorySummary
    deletedIds?: string[]
    deletedTopicIds?: string[]
    alreadyDeliveredContent?: 'not_erased'
    preferences?: { learn: boolean; recall: boolean }
  }
}

export function summarize(record: MemoryRecord): MemorySummary {
  const { id, revision, state, scope, kind, facet, assertionType, claim, evidenceClass, createdAt, updatedAt } = record
  return { id, revision, state, scope, kind, facet, assertionType, claim, evidenceClass, createdAt, updatedAt }
}
