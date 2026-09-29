import { describe, it, expect, beforeAll } from 'vitest'
import { mkdtempSync } from 'fs'
import { tmpdir } from 'os'
import { join } from 'path'
import { ed25519 } from '@noble/curves/ed25519'

// ADAPTER_DATA_DIR before config/env.js loads (see manager.test.ts); every store here is in memory.
let C: typeof import('./core.js')
let B: typeof import('./groupBoard.js')
let G: typeof import('./trustGroup.js')
let S: typeof import('./groupSyncer.js')

beforeAll(async () => {
  process.env.ADAPTER_DATA_DIR = mkdtempSync(join(tmpdir(), 'e2ee-groupboard-'))
  C = await import('./core.js')
  B = await import('./groupBoard.js')
  G = await import('./trustGroup.js')
  S = await import('./groupSyncer.js')
})

// Pinned with the apps' `viewer/group_sync.dart` (desktop test/viewer/group_sync_test.dart): the same
// statement, signed by the same key, is the same bytes on both sides.
const SEED = Uint8Array.from({ length: 32 }, (_, i) => i + 1)
const VECTOR = {
  subject: { pub: 'ZGVmZ2hpamtsbW5vcHFyc3R1dnd4eXp7fH1+f4CBgoM=', kind: 'machine', machineId: 'a'.repeat(32), label: 'studio', at: 1700000000000 },
  signer: 'ebVWLo/mVPlAeLES6KmLp5AfhTrmlb7X4OORC60ElmQ=',
  sig: 'vAhKE9/5zgVV7fU9V6NiT8dqPlFjVgI6xRSzAxCCxQh+gsL9hlzJ51ozgyZe2PNOQi8hKfagAWJgQzQxsmM5Dg==',
} as const

const identity = () => { const priv = C.newIdentity().priv; return { priv, pub: ed25519.getPublicKey(priv) } }
const b64 = (u: Uint8Array) => C.b64e(u)

describe('the group board', () => {
  it('signs the statement the phones sign', () => {
    const v = B.signVouch({ priv: SEED, pub: ed25519.getPublicKey(SEED) }, { ...VECTOR.subject })
    expect(v).toEqual(VECTOR)
  })

  it('believes only what a trusted member signed, and grows from there', () => {
    const me = identity(), phone = identity(), web = identity(), app = identity(), stranger = identity()
    const local = { members: [{ pub: b64(phone.pub), kind: 'viewer' as const, label: 'phone', at: 5 }], removed: [] }
    const entries = [
      // The phone vouches for the browser; the browser (now trusted) vouches for a machine.
      B.signVouch(phone, { pub: b64(web.pub), kind: 'viewer', label: 'web1', at: 10 }),
      B.signVouch(web, { pub: b64(app.pub), kind: 'machine', machineId: 'b'.repeat(32), label: 'app1', at: 11 }),
      // A key nobody trusts vouches for itself, and for another.
      B.signVouch(stranger, { pub: b64(stranger.pub), kind: 'viewer', label: 'me!', at: 12 }),
      B.signVouch(stranger, { pub: b64(identity().pub), kind: 'viewer', label: 'friend', at: 12 }),
      // A trusted signer, but the statement was changed after signing.
      { ...B.signVouch(phone, { pub: b64(identity().pub), kind: 'viewer', label: 'x', at: 13 }), subject: { pub: b64(identity().pub), kind: 'viewer' as const, label: 'x', at: 13 } },
    ]
    const accepted = B.acceptVouches(local, b64(me.pub), entries, 100)
    expect(accepted.members.map((m) => m.label).sort()).toEqual(['app1', 'web1'])
    expect(accepted.removed).toEqual([])
  })

  it('carries removals signed by a member, and a removed key vouches for nobody', () => {
    const me = identity(), phone = identity(), gone = identity()
    const local = {
      members: [{ pub: b64(phone.pub), kind: 'viewer' as const, label: 'phone', at: 5 }],
      removed: [{ pub: b64(gone.pub), at: 20 }],
    }
    const entries = [
      B.signVouch(phone, { pub: b64(gone.pub), at: 30, removed: true }),
      B.signVouch(gone, { pub: b64(identity().pub), kind: 'viewer', label: 'sneak', at: 31 }),
    ]
    const accepted = B.acceptVouches(local, b64(me.pub), entries, 100)
    expect(accepted.removed).toEqual([{ pub: b64(gone.pub), at: 30 }])
    expect(accepted.members).toEqual([])
  })

  it('a machine adopts the board: the member arrives, is trusted, and a read asked for during one runs once more after it, never alongside', async () => {
    const me = identity(), phone = identity(), web = identity()
    const store = new (class extends G.TrustGroupStore {
      roster: import('./trustGroup.js').Roster = { members: [{ pub: b64(phone.pub), kind: 'viewer', label: 'phone', at: 5 }], removed: [] }
      override read() { return JSON.parse(JSON.stringify(this.roster)) }
      override write(r: import('./trustGroup.js').Roster) { this.roster = JSON.parse(JSON.stringify(r)) }
      override blocked() { return new Set<string>() }
    })()
    const trusted: string[] = []
    let reads = 0, inFlight = 0, overlapped = false
    const posted: unknown[] = []
    const syncer = new S.GroupSyncer({
      store,
      peers: { get: () => null, pin: () => {}, unlink: () => false, list: () => [] } as unknown as import('./machinePeers.js').MachinePeerStore,
      self: () => ({ pub: b64(me.pub), kind: 'machine', label: 'me', at: S.SELF_STAMP, machineId: 'c'.repeat(32) }),
      trust: (p) => { trusted.push(p.pub) },
      untrust: () => {},
      paired: () => [],
      request: async () => null,
      board: {
        read: async (since) => {
          reads++
          if (++inFlight > 1) overlapped = true
          await new Promise((r) => setTimeout(r, 0))
          inFlight--
          return since === 1 ? { revision: 1 } : { revision: 1, entries: [B.signVouch(phone, { pub: b64(web.pub), kind: 'viewer', label: 'web1', at: 10 })] }
        },
        post: async (e) => { posted.push(...e); return true },
      },
      sign: (subject) => B.signVouch(me, subject),
    })
    const [a, b] = [syncer.adoptBoard(), syncer.adoptBoard()]
    expect(await a).toBe(true)
    expect(await b).toBe(true) // joined, and read once more (it may carry what the first read saw too early)
    expect(reads).toBe(2)
    expect(overlapped).toBe(false)
    expect(trusted).toContain(b64(web.pub))
    expect(store.read().members.map((m: { label: string }) => m.label)).toContain('web1')
    // Unchanged since revision 1: nothing re-applied.
    expect(await syncer.adoptBoard()).toBe(false)
    // Removing a member puts a signed tombstone on the board.
    syncer.remove(b64(web.pub))
    await new Promise((r) => setTimeout(r, 0))
    expect(posted).toHaveLength(1)
    expect((posted[0] as { subject: { removed?: boolean } }).subject.removed).toBe(true)
    syncer.stop()
  })
})
