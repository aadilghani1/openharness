import { beforeEach, describe, expect, it, vi } from 'vitest'
import Fastify, { type FastifyInstance } from 'fastify'
import { ed25519 } from '@noble/curves/ed25519.js'
import { vouchMessage, parseVouch, mergeBoard, type VouchSubject } from '../lib/groupBoard.js'

// The board in memory; the route and lib/groupBoard.ts run for real.
const fakes = vi.hoisted(() => {
  let row: { userId: string; revision: number; entries: unknown } | null = null
  return {
    reset: () => { row = null },
    row: () => row,
    published: [] as Array<{ userId: string; revision: number }>,
    prisma: {
      groupBoard: {
        findUnique: vi.fn(async () => row),
        updateMany: vi.fn(async ({ where, data }: { where: { revision: number }; data: { revision: number; entries: unknown } }) => {
          if (!row || row.revision !== where.revision) return { count: 0 }
          row = { ...row, ...data }
          return { count: 1 }
        }),
        create: vi.fn(async ({ data }: { data: { userId: string; revision: number; entries: unknown } }) => { row = data; return data }),
      },
    },
  }
})

vi.mock('../lib/prisma.js', () => ({ prisma: fakes.prisma }))
vi.mock('../lib/bus.js', () => ({
  consumeRateLimit: vi.fn(async () => true),
  publishGroupChanged: vi.fn(async (userId: string, msg: { revision: number }) => { fakes.published.push({ userId, ...msg }); return 1 }),
}))

import { groupBoardRoutes } from './groupBoard.js'
import { registerAuthMiddleware } from '../middlewares/authMiddleware.js'
import { errorHandler } from '../middlewares/errorHandler.js'

const b64 = (b: Uint8Array): string => Buffer.from(b).toString('base64')
function member() {
  const priv = ed25519.utils.randomSecretKey()
  return { priv, pub: b64(ed25519.getPublicKey(priv)) }
}
function vouch(signer: { priv: Uint8Array; pub: string }, subject: VouchSubject) {
  return { subject, signer: signer.pub, sig: b64(ed25519.sign(vouchMessage(subject), signer.priv)) }
}

const phone = { authorization: 'Bearer phone' }
let app: FastifyInstance
beforeEach(async () => {
  fakes.reset(); fakes.published.length = 0; vi.clearAllMocks()
  app = Fastify()
  app.setErrorHandler(errorHandler)
  registerAuthMiddleware(app, async (token) => {
    if (token !== 'phone') throw Object.assign(new Error('no'), { code: 'INVALID_TOKEN' })
    return { sub: 'u1', email: 'dee@x.ai', role: 'user', autonomousEnv: 'prod' }
  })
  await app.register(groupBoardRoutes)
  await app.ready()
})

describe('a vouch', () => {
  it('is kept only when its signature matches its signer and the statement', () => {
    const p = member(), m = member()
    const good = vouch(p, { pub: m.pub, kind: 'machine', machineId: 'a'.repeat(32), label: 'box', at: 10 })
    expect(parseVouch(good)).not.toBeNull()
    expect(parseVouch({ ...good, subject: { ...good.subject, label: 'other' } })).toBeNull() // the statement changed
    expect(parseVouch({ ...good, signer: member().pub })).toBeNull()                        // another signer
    expect(parseVouch(vouch(p, { pub: m.pub, kind: 'machine', label: 'x', at: 10 }))).toBeNull() // a machine needs its id
    expect(parseVouch(vouch(p, { pub: m.pub, at: 11, removed: true }))).not.toBeNull()
  })

  it('merges once, newest first', () => {
    const p = member(), a = member(), b = member()
    const va = vouch(p, { pub: a.pub, kind: 'viewer', label: 'a', at: 5 })
    const vb = vouch(p, { pub: b.pub, kind: 'viewer', label: 'b', at: 9 })
    const once = mergeBoard([va], [va, vb])
    expect(once.added).toBe(1)
    expect(once.entries.map((v) => v.subject.pub)).toEqual([b.pub, a.pub])
    expect(mergeBoard(once.entries, [va]).changed).toBe(false)
  })

  it('keeps one word per signer per key: the newest, a removal winning a tie', () => {
    const p = member(), a = member()
    const v5 = vouch(p, { pub: a.pub, kind: 'viewer', label: 'a', at: 5 })
    const v9 = vouch(p, { pub: a.pub, kind: 'viewer', label: 'a2', at: 9 })
    const gone9 = vouch(p, { pub: a.pub, at: 9, removed: true })
    const board = mergeBoard([v5], [v9]).entries
    expect(board).toEqual([v9])
    expect(mergeBoard(board, [v5]).changed).toBe(false)
    expect(mergeBoard(board, [gone9]).entries).toEqual([gone9])
    expect(mergeBoard([gone9], [v9]).changed).toBe(false)
    // Another signer's word about the same key is its own.
    expect(mergeBoard(board, [vouch(member(), { pub: a.pub, kind: 'viewer', label: 'a', at: 1 })]).entries).toHaveLength(2)
  })
})

describe('the board routes', () => {
  it('stores signed vouches, bumps the revision, tells the account, and reads back', async () => {
    const p = member(), web = member()
    const v = vouch(p, { pub: web.pub, kind: 'viewer', label: 'Chrome on macOS', at: Date.now() })
    const posted = await app.inject({ method: 'POST', url: '/api/group/board', headers: phone, payload: { entries: [v] } })
    expect(posted.statusCode).toBe(200)
    expect(posted.json().data).toEqual({ revision: 1, added: 1 })
    expect(fakes.published).toEqual([{ userId: 'u1', revision: 1 }])

    const again = await app.inject({ method: 'POST', url: '/api/group/board', headers: phone, payload: { entries: [v] } })
    expect(again.json().data).toEqual({ revision: 1, added: 0 })
    expect(fakes.published).toHaveLength(1) // nothing new, nobody told

    const read = await app.inject({ method: 'GET', url: '/api/group/board', headers: phone })
    expect(read.json().data).toEqual({ revision: 1, entries: [v] })
    const unchanged = await app.inject({ method: 'GET', url: '/api/group/board?since=1', headers: phone })
    expect(unchanged.json().data).toEqual({ revision: 1 })
  })

  it('refuses a forged or malformed vouch, and an anonymous caller', async () => {
    const p = member(), web = member()
    const v = vouch(p, { pub: web.pub, kind: 'viewer', label: 'x', at: Date.now() })
    const forged = { ...v, subject: { ...v.subject, label: 'y' } }
    expect((await app.inject({ method: 'POST', url: '/api/group/board', headers: phone, payload: { entries: [forged] } })).statusCode).toBe(400)
    expect((await app.inject({ method: 'POST', url: '/api/group/board', headers: phone, payload: { entries: [] } })).statusCode).toBe(400)
    expect((await app.inject({ method: 'GET', url: '/api/group/board' })).statusCode).toBe(401)
    expect(fakes.row()).toBeNull()
  })
})
