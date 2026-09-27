// Generated from daemons/plates/gnu.mjs by daemons/tools/generate.mjs. Do not edit.
// @ts-nocheck
import { ellipse, seg, tube, path, union, meet, blend, mirror, part, eye } from './plate.g.js'

// gnu: GNU's Not Unix (Richard Stallman, 1983), the recursive acronym; the gnu is a wildebeest.
export const size = { w: 100, h: 86 }

const clamp01 = (v) => Math.max(0, Math.min(1, v))
const mix = (a, b, k) => a + (b - a) * k

// Long hanging hair: a vertical hatch that waves a little down its length.
const hair = (lo, dx = () => 0) => (x, y) => lo + (1 - lo) * (0.5 + 0.5 * Math.sin((x - dx(y)) * 1.5 + Math.sin(y * 0.22) * 2))

// Scale a part about a point on the floor, so a younger gnu sits smaller on the same ground.
const grow = (p, k, ox, oy) => (k === 1 ? p : {
  ...p,
  d: (x, y) => k * p.d(ox + (x - ox) / k, oy + (y - oy) / k),
  tex: p.tex && ((x, y) => p.tex(ox + (x - ox) / k, oy + (y - oy) / k)),
})

export function model({ t = 0, mood = 'idle', age = '2.0' } = {}) {
  const cx = 50
  const g = clamp01((parseFloat(age) - 0.1) / 1.9) // 0 hatchling .. 1 full grown

  const chew = (mood === 'nap' ? 0 : 1) * Math.sin(2 * t) // a slow chew: the jaw rolls side to side, twice a loop
  const sway = Math.sin(t + 0.6) // the beard swings
  const flick = Math.pow(Math.max(0, Math.cos(t - (3 * Math.PI) / 4)), 12) // one quick ear flick

  // body language
  const perk = ['need', 'boop', 'done', 'back'].includes(mood) ? 1 : ['fail', 'nap'].includes(mood) ? -1 : 0
  const lift = mood === 'done' ? -2 : mood === 'nap' ? 1.2 : 0 // a hop, a nod
  const browTilt = { work: 0.3, fail: -0.32, need: -0.12, boop: -0.12 }[mood] ?? 0 // + frowns, - worries
  const browUp = { need: -2.2, boop: -2.2, done: -1, back: -1, nap: 0.8 }[mood] ?? 0

  const parts = []
  const add = (d, o) => parts.push(part(d, o))

  // proportions by age: a hatchling is mostly head and eyes, on a short face and a short neck
  const headY = mix(40, 32, g) + lift
  const muzzleY = headY + mix(15, 23, g)
  const eyeR = mix(8.4, 7, g)
  const headR = mix(22, 20, g)

  // shoulders, behind the head: dark, a quiet base
  add(blend(12, ellipse(cx, 106, 50, 30), ellipse(cx, 80, 18, 8)), { relief: 12, tone: 0.3 })
  // the neck
  add(seg(cx, muzzleY - 6, cx, 90, mix(10, 10.5, g), mix(12, 14, g)), { relief: 8, tone: 0.36 })

  // ears: out and a little down, under the horns; the left one flicks
  const droop = 0.4 - 0.34 * perk
  const ear = (side, a) => ellipse(cx + side * (16 + 9.5 * Math.cos(a)), headY - 5 + 9.5 * Math.sin(a), 9.5, 3.8, side * a)
  add(ear(-1, droop - 0.45 * flick), { relief: 2.5, tone: 0.62 })
  add(ear(1, droop), { relief: 2.5, tone: 0.62 })

  // forelock: a wild white tuft over the brow
  const q = mix(0.6, 1, g), tq = headY - mix(17, 20, g)
  add(union(ellipse(cx - 4 * q, tq, 3.2 * q, 6.5 * q, -0.45), ellipse(cx + q, tq - 1.5 * q, 3.2 * q, 7 * q, 0.1), ellipse(cx + 5.5 * q, tq + q, 3 * q, 5.5 * q, 0.6)), { relief: 2.5, tone: 1, tex: hair(0.55) })

  // the white beard, hanging from the jaw, its lower edge in strands; it swings and follows the chew
  const bx = cx + chew * 0.6, top = muzzleY + 9, bottom = mix(top + 6, 85, g)
  const swing = (y) => sway * 2.4 * clamp01((y - top) / (bottom - top)) + chew * 0.6
  const beardBody = blend(6, ellipse(bx, top, mix(8, 14.5, g), 5), seg(bx, top + 1, cx + sway * 2.4, bottom, mix(6, 14, g), 3.5))
  const strands = (x, y) => y - (bottom - 4 + 3 * Math.sin((x - cx - sway * 2.4) * 1.1) - Math.abs(x - cx) * 0.3)
  add(meet(beardBody, strands), { relief: 3, tone: 1, tex: hair(0.45, swing) })

  // head: a round brow, a long face, a broad muzzle
  add(blend(9, ellipse(cx, headY, headR, mix(17.5, 15.5, g)), seg(cx, headY + 6, cx, muzzleY - 2, 11.5, 9.8), ellipse(cx, muzzleY, 13.5, 8)), { relief: 14, tone: 0.78 })
  // the chewing jaw
  add(ellipse(cx + chew * 1.3, muzzleY + 7, 8.5, 3), { relief: 2, tone: 0.72 })
  // a small, contented smile
  add(tube(path(cx - 4.5 + chew * 1.3, muzzleY + 6.3, 0.5, 9, () => -0.11), 0.85), { tone: 0.03, ink: false })

  // horns: one bar across the top of the head, out sideways with a slight droop, then up like
  // handlebars. A hatchling has two nubs; they meet and lengthen as it grows.
  const hornLen = mix(9, 48, g)
  const hornA = mix(Math.PI + 1.05, Math.PI - 0.12, Math.min(1, g * 1.6))
  const horn = tube(path(cx - mix(8, 0, Math.min(1, g * 1.6)), headY - mix(11.5, 13.5, g), hornA, hornLen, (u) => (u < 0.42 ? 0 : 0.12 * g)), mix(3.2, 5.4, g), mix(1.6, 1.1, g))
  add(mirror(cx, horn), { relief: 3.5, tone: 1 })

  // bushy white eyebrows: the professor's, grown in with age
  if (g > 0.2) {
    for (const s of [-1, 1]) {
      const heading = s < 0 ? Math.PI + 0.32 + browTilt : -0.32 - browTilt
      add(tube(path(cx + s * 3.5, headY - 4.5 + browUp, heading, mix(8, 13, g), () => s * 0.075), mix(1.6, 2.9, g), mix(1.1, 1.5, g)), { tone: 1 })
    }
  }

  // snout and nostrils
  add(ellipse(cx, muzzleY + 1.5, 11.5, 5.8), { relief: 4, tone: 0.95 })
  for (const s of [-1, 1]) add(ellipse(cx + s * 5.2, muzzleY + 2.8, 2.9, 2, s * 0.55), { tone: 0.03, ink: false })

  // eyes, looking a little down, calm
  for (const s of [-1, 1]) parts.push(...eye(cx + s * 10.5, headY + 7, eyeR, mood, { look: [-s * 0.2, 0.25] }))

  const k = mix(0.8, 1, g)
  return { ...size, parts: parts.map((p) => grow(p, k, cx, size.h)) }
}
