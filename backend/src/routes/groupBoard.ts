/**
 * The account's trust-group board (lib/groupBoard.ts for what a vouch is and why the server cannot
 * forge one).
 *
 *   GET  /api/group/board?since=<revision>  → { revision, entries }   (entries omitted when unchanged)
 *   POST /api/group/board { entries }        → { revision, added }
 *
 * Any signed-in client of the account may read and write: a phone or browser (viewer session), a
 * machine (daemon session), or an Autonomous JWT. After a write that added something, every web and
 * adapter socket of the account hears `group_changed` (lib/webAccountPushes.ts,
 * lib/adapterAccountPushes.ts) and re-reads.
 *
 * The desk's write discipline (routes/desk.ts): compare-and-set on the revision, retried from the
 * fresh board — merging is idempotent, so replaying the same entries is the merge.
 */
import type { FastifyInstance } from 'fastify'
import { Prisma } from '@prisma/client'
import { prisma } from '../lib/prisma.js'
import { consumeRateLimit, publishGroupChanged } from '../lib/bus.js'
import { MAX_POST_ENTRIES, mergeBoard, parseBoard, parseVouch, type Vouch } from '../lib/groupBoard.js'
import { sendError, sendSuccess } from '../utils/response.js'

const WRITE_ATTEMPTS = 5
const RATE_WINDOW_SEC = 10 * 60
const POSTS_PER_WINDOW = 60

async function readBoard(userId: string): Promise<{ revision: number; entries: Vouch[] }> {
  const row = await prisma.groupBoard.findUnique({ where: { userId } })
  return row ? { revision: row.revision, entries: parseBoard(row.entries) } : { revision: 0, entries: [] }
}

export async function groupBoardRoutes(app: FastifyInstance): Promise<void> {
  app.get<{ Querystring: { since?: string } }>('/api/group/board', async (req, reply) => {
    // Every device of the account asks this after every `group_changed`, and mostly nothing moved:
    // the revision is compared before any stored signature is checked again.
    const row = await prisma.groupBoard.findUnique({ where: { userId: req.user!.sub }, select: { revision: true } })
    const revision = row?.revision ?? 0
    const since = Number(req.query?.since)
    if (Number.isInteger(since) && since === revision) return sendSuccess(reply, { revision })
    return sendSuccess(reply, await readBoard(req.user!.sub))
  })

  app.post<{ Body: { entries?: unknown } }>('/api/group/board', async (req, reply) => {
    const userId = req.user!.sub
    const raw = req.body?.entries
    if (!Array.isArray(raw) || raw.length === 0 || raw.length > MAX_POST_ENTRIES) {
      return sendError(reply, `entries must be 1–${MAX_POST_ENTRIES} vouches`, 'BAD_REQUEST', 400)
    }
    const incoming = raw.map((v) => parseVouch(v))
    if (incoming.some((v) => v === null)) return sendError(reply, 'a vouch is malformed or its signature does not match', 'BAD_VOUCH', 400)
    if (!(await consumeRateLimit(`groupboard:${userId}`, POSTS_PER_WINDOW, RATE_WINDOW_SEC))) {
      return sendError(reply, 'too many group updates — wait a few minutes', 'RATE_LIMITED', 429)
    }
    for (let attempt = 0; attempt < WRITE_ATTEMPTS; attempt++) {
      const current = await readBoard(userId)
      const merged = mergeBoard(current.entries, incoming as Vouch[])
      if (!merged.changed) return sendSuccess(reply, { revision: current.revision, added: 0 })
      const next = current.revision + 1
      const entries = merged.entries as unknown as Prisma.InputJsonValue
      const bumped = await prisma.groupBoard.updateMany({ where: { userId, revision: current.revision }, data: { revision: next, entries } })
      if (bumped.count !== 1) {
        if (current.revision !== 0) continue
        try {
          await prisma.groupBoard.create({ data: { userId, revision: next, entries } })
        } catch (error) {
          if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002') continue
          throw error
        }
      }
      void publishGroupChanged(userId, { revision: next })
      return sendSuccess(reply, { revision: next, added: merged.added })
    }
    return sendError(reply, 'The group is changing too quickly; try again.', 'GROUP_BUSY', 409)
  })
}
