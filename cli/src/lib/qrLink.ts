/**
 * `harness link qr`: this machine shows a QR, a phone that is already signed in scans it, and the two
 * run the same one-time-code CPace pairing the desktop's "Add phone" dialog uses — so no remote password.
 * The phone then carries this machine into its trust group (groupSyncer.ts), and this machine announces
 * the phone the moment the pairing lands (manager.ts `onPair` → `onPeerLinked`), so it reaches every
 * member, and they it, without anything else typed anywhere.
 *
 * Only the arming loop and the waiting live here, behind injected calls, so they can be tested without a
 * daemon. The code itself never leaves this machine except inside the QR: the relay carries CPace
 * messages, which a code it has never seen cannot be recovered from.
 */
import { randomInt } from 'crypto'

/** Same alphabet and length as the desktop's `newPhonePairCode` (add_phone_dialog.dart): no 0 O 1 I L U,
 *  so both sides' normalisers agree, 16 symbols of 30 — about 78 bits. */
export const PAIR_CODE_ALPHABET = 'ABCDEFGHJKMNPQRSTVWXYZ23456789'
export const PAIR_CODE_LENGTH = 16
export const PAIR_LINK_BASE = 'https://harness.autonomous.ai/pair'

/** A photographed QR should not stay good for long: a fresh code (and a redrawn QR) this often. */
const ROTATE_MS = 3 * 60_000
const REPOLL_MS = 1_500
const RATE_LIMITED_WAIT_MS = 60_000
/** After the phone links, how long to watch the group settle before reporting who this machine reaches. */
const SETTLE_MS = 10_000
const SYNC_WAIT_MS = 45_000
/** A group with no other machine yet (this phone's first) has nothing to wait for past this. */
const EMPTY_GROUP_WAIT_MS = 20_000

export function newPairCode(pick: (n: number) => number = (n) => randomInt(n)): string {
  let code = ''
  for (let i = 0; i < PAIR_CODE_LENGTH; i++) code += PAIR_CODE_ALPHABET[pick(PAIR_CODE_ALPHABET.length)]
  return code
}

/** The fingerprint as it travels in the QR: the separators dropped, so it stays plain ASCII. */
export function fingerprintParam(fingerprint: string): string {
  return fingerprint.toUpperCase().replace(/[^0-9A-Z]/g, '')
}

/** `https://harness.autonomous.ai/pair#…` — everything after `#`, so no server ever receives it. */
export function pairLink(p: { machineId: string; code: string; fingerprint: string; hostname: string; email?: string; signIn?: string; base?: string }): string {
  const q = new URLSearchParams({ m: p.machineId, c: p.code, f: fingerprintParam(p.fingerprint), n: p.hostname })
  if (p.email) q.set('e', p.email)
  // A phone that is not signed in yet (a browser, say) signs in with it: one scan, signed in and linked.
  if (p.signIn) q.set('h', p.signIn)
  return `${p.base ?? PAIR_LINK_BASE}#${q.toString()}`
}

/** The sign-in QR (`harness login`): `s` is the backend's sign-in request, `c` the E2EE pairing code
 *  the machine arms once signed in. No machine id yet — the approval is what binds one. */
export function signInLink(p: { userCode: string; code: string; fingerprint: string; hostname: string; base?: string }): string {
  const q = new URLSearchParams({ s: p.userCode, c: p.code, f: fingerprintParam(p.fingerprint), n: p.hostname })
  return `${p.base ?? PAIR_LINK_BASE}#${q.toString()}`
}

/** `${WEB_URL}/pair`: the web app a phone's camera opens the link in — the local one in development. */
export function pairLinkBase(webUrl: string): string {
  return `${webUrl.replace(/\/+$/, '')}/pair`
}

export interface GroupView { members: Array<{ kind: string; machineId?: string; label: string }> }

export interface QrLinkDeps {
  /** POST /api/pair {code} on the local daemon: long-polls through the handshake once a phone is waiting. */
  pair: (code: string) => Promise<{ status: number; body: Record<string, unknown> }>
  /** GET /api/group on the local daemon. */
  group: () => Promise<GroupView | null>
  /** Show (or redraw) the QR for this code — may first fetch what else the QR carries. */
  show: (code: string) => void | Promise<void>
  /** Progress for the person watching (and NDJSON). */
  note: (event: QrLinkEvent) => void
  sleep?: (ms: number) => Promise<void>
  now?: () => number
  mintCode?: () => string
  /** How often a fresh code (and QR) is drawn. Shorter when the QR also carries a sign-in code. */
  rotateMs?: number
}

export type QrLinkEvent =
  | { type: 'waiting' }
  | { type: 'mismatch' }
  | { type: 'rotated' }
  | { type: 'rate_limited'; retryInMs: number }
  | { type: 'linked'; label: string }
  | { type: 'syncing' }

export type QrLinkResult =
  | { ok: true; label: string; machines: Array<{ machineId: string; label: string }> }
  | { ok: false; error: string }

/** Arm the daemon with a code until a phone completes the pairing, then watch the group fill in. */
export async function runQrLink(deps: QrLinkDeps): Promise<QrLinkResult> {
  const sleep = deps.sleep ?? ((ms: number) => new Promise<void>((r) => setTimeout(r, ms)))
  const now = deps.now ?? (() => Date.now())
  const mint = deps.mintCode ?? (() => newPairCode())

  let code = mint()
  let shownAt = now()
  await deps.show(code)
  deps.note({ type: 'waiting' })

  let label: string | null = null
  while (!label) {
    if (now() - shownAt >= (deps.rotateMs ?? ROTATE_MS)) {
      code = mint(); shownAt = now()
      await deps.show(code)
      deps.note({ type: 'rotated' })
    }
    let answer: { status: number; body: Record<string, unknown> }
    try {
      answer = await deps.pair(code)
    } catch {
      return { ok: false, error: 'DAEMON_UNREACHABLE' }
    }
    const error = typeof answer.body.error === 'string' ? answer.body.error : null
    if (answer.status === 200 && !error) {
      label = typeof answer.body.label === 'string' && answer.body.label ? answer.body.label : 'your phone'
      break
    }
    switch (error) {
      case 'NO_INTENT':
      case 'EXPIRED':
      case 'BUSY':
      case 'TIMEOUT':
      case 'BACKEND_DOWN':
        await sleep(REPOLL_MS)
        continue
      case 'CODE_MISMATCH':
        // Someone scanned a stale QR, or guessed: this code is spent either way.
        code = mint(); shownAt = now()
        await deps.show(code)
        deps.note({ type: 'mismatch' })
        continue
      case 'RATE_LIMITED':
        deps.note({ type: 'rate_limited', retryInMs: RATE_LIMITED_WAIT_MS })
        await sleep(RATE_LIMITED_WAIT_MS)
        continue
      default:
        return { ok: false, error: error ?? `HTTP_${answer.status}` }
    }
  }

  deps.note({ type: 'linked', label })
  deps.note({ type: 'syncing' })
  // The phone pushes this machine to the rest of the group and the group answers; report once the list
  // of machines stops growing (or the wait runs out — whoever is offline catches up on their own).
  const started = now()
  let machines: Array<{ machineId: string; label: string }> = []
  let changedAt = now()
  while (now() - started < SYNC_WAIT_MS) {
    const view = await deps.group().catch(() => null)
    const next = (view?.members ?? [])
      .filter((m) => m.kind === 'machine' && typeof m.machineId === 'string')
      .map((m) => ({ machineId: m.machineId as string, label: m.label }))
    if (next.length !== machines.length) { machines = next; changedAt = now() }
    if (machines.length > 0 && now() - changedAt >= SETTLE_MS) break
    if (machines.length === 0 && now() - started >= EMPTY_GROUP_WAIT_MS) break
    await sleep(REPOLL_MS)
  }
  return { ok: true, label, machines }
}
