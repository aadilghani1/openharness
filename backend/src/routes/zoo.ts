/**
 * The account's zoo — its daemons and eggs, the same on every client (lib/zoo.ts for the rules,
 * daemons/README.md for the contract).
 *
 *   GET  /api/zoo       → { revision, zoo }
 *   POST /api/zoo/ops   → { ops } applied in order under `revision`, answers { revision, zoo, hatched }
 *
 * The desk's write discipline (routes/desk.ts), on its own document: a write that lost a race is
 * retried from the fresh zoo, since the ops are idempotent and drop-on-missing. A hatch that lost the
 * race draws again against the fresh zoo; only the draw that was written is answered. After a change
 * every adapter socket of the user hears `zoo_changed` (lib/adapterAccountPushes.ts) and re-fetches.
 */
import type { FastifyInstance } from 'fastify'
import { Prisma } from '@prisma/client'
import type { z } from 'zod'
import { prisma } from '../lib/prisma.js'
import { publishZooChanged } from '../lib/bus.js'
import { applyZooOps, emptyZoo, parseZoo, zooOpsBodySchema, type ZooDoc } from '../lib/zoo.js'
import { validateBody } from '../middlewares/validation.js'
import { sendError, sendSuccess } from '../utils/response.js'

const WRITE_ATTEMPTS = 5

async function readZoo(userId: string): Promise<ZooDoc> {
  const row = await prisma.zoo.findUnique({ where: { userId } })
  return row ? { revision: row.revision, zoo: parseZoo(row.state) } : { revision: 0, zoo: emptyZoo() }
}

export async function zooRoutes(app: FastifyInstance): Promise<void> {
  app.get('/api/zoo', async (req, reply) => {
    sendSuccess(reply, await readZoo(req.user!.sub))
  })

  app.post<{ Body: z.infer<typeof zooOpsBodySchema> }>(
    '/api/zoo/ops', { preHandler: [validateBody(zooOpsBodySchema)] },
    async (req, reply) => {
      const userId = req.user!.sub
      for (let attempt = 0; attempt < WRITE_ATTEMPTS; attempt++) {
        const current = await readZoo(userId)
        const applied = applyZooOps(current.zoo, req.body.ops)
        // Nothing moved — the same request twice, or ops on eggs already hatched. Say where we are.
        if (!applied.changed) return sendSuccess(reply, { ...current, hatched: [] })
        const next = { revision: current.revision + 1, zoo: applied.zoo }
        const state = next.zoo as unknown as Prisma.InputJsonValue
        // Compare-and-set on the revision: whoever wrote first wins, the other re-reads and replays.
        const bumped = await prisma.zoo.updateMany({ where: { userId, revision: current.revision }, data: { revision: next.revision, state } })
        if (bumped.count !== 1) {
          if (current.revision !== 0) continue
          // No row yet (the only way revision 0 and no update): make it. A second client making it at
          // the same moment trips the unique index and re-reads what the first one wrote.
          try {
            await prisma.zoo.create({ data: { userId, revision: next.revision, state } })
          } catch (error) {
            if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002') continue
            throw error
          }
        }
        void publishZooChanged(userId, { revision: next.revision })
        return sendSuccess(reply, { ...next, hatched: applied.hatched })
      }
      return sendError(reply, 'The zoo is changing too quickly; try again.', 'ZOO_BUSY', 409)
    },
  )
}
