import { ellipse, seg, tube, path, part, eye } from '../tools/plate.mjs'

// bug: the moth found in relay 70 of the Harvard Mark II on 9 September 1947, taped into the
// logbook: "First actual case of bug being found."
export const size = { w: 120, h: 100 }

const CX = 60
const clamp = (v, a = 0, b = 1) => Math.min(b, Math.max(a, v))

// A filled polygon (iq's exact polygon distance), rounded by r.
function poly(pts, r = 0) {
  return (x, y) => {
    let d = Infinity, s = 1
    for (let i = 0, j = pts.length - 1; i < pts.length; j = i++) {
      const [ax, ay] = pts[i], [bx, by] = pts[j]
      const ex = bx - ax, ey = by - ay, wx = x - ax, wy = y - ay
      const h = clamp((wx * ex + wy * ey) / (ex * ex + ey * ey))
      d = Math.min(d, (wx - ex * h) ** 2 + (wy - ey * h) ** 2)
      const c1 = y >= ay, c2 = y < by, c3 = ex * wy > ey * wx
      if ((c1 && c2 && c3) || (!c1 && !c2 && !c3)) s = -s
    }
    return s * Math.sqrt(d) - r
  }
}

// Move a shape by mapping render space back to its rest space; k keeps distances honest.
const warp = (d, f, k = 1) => (x, y) => { const [u, v] = f(x, y); return d(u, v) * k }

// The plate's own light, so the tape can show what lies under it.
const LIGHT = (() => { const v = [-0.5, -0.62, 0.62], n = Math.hypot(...v); return v.map((c) => c / n) })()
function shade(p, x, y) {
  const s = -p.d(x, y)
  let b = p.tone
  if (p.relief) {
    const e = 0.25
    const gx = (p.d(x + e, y) - p.d(x - e, y)) / (2 * e), gy = (p.d(x, y + e) - p.d(x, y - e)) / (2 * e)
    const gl = Math.hypot(gx, gy) || 1
    const u = Math.min(s / p.relief, 1), slope = u >= 1 ? 0 : (1 - u) / Math.sqrt(Math.max(1 - (1 - u) * (1 - u), 1e-4))
    let nx = (gx / gl) * slope, ny = (gy / gl) * slope, nz = 1
    const nl = Math.hypot(nx, ny, nz); nx /= nl; ny /= nl; nz /= nl
    b = p.tone * (0.46 + 0.58 * Math.max(0, nx * LIGHT[0] + ny * LIGHT[1] + nz * LIGHT[2]))
  }
  if (p.tex) b *= p.tex(x, y)
  return b
}
const under = (parts, x, y) => { for (let i = parts.length - 1; i >= 0; i--) if (parts[i].d(x, y) < 0) return shade(parts[i], x, y); return -1 }

// A strip of tape: a band along `rot` through (cx, cy), with torn ends.
function tape(cx, cy, hl, hh, rot) {
  const c = Math.cos(rot), s = Math.sin(rot)
  return (x, y) => {
    const dx = x - cx, dy = y - cy, u = dx * c + dy * s, v = -dx * s + dy * c
    const torn = 1.1 * Math.sin(v * 2.3 + (u > 0 ? 1 : 4)) + 0.6 * Math.sin(v * 5.1)
    return Math.max(Math.abs(v) - hh, Math.abs(u) - hl - torn)
  }
}

// A feathery antenna along points: a vane widest past the middle, toothed like a comb.
function plume(pts, w) {
  const segs = []
  let L = 0
  for (let i = 1; i < pts.length; i++) {
    const [ax, ay] = pts[i - 1], [bx, by] = pts[i], l = Math.hypot(bx - ax, by - ay)
    segs.push([ax, ay, bx - ax, by - ay, l, L])
    L += l
  }
  // a bounding circle, so points far away skip the walk along the shaft
  const [mx, my] = pts[pts.length >> 1], R = Math.max(...pts.map(([px, py]) => Math.hypot(px - mx, py - my))) + w + 1
  return (x, y) => {
    const far = Math.hypot(x - mx, y - my) - R
    if (far > 0) return far + 1
    let best = Infinity, at = 0
    for (const [ax, ay, ex, ey, l, l0] of segs) {
      const h = clamp(((x - ax) * ex + (y - ay) * ey) / (l * l))
      const d = Math.hypot(x - ax - ex * h, y - ay - ey * h)
      if (d < best) { best = d; at = (l0 + h * l) / L }
    }
    const r = w * Math.pow(Math.sin(Math.PI * Math.min(at * 0.85 + 0.08, 1)), 0.8)
    return best - r * (0.7 + 0.3 * Math.cos(at * L * 1.25)) - 0.5
  }
}

// Scale every part about (ax, ay): the younger moths are the same moth, smaller, on the same floor.
function scaled(parts, k, ax, ay) {
  if (k === 1) return parts
  const f = (x, y) => [ax + (x - ax) / k, ay + (y - ay) / k]
  return parts.map((p) => ({ ...p, d: warp(p.d, f, k), relief: p.relief && p.relief * k, tex: p.tex && ((x, y) => p.tex(...f(x, y))) }))
}

export function model({ t = 0, mood = 'idle', age = '2.0' } = {}) {
  const g = clamp((parseFloat(age) - 0.1) / 1.9)
  const lerp = (a, b) => a + (b - a) * g
  const headK = lerp(1.22, 1), wingK = lerp(0.6, 1), antK = lerp(0.6, 1), abdK = lerp(0.62, 1), thK = lerp(1.3, 1)
  const droop = lerp(0.3, 0) // a hatchling's wing buds stick out sideways, like little arms

  const pressed = mood === 'fail', still = mood === 'nap'
  // Seen from above a raised wing looks shorter: the flutter is a small squeeze of the span.
  const flap = still ? 0 : 0.5 - 0.5 * Math.cos(2 * t)
  const spread = mood === 'done' ? 1.05 : 1
  const kx = (pressed ? 1.04 : spread) * (1 - 0.055 * flap), ky = (pressed ? 0.93 : 1) * (1 - 0.02 * flap)

  const TY = 56 // the thorax, where the wings meet
  const HY = TY - 8.6 - 14 * headK

  // ---- wings: rounded triangles, patterned, a little darker than the fluffy body --------------
  // outlines as (out from the middle, down from the thorax), for the right side
  const fore = [[6, -8], [20, -21], [36, -32], [50, -40], [52, -33], [46, -19], [36, -6], [12, 3]]
  const hind = [[6, 2], [26, 2], [39, 9], [40, 22], [31, 35], [18, 35], [9, 24]]
  const outline = (pts, side) => pts.map(([dx, dy]) => [CX + side * dx, TY + dy])
  // each wing grows (and flutters) from its root at the side of the thorax
  const cr = Math.cos(droop), sr = Math.sin(droop)
  const toRest = (x, y) => {
    const side = Math.sign(x - CX) || 1, bx = CX + side * 6, px = (x - bx) * side, py = y - TY
    return [bx + (side * (px * cr + py * sr)) / (kx * wingK), TY + (-px * sr + py * cr) / (ky * wingK)]
  }
  const wingAt = (d) => warp(d, toRest, Math.min(kx, ky) * wingK)
  const texAt = (tx) => (x, y) => tx(...toRest(x, y))
  // forewing: pale near the body, a wavy dark crossline, a kidney spot, a dusky outer band
  const foreTex = (x, y) => {
    const dx = Math.abs(x - CX), r = Math.hypot(dx, y - TY), a = Math.atan2(y - TY, dx)
    const wob = 1.8 * Math.sin(a * 8)
    let m = r > 47 + wob ? 0.72 : 1
    if (Math.abs(r - 43 - wob) < 2.2) m *= 0.55
    m *= 1 - 0.65 * Math.exp(-((dx - 31) ** 2 + ((y - TY + 16) * 1.25) ** 2) / 11)
    return m
  }
  const hindTex = (x, y) => {
    const dx = Math.abs(x - CX), r = Math.hypot(dx, y - TY)
    return r > 28 + 2 * Math.sin(Math.atan2(y - TY, dx) * 5) ? 0.78 : 1
  }
  const wings = []
  for (const side of [-1, 1]) wings.push(part(wingAt(poly(outline(hind, side), 3)), { tone: 0.6, relief: 5, tex: texAt(hindTex) }))
  for (const side of [-1, 1]) wings.push(part(wingAt(poly(outline(fore, side), 3.5)), { tone: 0.84, relief: 8, tex: texAt(foreTex) }))

  // ---- antennae: feathery plumes, a bright shaft in a toothed vane, arching out -------------
  const antennae = []
  for (const side of [-1, 1]) {
    const twitch = still ? 0 : 0.07 * Math.sin((side < 0 ? 3 : 2) * t)
    const lift = mood === 'need' ? -0.06 : mood === 'boop' ? 0.25 : pressed ? 0.8 : still ? 0.6 : 0
    const heading = -Math.PI / 2 + side * (0.22 + lift + twitch)
    const pts = path(CX + side * 4 * headK, HY - 9 * headK, heading, 25 * antK, (u) => side * 0.065 * u * (pressed ? -0.3 : 1), 14)
    const w = lerp(3.4, 3.8)
    antennae.push(part(plume(pts, w), { tone: 0.56, relief: w }), part(tube(pts, 1.1, 0.6), { tone: 1, ink: false }))
  }

  // ---- body: fluffy and pale, a segmented abdomen, a round head -----------------------------
  const breathe = 1 + 0.03 * Math.sin(t)
  const fur = (x, y) => 0.86 + 0.14 * Math.sin(x * 2.3 + Math.sin(y * 1.9) * 2) * Math.sin(y * 1.7 - x * 0.6)
  const abdomen = part(seg(CX, TY + 6, CX, TY + 6 + 30 * abdK, 7.5 * breathe, 3), {
    tone: 0.95, relief: 6, tex: (x, y) => 0.84 + 0.16 * Math.cos((y - TY) * 1.05),
  })
  const fuzz = (cx, cy, rx, ry, n, amp) => {
    const e = ellipse(cx, cy, rx, ry)
    return (x, y) => e(x, y) + amp * Math.sin(Math.atan2(y - cy, x - cx) * n)
  }
  const thorax = part(fuzz(CX, TY, 11 * thK, 9.5 * thK, 18, 0.8), { tone: 1, relief: 7, tex: fur })
  const head = part(fuzz(CX, HY - 1, 18 * headK, 13 * headK, 22, 0.5), { tone: 0.8, relief: 8 * headK })
  // it always looks toward the light, upper left
  const look = mood === 'work' ? [-0.4, 0] : [-0.25, -0.15]
  const wide = mood === 'need' || mood === 'boop'
  const eyes = [-1, 1].flatMap((side) => eye(CX + side * 8.5 * headK, HY, (wide ? 6.4 : 7.5) * headK, mood, { look }))

  // a dark rim where the body lies over the wings, so it stands off them
  const halo = (p, ...behind) => part((x, y) => Math.max(p.d(x, y) - 1.7, Math.min(...behind.map((b) => b.d(x, y)))), { tone: 0.1, ink: false })
  const moth = [...antennae, ...wings, halo(abdomen, ...wings), abdomen, halo(thorax, ...wings, abdomen), thorax, halo(head, ...antennae, ...wings, thorax), head, ...eyes]

  // ---- the tape: flat and pale, the moth pressed under it ----------------------------------
  const strips = [tape(CX, TY + lerp(15, 24.4), lerp(31, 54), lerp(5.4, 6.5), 0)]
  // on a failure it gets a second strip, across the wings: pressed flat, antennae and all
  if (pressed) strips.push(tape(CX, TY - lerp(3, 1.6), lerp(20, 50), lerp(5, 6.5), 0.03))
  const tapes = strips.map((d) => part(d, {
    tone: 1, tex: (x, y) => { const b = under(moth, x, y); return b < 0 ? 0.12 : 0.5 + 0.45 * b },
  }))

  return { ...size, parts: scaled([...moth, ...tapes], lerp(0.72, 1), CX, 96) }
}
