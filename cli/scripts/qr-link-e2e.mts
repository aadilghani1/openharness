// Stands in for a phone scanning a machine's QR (`harness link qr`, or the desktop's Add Phone): the same
// wire the Harness app speaks — the one-time-code pairing with `kind`/`label` sealed beside its identity,
// the fingerprint in the QR checked against the key it pins, then the trust-group roster swap with the
// machine and with every other machine it has pinned (`AppNotifier.connectWithCode` → `_syncGroup`).
//
//   npx tsx scripts/qr-link-e2e.mts link '<https://harness.autonomous.ai/pair#m=…&c=…&f=…>'
//   npx tsx scripts/qr-link-e2e.mts sync          # swap rosters with every pinned machine again
//   npx tsx scripts/qr-link-e2e.mts show          # what this "phone" has pinned
//
// The phone's identity and pins live in $PHONE_STATE (default: a file in the OS temp dir), so several
// scans in a row are one phone. It signs in to the relay with THIS computer's session, so it is on the
// same account. Nothing is written anywhere else.
import WebSocket from 'ws'
import { readFileSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import * as C from '../src/lib/e2ee/core.ts'
import { RelaySessionCrypto } from '../src/lib/e2ee/relayClient.ts'
import { AuthSessionManager, readAuthSession } from '../src/lib/authSession.ts'
import { env } from '../src/config/env.ts'

type Frame = Record<string, unknown>
interface PhoneState { seed: { priv: string; pub: string }; pins: Record<string, string> }

const STATE_FILE = process.env.PHONE_STATE ?? join(tmpdir(), 'harness-e2e-phone.json')
const LABEL = process.env.PHONE_LABEL ?? 'E2E phone'
const log = (m: string): void => console.log(`[phone] ${m}`)
const fail = (m: string): never => { console.error(`[phone] FAIL ${m}`); process.exit(1) }

function load(): PhoneState {
  try { return JSON.parse(readFileSync(STATE_FILE, 'utf8')) as PhoneState } catch {
    const id = C.newIdentity()
    return { seed: { priv: C.b64e(id.priv), pub: C.b64e(id.pub) }, pins: {} }
  }
}
const state = load()
const save = (): void => writeFileSync(STATE_FILE, JSON.stringify(state, null, 2), { mode: 0o600 })
save() // a new phone keeps its identity from its first run
const identity: C.Identity = { priv: C.b64d(state.seed.priv), pub: C.b64d(state.seed.pub) }
const plain = (fp: string): string => fp.toUpperCase().replace(/[^0-9A-Z]/g, '')

async function relay(machineId: string): Promise<{ ws: WebSocket; next: (want: (f: Frame) => boolean, ms?: number) => Promise<Frame>; send: (f: Frame) => void }> {
  const session = readAuthSession() ?? fail('this computer is not signed in (harness login)')
  const httpBase = env.BACKEND_WS_URL.replace(/\/$/, '').replace(/^wss:/, 'https:').replace(/^ws:/, 'http:')
  const token = await new AuthSessionManager(httpBase).accessToken()
  const ws = new WebSocket(`${env.BACKEND_WS_URL.replace(/\/$/, '')}/api/web-ws?autonomousEnv=${session.autonomousEnv}`, [token])
  const inbox: Frame[] = []
  const waiters: Array<{ want: (f: Frame) => boolean; resolve: (f: Frame) => void }> = []
  ws.on('message', (raw, bin) => {
    if (bin) return
    const f = JSON.parse(raw.toString()) as Frame
    const w = waiters.find((x) => x.want(f))
    if (w) { waiters.splice(waiters.indexOf(w), 1); w.resolve(f) } else inbox.push(f)
  })
  await new Promise<void>((resolve, reject) => { ws.once('open', () => resolve()); ws.once('error', reject) })
  const send = (f: Frame): void => ws.send(JSON.stringify(f))
  const next = (want: (f: Frame) => boolean, ms = 30_000): Promise<Frame> => new Promise((resolve, reject) => {
    const hit = inbox.findIndex(want)
    if (hit >= 0) { resolve(inbox.splice(hit, 1)[0]); return }
    const t = setTimeout(() => reject(new Error('timeout')), ms)
    waiters.push({ want, resolve: (f) => { clearTimeout(t); resolve(f) } })
  })
  send({ type: 'machine_select', payload: { machineId } })
  const sel = await next((f) => (f.type === 'connected' || f.type === 'machine_select_error'))
  if (sel.type !== 'connected') fail(`select ${machineId}: ${JSON.stringify(sel.payload)}`)
  return { ws, next, send }
}

/** The one-time-code pairing, joiner side — mobile/lib/viewer/code_link.dart. Returns the pinned key. */
async function pairByCode(machineId: string, code: string): Promise<Uint8Array> {
  const { ws, next, send } = await relay(machineId)
  const pairId = C.newPairId(), pairIdB64 = C.b64e(pairId), requestId = C.b64e(C.newPairId())
  const ci = C.pairContext(machineId, 'web')
  send({ type: 'e2e_pair_intent', payload: { requestId, pairId: pairIdB64, label: LABEL, role: 'web' } })
  const intent = await next((f) => f.type === 'e2e_pair_intent_result')
  const ip = intent.payload as Record<string, unknown>
  if (ip.accepted !== true) fail(`intent refused: ${JSON.stringify(ip)}`)
  log('intent accepted — waiting for the machine (its QR must be on screen)')
  const pake = (round: number) => next((f) => f.type === 'e2e_pake' && (f.payload as Frame).pairId === pairIdB64 && Number((f.payload as Frame).round) === round, 60_000)
  const r1 = (await pake(1)).payload as Record<string, unknown>
  const { y, Y } = C.cpaceStart(C.cpaceGenerator(C.normalizeCode(code), pairId, ci))
  const Ya = C.b64d(String(r1.ya))
  const isk = C.cpaceISK(pairId, C.cpaceShared(Ya, y), Ya, Y)
  const th = C.transcriptHash(pairId, ci, Ya, Y)
  const kc = C.kcKeys(isk, ci)
  send({ type: 'e2e_pake', payload: { pairId: pairIdB64, round: 2, yb: C.b64e(Y), mac: C.b64e(C.macTag(kc.web, th)) } })
  const r3 = (await pake(3)).payload as Record<string, unknown>
  if (r3.error) fail(`round 3: ${r3.error}`)
  if (!C.macVerify(kc.adapter, th, C.b64d(String(r3.mac)))) fail('machine MAC did not verify (wrong code)')
  const opened = C.aeadOpen(C.pairKey(isk, ci), 3, C.utf8('e2e-id'), C.b64d(String(r3.enc))) ?? fail('round 3 did not open')
  const claim = JSON.parse(new TextDecoder().decode(opened)) as { id: string; sig: string }
  const machinePub = C.b64d(claim.id)
  if (!C.pairBindVerify(machinePub, th, C.b64d(claim.sig))) fail('machine identity not bound to the transcript')
  const ours = { id: C.b64e(identity.pub), sig: C.b64e(C.pairBindSig(identity.priv, th)), label: LABEL, kind: 'viewer' }
  send({ type: 'e2e_pake', payload: { pairId: pairIdB64, round: 4, enc: C.b64e(C.aeadSeal(C.pairKey(isk, ci), 4, C.utf8('e2e-id'), C.utf8(JSON.stringify(ours)))) } })
  const r5 = (await pake(5)).payload as Record<string, unknown>
  ws.close()
  if (r5.ok !== true) fail(`round 5: ${JSON.stringify(r5)}`)
  return machinePub
}

/** One roster swap over a sealed session — mobile/lib/viewer/group_sync.dart. */
async function groupSync(machineId: string): Promise<boolean> {
  const pin = state.pins[machineId]
  if (!pin) return false
  let conn
  try { conn = await relay(machineId) } catch (e) { log(`${machineId.slice(0, 8)}: unreachable (${(e as Error).message})`); return false }
  const { ws, next, send } = conn
  const crypto = new RelaySessionCrypto({ machineId, selfIdentity: identity, peerPub: C.b64d(pin) })
  send(crypto.helloFrame())
  const answer = await next((f) => f.type === 'e2e_welcome' || f.type === 'e2e_denied').catch(() => null)
  if (!answer || answer.type !== 'e2e_welcome' || !crypto.handleWelcome(answer.payload as Record<string, unknown>)) {
    ws.close(); log(`${machineId.slice(0, 8)}: session refused (${answer?.type ?? 'no answer'})`); return false
  }
  const requestId = `gs-${Date.now()}`
  const members = Object.entries(state.pins).map(([id, pub]) => ({ pub, machineId: id, kind: 'machine', label: id, at: Date.now() - 1000 }))
  send(crypto.wrapOutgoing({ type: 'group_sync', payload: { requestId, self: { pub: C.b64e(identity.pub), kind: 'viewer', label: LABEL, at: 1 }, members, removed: [] } }))
  const reply = await next((f) => f.type === 'group_sync_result').catch(() => null)
  ws.close()
  const opened = reply ? crypto.unwrapIncoming(reply) : null
  const body = (opened?.payload ?? {}) as Record<string, unknown>
  if (!opened || body.error) { log(`${machineId.slice(0, 8)}: group_sync ${String(body.error ?? 'no reply')}`); return false }
  let learned = 0
  for (const m of [...((body.members as Frame[]) ?? []), body.self as Frame]) {
    if (m?.kind === 'machine' && typeof m.machineId === 'string' && typeof m.pub === 'string' && !state.pins[m.machineId]) {
      state.pins[m.machineId] = m.pub; learned++
    }
  }
  save()
  log(`${machineId.slice(0, 8)}: roster swapped${learned ? `, learned ${learned} machine(s)` : ''}`)
  return true
}

async function syncAll(first?: string): Promise<void> {
  if (first) await groupSync(first)
  for (const id of Object.keys(state.pins)) if (id !== first) await groupSync(id)
}

const [cmd, arg] = process.argv.slice(2)
if (cmd === 'link') {
  const url = new URL(arg ?? fail('usage: link <pair-url>'))
  const q = new URLSearchParams(url.hash.slice(1))
  const machineId = q.get('m') ?? fail('no m'), code = q.get('c') ?? fail('no c'), f = q.get('f')
  log(`scanned ${q.get('n') ?? machineId} — approving`)
  const pub = await pairByCode(machineId, code)
  if (f && plain(C.fingerprint(pub)) !== plain(f)) fail(`fingerprint mismatch: QR ${f}, machine ${C.fingerprint(pub)} — not pinned`)
  state.pins[machineId] = C.b64e(pub); save()
  log(`linked ${machineId.slice(0, 8)} · fingerprint ${C.fingerprint(pub)} ${f ? '(matches the QR)' : ''}`)
  await syncAll(machineId)
  log('done')
} else if (cmd === 'sync') {
  await syncAll(); log('done')
} else if (cmd === 'show') {
  console.log(JSON.stringify({ phone: C.fingerprint(identity.pub), pins: Object.keys(state.pins) }, null, 2))
} else fail('usage: link <url> | sync | show')
process.exit(0)
