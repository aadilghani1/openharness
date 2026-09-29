/**
 * A trust-group roster handed over by the phone that approved this device's sign-in QR — the other
 * half of the viewer apps' `sealHandedRoster` (`viewer/group_sync.dart`).
 *
 * The QR carries a one-time pairing code that only the approving phone ever reads, by its camera. The
 * phone seals its roster under a key derived from that code and hands it over through the backend's
 * sign-in request; the backend carries it but can neither read nor alter it. Opening it is how this
 * device learns — and pins — every machine of the group, and the phone that vouched for it, without
 * dialling anything first. The phone, for its part, took this device's key (checked against the QR's
 * fingerprint) into its own roster: the two now trust each other, and the group sync spreads the rest.
 *
 * The code is 16 characters from a 30-symbol alphabet (~78 bits, from a CSPRNG), which is why a plain
 * KDF is enough here where a remote password needs a PAKE.
 */
import { sha256 } from '@noble/hashes/sha2'
import { hkdf } from '@noble/hashes/hkdf'
import { aeadOpen, aeadSeal, b64d, b64e, utf8 } from './core.js'

const SALT = 'harness/signin-roster/v1'
const AAD = 'harness signin roster'

/** The key, bound to the sign-in request it answers ([userCode]) so one sealed roster cannot be replayed into another. */
function key(code: string, userCode: string): Uint8Array {
  return hkdf(sha256, utf8(code.trim().toUpperCase()), utf8(SALT), utf8(userCode), 32)
}

/** The roster as the phone sent it, or null when it does not open (another code or request, or a changed byte). */
export function openHandedRoster(sealed: string, opts: { code: string; userCode: string }): unknown {
  let ct: Uint8Array
  try { ct = b64d(sealed) } catch { return null }
  const clear = aeadOpen(key(opts.code, opts.userCode), 1, utf8(AAD), ct)
  if (!clear) return null
  try { return JSON.parse(new TextDecoder().decode(clear)) as unknown } catch { return null }
}

/** The sealing side, for tests (the phones seal; this CLI only opens). */
export function sealHandedRoster(roster: unknown, opts: { code: string; userCode: string }): string {
  return b64e(aeadSeal(key(opts.code, opts.userCode), 1, utf8(AAD), utf8(JSON.stringify(roster))))
}
