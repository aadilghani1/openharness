/**
 * The account's trust-group board: signed statements ("vouches") about who is in the group, kept here
 * so a device can learn a member it has no machine in common with — a browser approved by a phone that
 * had no machine yet, then a machine approved by that same phone.
 *
 *   vouch = { subject, signer, sig }
 *   subject = { pub, kind: 'machine' | 'viewer', machineId?, label, at }   a member
 *           | { pub, at, removed: true }                                   a removal
 *   sig = ed25519(signer, lvCat('group-vouch-v1', pub, kind | 'removed', machineId | '', label | '', at))
 *
 * The same statement, byte for byte, as the CLI's `lib/e2ee/groupBoard.ts` and the apps'
 * `viewer/group_sync.dart` sign and check.
 *
 * ⚠️ This server does NOT decide trust. It checks only that a signature is well formed and matches
 * its `signer` — so garbage never takes a slot — and every device then believes only vouches signed by
 * a key it already trusts. Holding no member's private key, the server cannot add anyone; it can only
 * withhold or replay what members wrote, which the group's own merge rules (newest wins, a removal at
 * or after an entry beats it) already handle.
 */
import { ed25519 } from '@noble/curves/ed25519.js'

export const MAX_BOARD_ENTRIES = 256
export const MAX_POST_ENTRIES = 32
const MAX_LABEL = 60
const MAX_CLOCK_SKEW_MS = 24 * 60 * 60 * 1000

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

/** Standard base64 of exactly [length] bytes, or null. */
function bytesOf(value: unknown, length: number): Uint8Array | null {
  if (typeof value !== 'string' || value.length > 128) return null
  const bytes = Buffer.from(value, 'base64')
  if (bytes.length !== length || bytes.toString('base64') !== value) return null
  return new Uint8Array(bytes)
}

/** core.ts `lvCat`: each part as a 4-byte big-endian length, then its UTF-8 bytes. */
function lvCat(parts: string[]): Uint8Array {
  const encoded = parts.map((p) => Buffer.from(p, 'utf8'))
  const out = Buffer.alloc(encoded.reduce((n, b) => n + 4 + b.length, 0))
  let at = 0
  for (const b of encoded) {
    out.writeUInt32BE(b.length, at)
    b.copy(out, at + 4)
    at += 4 + b.length
  }
  return new Uint8Array(out)
}

/** The bytes a vouch's signature covers. */
export function vouchMessage(subject: VouchSubject): Uint8Array {
  return lvCat([
    'group-vouch-v1',
    subject.pub,
    subject.removed ? 'removed' : (subject.kind ?? ''),
    subject.machineId ?? '',
    subject.label ?? '',
    String(subject.at),
  ])
}

/** A well-formed vouch whose signature matches its signer, or null. */
export function parseVouch(raw: unknown, now = Date.now()): Vouch | null {
  if (!raw || typeof raw !== 'object') return null
  const { subject, signer, sig } = raw as Record<string, unknown>
  if (!subject || typeof subject !== 'object') return null
  const s = subject as Record<string, unknown>
  if (!bytesOf(s.pub, 32)) return null
  const at = s.at
  if (typeof at !== 'number' || !Number.isSafeInteger(at) || at <= 0 || at > now + MAX_CLOCK_SKEW_MS) return null
  let clean: VouchSubject
  if (s.removed === true) {
    clean = { pub: s.pub as string, at, removed: true }
  } else {
    if (s.kind !== 'machine' && s.kind !== 'viewer') return null
    const label = typeof s.label === 'string' ? s.label : ''
    if (label.length > MAX_LABEL) return null
    const machineId = s.machineId
    if (s.kind === 'machine' && (typeof machineId !== 'string' || !/^[a-f0-9]{32}$/.test(machineId))) return null
    clean = {
      pub: s.pub as string,
      kind: s.kind,
      ...(s.kind === 'machine' ? { machineId: machineId as string } : {}),
      label,
      at,
    }
  }
  const signerKey = bytesOf(signer, 32)
  const signature = bytesOf(sig, 64)
  if (!signerKey || !signature) return null
  try {
    if (!ed25519.verify(signature, vouchMessage(clean), signerKey)) return null
  } catch {
    return null
  }
  return { subject: clean, signer: signer as string, sig: sig as string }
}

/** One statement per signer per member: a signer's newer word about a key (re-added, removed, renamed)
 *  replaces its older one — the roster's own rule, newest wins — so repeated approvals do not crowd
 *  other members off the capped board. */
const keyOf = (v: Vouch): string => `${v.signer}|${v.subject.pub}`

/** The board after [incoming]: a statement newer than the same signer's last word about that key
 *  replaces it, anything else is dropped; newest first, capped. `added` counts what took a place. */
export function mergeBoard(current: Vouch[], incoming: Vouch[]): { entries: Vouch[]; changed: boolean; added: number } {
  const seen = new Map(current.map((v) => [keyOf(v), v]))
  let added = 0
  for (const v of incoming) {
    const key = keyOf(v)
    const had = seen.get(key)
    // Same stamp: the removal wins, as in the roster.
    if (had && (had.subject.at > v.subject.at || (had.subject.at === v.subject.at && (had.subject.removed || !v.subject.removed)))) continue
    seen.set(key, v)
    added++
  }
  const entries = [...seen.values()].sort((a, b) => b.subject.at - a.subject.at).slice(0, MAX_BOARD_ENTRIES)
  return { entries, changed: added > 0, added }
}

/** Stored entries, re-checked on the way out — a row written by an older server is not trusted blind. */
export function parseBoard(raw: unknown): Vouch[] {
  if (!Array.isArray(raw)) return []
  return raw.map((v) => parseVouch(v, Number.MAX_SAFE_INTEGER)).filter((v): v is Vouch => v !== null)
}
