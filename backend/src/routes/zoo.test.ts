import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import Fastify, { type FastifyInstance } from 'fastify'
import { Prisma } from '@prisma/client'
const mocks = vi.hoisted(() => ({
  prisma: { zoo: { findUnique: vi.fn(), updateMany: vi.fn(), create: vi.fn() }, machine: { findMany: vi.fn() } },
  changed: vi.fn(), auth: vi.fn(),
}))
vi.mock('../lib/prisma.js', () => ({ prisma: mocks.prisma }))
vi.mock('../lib/bus.js', () => ({ publishZooChanged: mocks.changed }))
vi.mock('../lib/ssoAuth.js', async original => ({ ...await original<typeof import('../lib/ssoAuth.js')>(), authenticateAccessToken: mocks.auth }))
import { zooRoutes } from './zoo.js'
import { emptyZoo, type Zoo } from '../lib/zoo.js'
import { DAEMON_ROSTER } from '../lib/daemonRoster.g.js'
import { registerAuthMiddleware } from '../middlewares/authMiddleware.js'
import { errorHandler } from '../middlewares/errorHandler.js'

const user = { sub: 'u1', email: 'd@example.com', role: 'user', autonomousEnv: 'prod' as const }
const withHabits = (habits: string[]): Zoo => ({ ...emptyZoo(), habits })
const egg = { id: 'e1', kind: 'first', grantedAt: '2026-09-26T00:00:00.000Z' }

describe('zoo routes', () => {
  let app: FastifyInstance
  beforeEach(async () => {
    vi.resetAllMocks()
    mocks.auth.mockResolvedValue(user)
    mocks.changed.mockResolvedValue(1)
    app = Fastify(); app.setErrorHandler(errorHandler); registerAuthMiddleware(app, mocks.auth)
    await app.register(zooRoutes); await app.ready()
  })
  afterEach(async () => { await app.close() })
  const auth = { authorization: 'Bearer fixture' }
  const post = (ops: unknown) => app.inject({ method: 'POST', url: '/api/zoo/ops', headers: auth, payload: { ops } as any })

  it('answers an empty zoo for a user who has none', async () => {
    mocks.prisma.zoo.findUnique.mockResolvedValue(null)
    const res = await app.inject({ method: 'GET', url: '/api/zoo', headers: auth })
    expect(res.json()).toEqual({ success: true, data: { revision: 0, zoo: emptyZoo() } })
    expect(mocks.prisma.zoo.findUnique).toHaveBeenCalledWith({ where: { userId: 'u1' } })
  })

  it('serves a stored zoo with its malformed entries dropped', async () => {
    mocks.prisma.zoo.findUnique.mockResolvedValue({ revision: 4, state: { ...withHabits(['turn', 'bogus key']), eggs: [egg, { id: 'x' }], pity: 'lots' } })
    const res = await app.inject({ method: 'GET', url: '/api/zoo', headers: auth })
    expect(res.json().data).toEqual({ revision: 4, zoo: { ...withHabits(['turn']), eggs: [egg] } })
  })

  it('refuses a caller with no session, like the desk', async () => {
    const res = await app.inject({ method: 'GET', url: '/api/zoo' })
    expect(res.statusCode).toBe(401)
    expect(mocks.prisma.zoo.findUnique).not.toHaveBeenCalled()
  })

  it('creates the row on the first write and tells every adapter of the user', async () => {
    mocks.prisma.zoo.findUnique.mockResolvedValue(null)
    mocks.prisma.zoo.updateMany.mockResolvedValue({ count: 0 })
    mocks.prisma.zoo.create.mockResolvedValue({})
    const res = await post([{ op: 'zoo.habit', key: 'turn' }])
    expect(res.json().data).toEqual({ revision: 1, zoo: withHabits(['turn']), hatched: [], grants: [], levelUps: [] })
    expect(mocks.prisma.zoo.create).toHaveBeenCalledWith({ data: { userId: 'u1', revision: 1, state: withHabits(['turn']) } })
    expect(mocks.changed).toHaveBeenCalledWith('u1', { revision: 1 })
  })

  it('re-reads when another client created the row at the same moment', async () => {
    mocks.prisma.zoo.findUnique
      .mockResolvedValueOnce(null)
      .mockResolvedValueOnce({ revision: 1, state: withHabits(['split']) })
    mocks.prisma.zoo.updateMany
      .mockResolvedValueOnce({ count: 0 })
      .mockResolvedValueOnce({ count: 1 })
    mocks.prisma.zoo.create.mockRejectedValue(new Prisma.PrismaClientKnownRequestError('dup', { code: 'P2002', clientVersion: 'test' }))
    const res = await post([{ op: 'zoo.habit', key: 'turn' }])
    expect(res.json().data).toEqual({ revision: 2, zoo: withHabits(['split', 'turn']), hatched: [], grants: [], levelUps: [] })
    expect(mocks.prisma.zoo.updateMany).toHaveBeenLastCalledWith({ where: { userId: 'u1', revision: 1 }, data: { revision: 2, state: withHabits(['split', 'turn']) } })
  })

  it('bumps the revision with a compare-and-set, and replays on a lost race', async () => {
    // (No 'turn' among them: three habits with a finished turn would earn the first egg.)
    mocks.prisma.zoo.findUnique
      .mockResolvedValueOnce({ revision: 3, state: withHabits(['split']) })
      .mockResolvedValueOnce({ revision: 4, state: withHabits(['split', 'find']) })
    mocks.prisma.zoo.updateMany
      .mockResolvedValueOnce({ count: 0 })
      .mockResolvedValueOnce({ count: 1 })
    const res = await post([{ op: 'zoo.habit', key: 'store' }])
    expect(res.json().data).toEqual({ revision: 5, zoo: withHabits(['split', 'find', 'store']), hatched: [], grants: [], levelUps: [] })
    expect(mocks.prisma.zoo.create).not.toHaveBeenCalled()
    expect(mocks.changed).toHaveBeenCalledOnce()
  })

  it('hatches on the server and answers what came out', async () => {
    mocks.prisma.zoo.findUnique.mockResolvedValue({ revision: 2, state: { ...emptyZoo(), eggs: [egg] } })
    mocks.prisma.zoo.updateMany.mockResolvedValue({ count: 1 })
    const res = await post([{ op: 'zoo.hatch', eggId: 'e1' }])
    const data = res.json().data
    expect(data.revision).toBe(3)
    expect(data.hatched).toEqual([{ eggId: 'e1', daemonId: expect.any(String), shiny: expect.any(Boolean) }])
    expect(DAEMON_ROSTER.daemons.map((d) => d.id)).toContain(data.hatched[0].daemonId)
    expect(data.zoo).toMatchObject({ eggs: [], pair: data.hatched[0].daemonId, daemons: [{ id: data.hatched[0].daemonId, egg: 'first', bond: 0, version: '0.1' }] })
  })

  it('writes nothing, and says where the zoo is, when the ops change nothing', async () => {
    mocks.prisma.zoo.findUnique.mockResolvedValue({ revision: 7, state: withHabits(['turn']) })
    const res = await post([{ op: 'zoo.hatch', eggId: 'gone' }, { op: 'zoo.habit', key: 'turn' }, { op: 'zoo.easter', word: 'plugh' }])
    expect(res.json().data).toEqual({ revision: 7, zoo: withHabits(['turn']), hatched: [], grants: [], levelUps: [] })
    expect(mocks.prisma.zoo.updateMany).not.toHaveBeenCalled()
    expect(mocks.changed).not.toHaveBeenCalled()
  })

  it('refuses a malformed op, a nickname past 24 characters, and a client-sent result', async () => {
    mocks.prisma.zoo.findUnique.mockResolvedValue(null)
    expect((await post([{ op: 'zoo.explode' }])).statusCode).toBe(400)
    expect((await post([{ op: 'zoo.nickname', id: 'tim', nickname: 'x'.repeat(25) }])).statusCode).toBe(400)
    expect((await post([{ op: 'zoo.hatch', eggId: 'e1', daemonId: 'grue' }])).statusCode).toBe(400)
    expect((await post([])).statusCode).toBe(400)
    expect(mocks.prisma.zoo.findUnique).not.toHaveBeenCalled()
  })

  it('counts reported turns, asks which machines are the account\'s, and answers eggs and levels', async () => {
    vi.useFakeTimers({ toFake: ['Date'] })
    vi.setSystemTime(new Date('2026-09-26T12:00:00.000Z'))
    try {
      const tim = { id: 'tim', hatchedAt: '2026-09-01T00:00:00.000Z', egg: 'first', shiny: false, bond: 0, xp: 40, version: '0.1' }
      const progress = { turns: 39, machines: ['mac-1'] }
      mocks.prisma.zoo.findUnique.mockResolvedValue({ revision: 5, state: { ...emptyZoo(), daemons: [tim], pair: 'tim', progress } })
      mocks.prisma.zoo.updateMany.mockResolvedValue({ count: 1 })
      mocks.prisma.machine.findMany.mockResolvedValue([{ machineId: 'mac-1' }])
      const turn = (batchId: string, machineId: string) => ({ op: 'zoo.turn', batchId, n: 5, day: '2026-09-26', hour: 10, machineId })
      const res = await post([turn('b1', 'mac-1'), turn('b2', 'someone-elses')])
      expect(res.statusCode).toBe(200)
      expect(mocks.prisma.machine.findMany).toHaveBeenCalledWith({ where: { userId: 'u1', machineId: { in: ['mac-1', 'someone-elses'] } }, select: { machineId: true } })
      const data = res.json().data
      expect(data.grants).toEqual([{ kind: 'turn', eggId: expect.any(String) }])
      expect(data.levelUps).toEqual([{ id: 'tim', level: 1, version: '0.1' }])      // 40 + 5 + 10
      expect(data.zoo.daemons[0]).toMatchObject({ xp: 55, bond: 1 })
      expect(data.zoo.progress).toMatchObject({ turns: 49, machines: ['mac-1'], marathon: [], batches: ['b1', 'b2'] })
      expect(mocks.changed).toHaveBeenCalledWith('u1', { revision: 6 })
    } finally {
      vi.useRealTimers()
    }
  })

  it('never asks about machines when no turn is reported, and refuses an absurd report', async () => {
    mocks.prisma.zoo.findUnique.mockResolvedValue(null)
    mocks.prisma.zoo.updateMany.mockResolvedValue({ count: 0 })
    mocks.prisma.zoo.create.mockResolvedValue({})
    await post([{ op: 'zoo.habit', key: 'turn' }])
    expect(mocks.prisma.machine.findMany).not.toHaveBeenCalled()
    for (const bad of [{ n: 500 }, { n: 0 }, { hour: 24 }, { day: '2026-02-30' }, { day: 'today' }, { machineId: '' }]) {
      const res = await post([{ op: 'zoo.turn', batchId: 'b1', n: 1, day: '2026-09-26', hour: 1, machineId: 'm', ...bad }])
      expect(res.statusCode, JSON.stringify(bad)).toBe(400)
    }
    expect(mocks.prisma.machine.findMany).not.toHaveBeenCalled()
  })

  it('gives up after five lost races rather than spinning', async () => {
    mocks.prisma.zoo.findUnique.mockResolvedValue({ revision: 2, state: emptyZoo() })
    mocks.prisma.zoo.updateMany.mockResolvedValue({ count: 0 })
    const res = await post([{ op: 'zoo.habit', key: 'turn' }])
    expect(res.statusCode).toBe(409)
    expect(res.json().error.code).toBe('ZOO_BUSY')
    expect(mocks.prisma.zoo.updateMany).toHaveBeenCalledTimes(5)
    expect(mocks.changed).not.toHaveBeenCalled()
  })
})
