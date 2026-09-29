import { describe, expect, it } from 'vitest'
import { openHandedRoster, sealHandedRoster } from './handedRoster.js'

// One vector for both languages: the phones seal in Dart (`viewer/group_sync.dart` `sealHandedRoster`),
// this CLI opens. The same inputs must give the same bytes on both sides — desktop's
// test/viewer/group_sync_test.dart pins the identical string.
const VECTOR = 'MCsWzwhdskkULflZqvr/unR+ynpfBWQdAE3GXwh+/8m83dSl5Ec/JCojguagCCL91gghdXqGphL7tgaRHbJO11qaAJAvrguTW6XwhFjtK3V785T2LWibIeRWCjBsrJ+FCPGtbK+6qTS0dmFWPNyB41Jm7Qc1ICGuXKVLNort+YXR3uMh+sx16TlHddBqkbn1rkZE7O+MiYfFSiwjAw2+hTwIiBmSzZAi7wEn99u/22/yMpp83cH6a8tZzVZvyKBSZ0hIVfE='
const ROSTER = { members: [{ pub: 'A'.repeat(43) + '=', kind: 'machine', label: 'studio', at: 1700000000000, machineId: 'a'.repeat(32) }], removed: [] }
const opts = { code: 'ABCDEFGHJKMNPQRS', userCode: 'VECTORUSERCODE' }

describe('a roster handed over by the approving phone', () => {
  it('seals to the bytes the phones produce, and opens back', () => {
    expect(sealHandedRoster(ROSTER, opts)).toBe(VECTOR)
    expect(openHandedRoster(VECTOR, opts)).toEqual(ROSTER)
  })

  it('opens with the QR\'s code however it is cased, and with nothing else', () => {
    expect(openHandedRoster(VECTOR, { ...opts, code: 'abcdefghjkmnpqrs' })).toEqual(ROSTER)
    expect(openHandedRoster(VECTOR, { ...opts, code: 'ABCDEFGHJKMNPQRT' })).toBeNull()
    expect(openHandedRoster(VECTOR, { ...opts, userCode: 'ANOTHERREQUEST' })).toBeNull()
    const tampered = Buffer.from(VECTOR, 'base64'); tampered[5] ^= 1
    expect(openHandedRoster(tampered.toString('base64'), opts)).toBeNull()
    expect(openHandedRoster('not base64 at all!', opts)).toBeNull()
  })
})
