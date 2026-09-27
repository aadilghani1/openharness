// Generated from daemons/plates/auk.mjs by daemons/tools/generate.mjs. Do not edit.
// @ts-nocheck
import { circle, ellipse, seg, tube, path, blend, union, meet, part, eye } from './plate.g.js'

// auk: awk (Aho, Weinberger and Kernighan, Bell Labs, 1977) and the great auk, the first bird ever
// called a penguin, extinct since 1844; awk is still in every Unix.
export const size = { w: 100, h: 86 }

const FLOOR = { x: 57, y: 76 } // where the feet meet the rock; the young stand here too
const clamp = (v, a = 0, b = 1) => Math.max(a, Math.min(b, v))
const mix = (a, b, u) => a + (b - a) * u
const smooth = (e0, e1, v) => { const u = clamp((v - e0) / (e1 - e0)); return u * u * (3 - 2 * u) }

// Turn a shape (or a texture) by `a` radians about (px, py), clockwise on screen (y down).
function turn(f, px, py, a) {
  if (!a) return f
  const c = Math.cos(a), s = Math.sin(a)
  return (x, y) => { const dx = x - px, dy = y - py; return f(px + c * dx + s * dy, py - s * dx + c * dy) }
}
const turnPart = (p, px, py, a) => ({ ...p, d: turn(p.d, px, py, a), tex: p.tex && turn(p.tex, px, py, a) })

// Scale a finished part by k about the floor point and raise it by `lift` (a hop).
function grow(p, k, lift) {
  if (k === 1 && !lift) return p
  const at = (f) => (x, y) => f(FLOOR.x + (x - FLOOR.x) / k, FLOOR.y + (y - FLOOR.y + lift) / k)
  const d = at(p.d)
  return { ...p, d: (x, y) => d(x, y) * k, tex: p.tex && at(p.tex), relief: p.relief && p.relief * k }
}

// '0.1' a grey downy chick, '1.0' a young auk, '2.0' the great auk: g runs 0, 0.55, 1.
function growth(age) {
  const a = parseFloat(age)
  if (!Number.isFinite(a)) return 1
  return clamp(a <= 1 ? ((a - 0.1) / 0.9) * 0.55 : 0.55 + (a - 1) * 0.45)
}

export function model({ t = 0, mood = 'idle', age = '2.0' } = {}) {
  const g = growth(age), baby = 1 - g
  const k = mix(0.66, 1.05, g)

  // ---- body language -------------------------------------------------------------------
  const breath = Math.sin(t) * (mood === 'nap' ? 1.7 : 1)
  let nod = 0.028 * Math.sin(t + 0.8) // a slow, dignified bob of the bill
  let headDx = 0, headDy = -0.45 * Math.sin(t), wingUp = 0, lift = 0
  if (mood === 'work') { nod -= 0.1; headDx = -1.5 } // leans in to read the input
  if (mood === 'fail') { nod -= 0.26; headDy += 2.5; wingUp = -0.1 } // hangs its head
  if (mood === 'nap') { nod -= 0.18; headDy += 3.5; headDx = 1.5 } // sunk into its shoulders
  if (mood === 'boop') { nod += 0.14; headDx = 2 } // pulls back from the finger
  if (mood === 'need') wingUp = -2.55 // a flipper up: a question
  if (mood === 'back') wingUp = -2.3 + 0.35 * Math.sin(2 * t) // waves hello
  if (mood === 'done') { lift = 3 * Math.max(0, Math.sin(t)); wingUp = -0.55 } // a small hop, flippers out

  // ---- the body: one silhouette from crown to tail ---------------------------------------
  const swell = 1 + 0.025 * breath
  const bodyRy = mix(16, 23, g), bodyCy = FLOOR.y - 1 - bodyRy
  const body = ellipse(58, bodyCy, mix(18, 17, g) * swell, bodyRy, -0.12)
  const chest = ellipse(mix(55, 51, g), bodyCy - bodyRy * 0.3, mix(13, 12, g) * swell, mix(11, 12, g))
  const headR = mix(19, 14, g)
  const hx = mix(51, 46, g) + headDx, hy = bodyCy - bodyRy * mix(0.95, 1.0, g) - headR * mix(0.35, 0.55, g) + headDy
  const pivot = [55, bodyCy - bodyRy * 0.7] // the neck
  const head = turn(circle(hx, hy, headR), pivot[0], pivot[1], nod)
  const neck = seg(57, bodyCy - bodyRy * 0.55, hx + 3, hy + headR * 0.4, mix(12, 10, g), mix(11, 8.5, g))
  const tail = seg(67, FLOOR.y - 8, 80 - baby * 6, FLOOR.y - 1.5, 3.8, 0.8)
  const silhouette = blend(8, body, chest, neck, head, tail)

  // White from the throat down, ending in a point on the foreneck; the rest black as a dinner jacket.
  const belly = ellipse(mix(54, 50.5, g), bodyCy + bodyRy * 0.12, mix(13, 14.5, g), bodyRy * 1.08, -0.1)
  const dark = mix(0.66, 0.56, g), white = mix(0.8, 0.95, g)
  const fluff = (x, y) => 1 + baby * 0.14 * Math.sin(x * 2.1 + Math.sin(y * 1.7) * 2) * Math.sin(y * 1.9)
  const plumage = (x, y) => mix(dark, white, smooth(0.8, -0.8, belly(x, y))) * fluff(x, y)

  // Flipper: small, held at the side, pointing down and back.
  const shoulder = [63, bodyCy - bodyRy * 0.5]
  const flipper = tube(path(shoulder[0], shoulder[1], 1.42, mix(13, 27, g), (u) => 0.012 + 0.02 * u), mix(4, 5.4, g), 1.1)
  const wing = turn(flipper, shoulder[0], shoulder[1], wingUp)
  // The white bar along its trailing edge, from the tips of the secondaries.
  const bar = turn((x, y) => Math.max(flipper(x, y), -flipper(x + 1.5, y), shoulder[1] + 6 - y), shoulder[0], shoulder[1], wingUp)

  // Feet: black, webbed, flat on the rock, toes forward.
  const foot = (dx) => blend(2, seg(63 + dx, FLOOR.y - 4, 62 + dx, FLOOR.y - 1.2, 2.4, 2), seg(62 + dx, FLOOR.y - 1.2, mix(54, 48, g) + dx, FLOOR.y - 0.8, 2, 1.1))

  // ---- the head: the deep, grooved, hooked bill and the white oval ------------------------
  // The bill is drawn level, facing left from its gape (bx, by), then tipped down a little.
  const bx = hx - headR * mix(0.92, 0.8, g), by = hy + headR * 0.3
  const L = mix(8, 19, g), up = mix(5.5, 10.5, g), lo = mix(3.5, 5.5, g), tilt = -0.08
  // The culmen is one arc from the forehead down to the tip.
  const arcR = ((L * L + up * up) / (2 * up)) * 0.62 + L * 0.3
  const upperArc = circle(bx - L * 0.38, by + arcR - up, arcR)
  const upper = meet(upperArc, (x, y) => Math.max(x - bx - 3, y - by, bx - L - x))
  const lower = meet(ellipse(bx + 2, by - 1.2, L * 0.8 + 2, lo + 1.2), (x, y) => Math.max(x - bx - 3, by - 1.2 - y))
  const hook = tube(path(bx - L * 0.9, by - up * 0.32, Math.PI - 0.35, mix(2, 6.5, g), () => -0.3), mix(0.9, 1.9, g), 0.5)
  const beak = g > 0.3 ? union(upper, hook) : upper
  const bill = turn(union(beak, lower), bx, by, tilt)
  // White grooves across the bill, curved like its base: three on the great auk, a hint on the chick.
  const n = g < 0.3 ? 1 : g < 0.8 ? 2 : 3
  const grooves = []
  for (let i = 0; i < n; i++) {
    const r = L * (n === 1 ? 0.5 : 0.3 + 0.2 * i) + 8
    const arc = (x, y) => Math.abs(Math.hypot(x - (bx + 8), y - by) - r) - mix(0.75, 0.65, g)
    grooves.push(part(meet(turn(arc, bx, by, tilt), (x, y) => bill(x, y) + 0.9), { tone: n === 1 ? 0.7 : 1, ink: false }))
  }
  const eyeX = hx + headR * 0.2, eyeY = hy - headR * 0.12, eyeR = mix(7.8, 6.2, g)
  const patch = ellipse(eyeX - eyeR * mix(0.9, 1.1, g), eyeY - 0.6, eyeR * mix(0.7, 0.95, g), eyeR * mix(0.6, 0.72, g), 0.15)
  const look = mood === 'work' ? [-1, 0.6] : [-0.45, 0]
  // A heavy upper lid, drooping to the back: at rest the auk looks a little wistful.
  const lidLine = (x, y) => y - (eyeY - eyeR * 0.32 + (x - eyeX) * 0.2)
  const lid = mood === 'idle' && g > 0.5 ? [part(meet(circle(eyeX, eyeY, eyeR * 1.05), lidLine), { tone: dark * 0.95 })] : []
  const headParts = [
    part(turn(lower, bx, by, tilt), { tone: 0.42, relief: 2 }),
    part(turn(beak, bx, by, tilt), { tone: 0.5, relief: 2.5 }),
    ...grooves,
    part(patch, { tone: mix(0.62, 1, g), ink: false }),
    ...eye(eyeX, eyeY, eyeR, mood, { look }),
    ...lid,
  ].map((p) => turnPart(p, pivot[0], pivot[1], nod))

  const bird = [
    part(foot(-4), { tone: 0.24, relief: 1.5 }),
    part(silhouette, { tone: 1, relief: 10, tex: plumage }),
    part(wing, { tone: mix(0.58, 0.5, g), relief: 3 }),
    part(bar, { tone: mix(0.6, 0.9, g), ink: false }),
    part(foot(0), { tone: 0.3, relief: 1.5 }),
    ...headParts,
  ].map((p) => grow(p, k, lift))

  // The rock, the same at every age.
  const rock = blend(6, ellipse(57, 88, 30, 11), ellipse(44, 83, 13, 6, 0.1), ellipse(72, 83, 14, 5.5, -0.15))
  const grain = (x, y) => 0.92 + 0.08 * Math.sin(x * 0.35 + Math.sin(y * 0.5) * 2)
  return { ...size, parts: [part(rock, { tone: 0.4, relief: 6, tex: grain }), ...bird] }
}
