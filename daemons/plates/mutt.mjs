import { ellipse, seg, tube, path, blend, part, eye } from '../tools/plate.mjs'

// mutt: the terminal mail client (Michael Elkins, 1995): "All mail clients suck. This one just sucks less."
export const size = { w: 100, h: 84 }

const FLOOR = 82

// Move a part by a map from canvas to model coordinates, scaling its distance by k.
function warp(p, map, k = 1) {
  const q = { ...p, d: (x, y) => k * p.d(...map(x, y)) }
  if (p.relief) q.relief = p.relief * k
  if (p.tex) q.tex = (x, y) => p.tex(...map(x, y))
  return q
}
const grow = (p, s, ox, oy) => (s === 1 ? p : warp(p, (x, y) => [ox + (x - ox) / s, oy + (y - oy) / s], s))
const shift = (p, dx, dy) => (!dx && !dy ? p : warp(p, (x, y) => [x - dx, y - dy]))
const turn = (p, a, ox, oy) => {
  if (!a) return p
  const c = Math.cos(a), s = Math.sin(a)
  return warp(p, (x, y) => [ox + (x - ox) * c + (y - oy) * s, oy - (x - ox) * s + (y - oy) * c])
}

// Scruff: pointed tufts pushed out of a shape's edge, n to a full turn, only between angles lo..hi.
function tufts(d, cx, cy, n, amp, lo, hi, ph = 0) {
  return (x, y) => {
    const ang = Math.atan2(y - cy, x - cx)
    const m = Math.min(ang - lo, hi - ang)
    if (m <= 0) return d(x, y)
    const w = Math.min(1, m / 0.35)
    return d(x, y) - amp * w * (1 - Math.abs(Math.sin((ang * n) / 2 + ph))) ** 2
  }
}

// Fur that is never quite combed, shaggier on the tail, and the fringe hanging in a hatch.
const fur = (x, y) => 0.93 + 0.07 * Math.sin(x * 1.3 + Math.sin(y * 0.3) * 2.4)
const shag = (x, y) => 0.84 + 0.16 * Math.sin(x * 1.4 + Math.sin(y * 0.25) * 2)
const hair = (x, y) => 0.78 + 0.22 * Math.sin(x * 1.3 + Math.sin(y * 0.2) * 2)

export function model({ t = 0, mood = 'idle', age = '2.0' } = {}) {
  const a = Math.max(0, Math.min(1, (parseFloat(age) - 0.1) / 1.9)) // 0 hatchling .. 1 full grown
  const happy = mood === 'done' || mood === 'back' || mood === 'boop'
  const sad = mood === 'fail'
  const pant = mood === 'idle' || mood === 'need' || happy
  const breath = Math.sin(2 * t)

  // ---- body: sitting, the haunch round and behind, the chest and front legs forward ----
  const body = []
  const wag = (sad ? 0.08 : mood === 'nap' ? 0.05 : happy ? 0.5 : 0.36) * Math.sin(2 * t)
  const tail = sad
    ? path(73, 77, 0.15, 17 * (0.5 + 0.5 * a), () => 0.02)
    : path(71, 74, -0.45 + wag, 27 * (0.45 + 0.55 * a), (u) => (-0.035 - 0.04 * wag) * (0.4 + 1.6 * u))
  body.push(part(tube(tail, 5, 1.8), { relief: 3.5, tone: 0.86, tex: shag }))

  const haunch = ellipse(63, 70, 13.5, 11)
  const chest = tufts(ellipse(47, 64, 13.5 + 0.3 * breath, 14), 47, 64, 24, 2.4, 0.4, 2.7)
  body.push(part(blend(10, haunch, chest), { relief: 10, tone: 0.84, tex: fur }))
  body.push(part(ellipse(69, FLOOR - 2.8, 8.5, 3.3), { relief: 2.5, tone: 0.88 })) // hind paw
  for (const [x0, x1] of [[42, 40], [53, 54]]) {
    body.push(part(blend(3, seg(x0, 64, x1, FLOOR - 3, 4.4, 3.9), ellipse(x1 - 1.2, FLOOR - 2.8, 5.6, 3.1)), { relief: 3.5, tone: 0.92, tex: fur }))
  }

  // ---- head (drawn full grown, then placed) ----
  const back = [], head = []
  const flick = 0.2 * Math.max(0, Math.sin(t)) ** 8
  const perk = sad ? 0.15 : 0.25 + 0.75 * a // the standing ear only hints on the hatchling
  const earUp = path(62, 19, -1.2 + (1 - perk) * 0.5 + flick, 9 + 10 * perk, (u) => 0.02 + 0.1 * u * u + (u > 0.35 ? (1 - perk) * 0.4 : 0))
  back.push(part(tube(earUp, 7.5, 1.2), { relief: 3.5, tone: 0.82, tex: fur }))

  // the skull, scruffy at the cheeks, the muzzle pushed forward and a touch to the left:
  // three-quarter view
  const skull = tufts(ellipse(46, 31, 24, 18), 46, 31, 22, 2.6, 0.5, 2.7, 0.8)
  const muzzle = ellipse(40, 43.5, 11, 7.5)
  head.push(part(blend(6, skull, ellipse(41, 43, 13, 8.5)), { relief: 11, tone: 0.9, tex: fur }))
  head.push(part(ellipse(57.5, 29.5, 9.5, 8.8, 0.3), { relief: 4, tone: 0.34, ink: false })) // the patch
  head.push(part(muzzle, { relief: 6, tone: 1 }))

  // the fringe: the crown's hair, tufted on top and hanging in ragged points over the brow,
  // longer as it grows
  const crown = tufts(ellipse(46, 31, 24.5, 18.5), 46, 31, 16, 1 + 2.8 * a, -2.5, -0.7, 0.3)
  const brow = 17 + 2 * a
  const hang = (x) => (2 + 5 * a) * (1 - Math.abs(Math.sin((x - 33) * 0.36))) ** 2
  head.push(part((x, y) => Math.max(crown(x, y), y - brow - hang(x)), { relief: 3, tone: 1, tex: hair }))

  const look = mood === 'work' ? [-1, 0.3] : [-0.2, 0.25]
  head.push(...eye(34, 30, 7.6, mood, { look, tone: 0.02 }), ...eye(57.5, 29.5, 7.6, mood, { look, tone: 0.02 }))

  if (pant) {
    const lick = 9 + 2 * breath
    head.push(part(ellipse(40.5, 48.5, 7, 2.6), { tone: 0.02, ink: false }))
    head.push(part(seg(41, 48.5, 41.5, 48.5 + lick, 4.4, 3.8), { relief: 3, tone: 1 }))
    head.push(part(seg(41.3, 50, 41.5, 47 + lick, 0.55), { tone: 0.12, ink: false }))
  } else {
    head.push(part(tube(path(33, 47.5, 0.25, 14, () => -0.035), 0.6), { tone: 0.04, ink: false }))
  }
  head.push(part(ellipse(39.5, 40.5, 6, 4), { relief: 3, tone: 0.05 })) // nose

  // the ear that flops, hanging by the cheek and widening to a round tip
  const droop = (sad ? 0.25 : 0) + 0.04 * breath
  const g = 0.6 + 0.4 * a
  head.push(part(seg(27, 16, 27 - (11 - 4 * droop) * g, 16 + (22 + 4 * droop) * g, 3.6, 5.4), { relief: 3, tone: 0.5, tex: fur }))

  // ---- place: tilt the head, grow a big-headed hatchling, sit it on the floor ----
  const tilt = mood === 'need' ? -0.12 : sad ? 0.1 : mood === 'nap' ? 0.12 : 0
  const nod = mood === 'nap' ? 2.5 : sad ? 1.5 : 0
  const hk = 1.3 - 0.3 * a // the hatchling's head is big for its body
  const place = (p) => grow(shift(turn(p, tilt, 46, 48), 0, nod), hk, 46, 50)
  const hop = mood === 'done' ? -2.4 * Math.max(0, Math.sin(2 * t)) : 0
  const s = 0.68 + 0.32 * a
  return { ...size, parts: [...back.map(place), ...body, ...head.map(place)].map((p) => grow(shift(p, 0, hop), s, 50, FLOOR)) }
}
