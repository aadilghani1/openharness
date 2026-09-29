/**
 * The account's trust-group board, device side: signed statements ("vouches") about who is in the group,
 * kept by the backend (`backend/src/lib/groupBoard.ts`) so a device can learn a member it has no machine
 * in common with — the case the relay-only roster swap (groupSyncer.ts) cannot reach: a browser approved
 * by a phone that had no machine yet, then a machine approved by that same phone.
 *
 *   vouch = { subject, signer, sig }
 *   subject = { pub, kind, machineId?, label, at }  a member,  or  { pub, at, removed: true }  a removal
 *   sig = ed25519(signer, lvCat('group-vouch-v1', pub, kind | 'removed', machineId | '', label | '', at))
 *
 * Byte for byte what the apps' `viewer/group_sync.dart` signs; `groupBoard.spec.ts` and the Dart suite
 * pin one vector between them.
 *
 * TRUST lives here, not on the server: a vouch counts only when its signer is already a member of this
 * device's roster (or this device), and that grows to a fixpoint — a member accepted this round may vouch
 * for the next. The server, holding no member's key, cannot add anyone; replays and withheld entries are
 * what the roster's own merge (newest wins, a removal at or after an entry beats it) already absorbs.
 */
import { b64d, b64e, lvCat, sign, verify } from './core.js'
import { parseMember, type GroupMember, type GroupTombstone, type Roster } from './trustGroup.js'

export interface VouchSubject {
  pub: string
  kind?: 'machine' | 'viewer'
  machineId?: string
  label?: string
  at: number
  removed?: true
}

export interface Vouch {
  subject: VouchSubject
  signer: string
  sig: string
}

export function vouchMessage(subject: VouchSubject): Uint8Array {
  return lvCat(
    'group-vouch-v1',
    subject.pub,
    subject.removed ? 'removed' : (subject.kind ?? ''),
    subject.machineId ?? '',
    subject.label ?? '',
    String(subject.at),
  )
}

/** A vouch for [member] (or its removal), signed by this device's identity. */
export function signVouch(identity: { priv: Uint8Array; pub: Uint8Array }, subject: VouchSubject): Vouch {
  return { subject, signer: b64e(identity.pub), sig: b64e(sign(identity.priv, vouchMessage(subject))) }
}

export function memberSubject(m: GroupMember): VouchSubject {
  return { pub: m.pub, kind: m.kind, ...(m.machineId ? { machineId: m.machineId } : {}), label: m.label, at: m.at }
}

function verifyVouch(v: Vouch): boolean {
  try {
    const signer = b64d(v.signer), sig = b64d(v.sig)
    return signer.length === 32 && sig.length === 64 && verify(signer, vouchMessage(v.subject), sig)
  } catch {
    return false
  }
}

/** Well-formed entries of a board as the backend answered it; anything else is dropped. */
export function parseBoardEntries(raw: unknown): Vouch[] {
  if (!Array.isArray(raw)) return []
  const out: Vouch[] = []
  for (const v of raw) {
    if (!v || typeof v !== 'object') continue
    const { subject, signer, sig } = v as Record<string, unknown>
    if (!subject || typeof subject !== 'object' || typeof signer !== 'string' || typeof sig !== 'string') continue
    const s = subject as Record<string, unknown>
    if (typeof s.pub !== 'string' || typeof s.at !== 'number') continue
    out.push({
      subject: s.removed === true
        ? { pub: s.pub, at: s.at, removed: true }
        : { pub: s.pub, kind: s.kind as VouchSubject['kind'], ...(typeof s.machineId === 'string' ? { machineId: s.machineId } : {}), label: typeof s.label === 'string' ? s.label : '', at: s.at },
      signer,
      sig,
    })
  }
  return out
}

/**
 * The part of [entries] this device believes, as a roster to merge: members and removals whose signer it
 * already trusts — its roster's members and itself — growing to a fixpoint. A key the group removed
 * (a tombstone at or after its entry) vouches for nobody.
 */
export function acceptVouches(local: Roster, selfPub: string, entries: Vouch[], now = Date.now()): Roster {
  const removedAt = new Map(local.removed.map((t) => [t.pub, t.at]))
  const trusted = new Set<string>([selfPub, ...local.members.map((m) => m.pub)])
  const members: GroupMember[] = []
  const removed: GroupTombstone[] = []
  const pending = entries.filter((v) => v.signer !== v.subject.pub || v.signer === selfPub)
  // A self-vouch proves only that a key can sign; it is carried for others, never believed on its own.
  let progressed = true
  const done = new Set<Vouch>()
  while (progressed) {
    progressed = false
    for (const v of pending) {
      if (done.has(v) || !trusted.has(v.signer)) continue
      done.add(v)
      if (!verifyVouch(v)) continue
      if (v.subject.removed) {
        removed.push({ pub: v.subject.pub, at: v.subject.at })
        continue
      }
      const member = parseMember(v.subject, now)
      if (!member) continue
      // Removed at or after this statement: it may still merge (the roster's rules decide), but a key
      // the group took back vouches for nobody.
      const tomb = removedAt.get(member.pub)
      members.push(member)
      if (tomb !== undefined && tomb >= member.at) continue
      trusted.add(member.pub)
      progressed = true
    }
  }
  return { members, removed }
}
