// Generated from daemons/plates/lynx.mjs by daemons/tools/generate.mjs. Do not edit.
// @ts-nocheck
import { ellipse, seg, tube, path, union, blend, part, eye } from './plate.g.js'

// lynx: Lynx, the text-mode web browser (University of Kansas, 1992), still maintained: the web with the pictures taken out.
export const size = { w: 92, h: 78 }

const lerp = (a, b, u) => a + (b - a) * u
const clamp01 = (v) => Math.max(0, Math.min(1, v))
const smooth = (a, b, v) => { const u = clamp01((v - a) / (b - a)); return u * u * (3 - 2 * u) }

// Move a part drawn in local units: scale by k about the local origin, turn by rot, then put the
// origin at (ox, oy).
function place(p, k, ox, oy, rot = 0) {
  const c = Math.cos(rot), s = Math.sin(rot)
  const to = (x, y) => { const dx = x - ox, dy = y - oy; return [(dx * c + dy * s) / k, (-dx * s + dy * c) / k] }
  const q = { ...p, d: (x, y) => p.d(...to(x, y)) * k }
  if (p.relief) q.relief = p.relief * k
  if (p.tex) q.tex = (x, y) => p.tex(...to(x, y))
  return q
}

// The spotted coat: soft jittered dots on a grid darken the fur.
const hash = (i, j) => { const v = Math.sin(i * 127.1 + j * 311.7) * 43758.5453; return v - Math.floor(v) }
function spotted(cell, r, dark) {
  return (x, y) => {
    const gx = Math.floor(x / cell), gy = Math.floor(y / cell)
    let m = Infinity
    for (let i = -1; i <= 1; i++) {
      for (let j = -1; j <= 1; j++) {
        const a = gx + i, b = gy + j
        const px = (a + 0.2 + 0.6 * hash(a, b)) * cell, py = (b + 0.2 + 0.6 * hash(b + 7, a - 3)) * cell
        m = Math.min(m, Math.hypot(x - px, (y - py) * 0.8))
      }
    }
    return 1 - (1 - dark) * smooth(r, r * 0.5, m)
  }
}

// How far along a path (0..1) the nearest point sits: for the tail's black tip.
function along(pts, x, y) {
  let best = Infinity, at = 0
  for (let i = 0; i < pts.length; i++) {
    const d = (pts[i][0] - x) ** 2 + (pts[i][1] - y) ** 2
    if (d < best) { best = d; at = i }
  }
  return at / (pts.length - 1)
}

export function model({ t = 0, mood = 'idle', age = '2.0' } = {}) {
  const g = clamp01((parseFloat(age) - 0.1) / 1.9) // 0 hatchling .. 1 grown
  const k = lerp(0.64, 1.05, g) // overall size
  const hk = lerp(1.45, 1.02, g) // head size against the body: kittens are mostly head
  const tuftK = lerp(0.15, 1, Math.pow(g, 1.4)) // the signature, only a hint at first
  const earK = lerp(0.72, 1, g)
  const ruffK = lerp(0.3, 1, g)

  const breath = Math.sin(t)
  const hop = mood === 'done' ? 2.8 * Math.pow(Math.max(0, Math.sin(2 * t)), 2) : 0
  const twitch = Math.pow(Math.max(0, Math.sin(t)), 6) // one quick flick of the right ear per loop

  // ---- body: local units, x from the middle, the floor at y = 0 and up is negative ----
  const chestRy = lerp(9.5, 15, g) * (1 + 0.025 * breath), chestRx = lerp(11, 14, g) * (1 + 0.015 * breath)
  const chestCy = lerp(-9, -16, g)
  const spots = spotted(5.5, 2, 0.55)
  const coat = (x, y) => lerp(1, spots(x, y), smooth(5, 9, Math.abs(x)))
  const body = []

  // a stubby tail curled out from behind the right haunch, black tipped
  const tail = path(16, -3, -0.45 + 0.16 * Math.sin(t + 1.2), lerp(10, 15, g), (u) => -0.05 - 0.1 * u)
  body.push(part(tube(tail, 3.4, 3.2), { relief: 3, tone: 0.84, tex: (x, y) => 1 - 0.5 * smooth(0.7, 0.85, along(tail, x, y)) }))
  const haunch = (side) => ellipse(side * lerp(11, 12.5, g), -lerp(6, 8, g), lerp(8, 9.5, g), lerp(6, 8, g))
  body.push(part(blend(6, ellipse(0, chestCy, chestRx, chestRy), haunch(-1), haunch(1)), { relief: 6, tone: 0.82, tex: (x, y) => coat(x, y) * (1 - 0.5 * smooth(5, 2, Math.abs(x)) * smooth(chestCy, chestCy + 8, y)) }))
  body.push(part(union(...[-1, 1].map((side) => seg(side * 6.2, chestCy + 3, side * 7, -4, 3.7, 3.5))), { relief: 3, tone: 1 }))
  for (const side of [-1, 1]) {
    const px = side * 7.6
    body.push(part(ellipse(px, -3.1, 5.8, 3.4), { relief: 3, tone: 0.96, tex: (x, y) => (y > -4.6 && Math.abs(Math.abs(x - px) - 2) < 0.5 ? 0.4 : 1) }))
  }

  // ---- head: head units, the origin between the eyes ----
  const head = []
  let earOut = 0, earDrop = 0, tilt = 0, headDy = 0
  if (mood === 'fail') { earOut = 0.6; earDrop = 2.5 }
  if (mood === 'nap') { earOut = 0.3; earDrop = 1.5; headDy = 1.5 }
  if (mood === 'need') tilt = 0.13
  if (mood === 'boop') earOut = 0.18
  if (mood === 'work' || mood === 'back') earOut = -0.06

  for (const side of [-1, 1]) {
    const flick = side > 0 ? twitch : 0
    const a = -Math.PI / 2 + side * (0.2 + earOut + 0.2 * flick)
    const bx = side * 7.5, by = -9 + earDrop
    const len = 13.5 * earK - earDrop
    const ca = Math.cos(a), sa = Math.sin(a)
    const tx = bx + ca * len, ty = by + sa * len
    const up = (x, y) => (x - bx) * ca + (y - by) * sa // distance along the ear
    head.push(part(seg(bx, by, tx, ty, 5.6, 0.5), { relief: 2.5, tone: 0.84, tex: (x, y) => 1 - 0.5 * smooth(len * 0.72, len * 0.92, up(x, y)) }))
    head.push(part(seg(bx + ca * 3 - side * 0.3, by + sa * 3, bx + ca * (len - 4.5), by + sa * (len - 4.5), 3, 0.4), { tone: 0.5, ink: false }))
    // the tuft: a brush of hair standing straight off the tip
    const ta = a - side * (0.1 + 0.05 * Math.sin(2 * t + side) + 0.3 * flick)
    const hair = (da, l, r) => tube(path(tx - ca * 1.2, ty - sa * 1.2, ta + side * da, l * tuftK, () => -side * 0.02), r, 0.2)
    head.push(part(union(hair(0, 8, 0.8), hair(0.4, 5, 0.6)), { tone: 0.62, ink: false }))
  }

  // the ruff: a flared beard of fur off each cheek, in points
  const ruffSide = (side) => {
    const S = (x0, y0, x1, y1, r) => seg(side * x0, y0, side * (11 + (x1 - 11) * ruffK), 6 + (y1 - 6) * ruffK, r, 0.4)
    return union(ellipse(side * 11.5, 7, 6, 5), S(12, 3, 22, 7, 3.6), S(11, 7, 20, 13.5, 3.4), S(9, 8, 15.5, 16, 3.2))
  }
  head.push(part(union(ruffSide(-1), ruffSide(1)), { relief: 2.5, tone: 1, tex: (x, y) => 0.9 + 0.1 * Math.sin(Math.atan2(y - 2, x) * 16) }))

  const skull = blend(6, ellipse(0, -1.5, 14, 11), ellipse(0, 4, 15, 7))
  head.push(part(skull, { relief: 6, tone: 0.84 }))
  head.push(part(blend(2, ellipse(-2.6, 7.2, 3.1, 2.4), ellipse(2.6, 7.2, 3.1, 2.4), ellipse(0, 9.2, 3.4, 2.2)), { relief: 2, tone: 1, ink: false }))
  head.push(part(seg(0, 4.2, 0, 5.9, 1.8, 0.6), { tone: 0.1, ink: false }))

  const look = mood === 'idle' ? [0.2, 0] : [0, 0.2]
  // eye height nudged per age so the pupils land on a row at 56 columns
  const gy = 0.9 / 1.9, ey = g < gy ? lerp(0.6, -1.4, g / gy) : lerp(-1.4, -0.6, (g - gy) / (1 - gy))
  for (const side of [-1, 1]) head.push(...eye(side * 6.7, ey, lerp(5.3, 4.8, g), mood, { look }))

  const headCy = lerp(-27, -40, g) + headDy + 0.2 * breath
  const local = [...body, ...head.map((p) => place(p, hk, 0, headCy, tilt))]
  return { ...size, parts: local.map((p) => place(p, k, 43, 76.5 - hop)) }
}
