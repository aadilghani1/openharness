// Generated from daemons/plates/yak.mjs by daemons/tools/generate.mjs. Do not edit.
// @ts-nocheck
import { ellipse, box, seg, tube, path, blend, union, part, eye } from './plate.g.js'

// yak: yacc, "Yet Another Compiler-Compiler" (Stephen Johnson, Bell Labs, 1975), and yak shaving,
// the chain of side tasks between you and what you set out to do.
export const size = { w: 112, h: 96 }

const FLOOR = 93

// Long hanging hair as vertical hatch; `sway` pushes the strands sideways more the lower they hang.
const hatch = (top, sway, amp = 0.24, f = 0.8) => (x, y) => {
  const k = Math.max(0, Math.min(1, (y - top) / 18))
  return 1 - amp * k * (0.5 - 0.5 * Math.sin((x - sway * k * k) * f + Math.sin(y * 0.15) * 1.5))
}
// A soft shadow cast on a part by the shapes in front of it.
const shadow = (d, w = 3, a = 0.55) => (x, y) => 1 - a * Math.exp(-Math.max(0, d(x, y)) / w)
// A line of hair clumps hanging in points: the height at x of a hem `drop` deep every `pitch`.
const points = (x, base, drop, pitch, phase = 0) => {
  const c = Math.abs(Math.cos(((x - phase) * Math.PI) / pitch))
  return base + drop * c * c * c
}
const mul = (...fs) => (x, y) => fs.reduce((m, f) => m * f(x, y), 1)
// Light from above: the back catches it, the hanging hair falls into shade.
const fall = (x, y) => 1 - 0.12 * Math.max(0, Math.min(1, (y - 28) / 56))

// Scale by k about (ox, oy), then move by (tx, ty): a shape, or a part with its relief and texture.
const move = (k, ox, oy, tx = 0, ty = 0) => {
  const at = (f) => (x, y) => f(ox + (x - ox - tx) / k, oy + (y - oy - ty) / k)
  const shape = (d) => { const g = at(d); return (x, y) => k * g(x, y) }
  return {
    shape,
    point: (x, y) => [ox + (x - ox) * k + tx, oy + (y - oy) * k + ty],
    part: (p) => ({ ...p, d: shape(p.d), ...(p.relief && { relief: p.relief * k }), ...(p.tex && { tex: at(p.tex) }) }),
  }
}

// A mouth across the muzzle: bend > 0 smiles, bend < 0 frowns.
const mouth = (x, y, w, bend, r) => tube(path(x - w / 2, y - bend * w * 0.3, bend * 0.9, w, () => (-bend * 1.8) / w, 10), r)

export function model({ t = 0, mood = 'idle', age = '2.0' } = {}) {
  // growth: 0 the hatchling (big head, nub horns, a short fluffy coat), 1 full grown
  const g = Math.max(0, Math.min(1, (parseFloat(age) - 0.1) / 1.9))
  const breath = Math.sin(t)
  const sway = 1.2 * Math.sin(t)
  const chew = mood === 'nap' ? 0 : Math.sin(2 * t)

  // ---- head: out front, facing us, a shaggy mop with a face peeking out of the fringe ----
  const hx = 29, hy = 34, ey = 38
  const beard = 0.25 + 0.75 * g
  const shag = blend(8,
    ellipse(hx, hy, 19, 16),
    seg(hx - 13, hy + 6, hx - 12 + 0.5 * sway, hy + 6 + 22 * beard, 7, 3.5),
    seg(hx + 13, hy + 6, hx + 12 + 0.5 * sway, hy + 6 + 22 * beard, 7, 3.5),
    ellipse(hx + 0.4 * sway, hy + 8 + 18 * beard, 12, 8),
  )
  const mop = (x, y) => Math.max(shag(x, y), y - points(x, hy + 9 + 18 * beard, 2 + 3 * g, 6, hx + 0.6 * sway))
  const face = ellipse(hx, hy + 8, 13.5, 13)
  // the fringe is the mop with a window cut for the face, its bangs hanging in points to the eyes
  const opening = (x, y) => Math.max(face(x, y), points(x, ey - 4.5, 2.2, 6.5, hx + 3.25 + 0.3 * sway) - y)
  const fringe = (x, y) => Math.max(mop(x, y), -opening(x, y))
  const earFlick = Math.pow(Math.max(0, Math.sin(t)), 12)
  const droop = mood === 'fail' || mood === 'nap' ? 0.55 : mood === 'need' || mood === 'boop' ? -0.35 : 0
  const ears = [
    ellipse(hx - 20, hy + 3 - 2 * earFlick, 6, 2.6, 0.35 + droop - 0.5 * earFlick),
    ellipse(hx + 20, hy + 3, 6, 2.6, -0.35 - droop),
  ]
  // horns: out sideways, then up, the tips turning in; a hatchling has two nubs
  const horns = [-1, 1].map((s) => tube(
    path(hx + s * 11, hy - 9, s < 0 ? Math.PI + 0.15 + 0.8 * (1 - g) : -0.15 - 0.8 * (1 - g), 10 + 18 * g, () => s * -0.1),
    2.8 + 1.2 * g, 0.8 + 0.8 * (1 - g),
  ))
  const muzzle = ellipse(hx, 50 + 0.3 * chew, 10, 6.5)
  const nostrils = [-1, 1].map((s) => ellipse(hx + s * 4 + 0.3 * chew, 50, 2.2, 1.7))
  // deadpan: a flat mouth that works side to side, chewing the cud
  const smile = mood === 'done' || mood === 'back' ? 1 : mood === 'fail' ? -0.8 : 0
  const lips = mood === 'boop' ? ellipse(hx, 54, 1.8, 1.6) : mouth(hx + 0.8 * chew, 54.2, 6.4, smile, 0.8)

  // the head is bigger on a hatchling, and droops or lifts with the mood
  const dip = { nap: 4, fail: 2.5, work: 1, need: -1.5, boop: -1 }[mood] ?? 0
  const hs = 1 + 0.28 * (1 - g)
  const head = move(hs, hx, hy, 4 * (1 - g), 7 * (1 - g) + dip)
  const front = head.shape(union(mop, ...horns))

  // ---- body: hump over the shoulders, barrel, rump, and a skirt of long hair to the floor ----
  const L = 0.7 + 0.26 * g // body length
  const bx = (x) => 48 + (x - 48) * L
  const hem = 72 + 11 * g
  const low = 8 * (1 - g) // a hatchling's short legs
  const trunk = blend(12,
    ellipse(bx(64), 31 + 8 * (1 - g), 19 * L, 17 - 6 * (1 - g)),
    ellipse(bx(76), 46, 30 * L, 16 + 0.5 * breath),
    ellipse(bx(95), 47, 10.5, 13),
    box(bx(71), (44 + hem) / 2 + 1, 32 * L, (hem - 44) / 2 + 1, 8),
  )
  const coat = (x, y) => Math.max(trunk(x, y), y - points(x, hem, 2 + 3 * g, 7, sway))
  const body = move(1, 0, 0, 0, low)
  const legs = [42, 52, 89, 99].map((x, i) => part(
    union(seg(bx(x), 70, bx(x), FLOOR - 2, 3.6, 3.4), ellipse(bx(x) - 0.6, FLOOR - 1.4, 3.9, 1.8)),
    { tone: i % 2 ? 0.4 : 0.6, relief: 2.5 },
  ))
  const swish = mood === 'back' ? 0.1 * Math.sin(2 * t) - 0.04 : 0.05 * Math.sin(t + 0.8)
  const tail = tube(path(bx(104), 36, 1.48 + swish, 12 + 22 * g, () => 0.01), 1.8, 2.6 + 1.2 * g)

  // the whole animal: smaller when young, standing on the same floor; a happy bounce when done
  const S = 0.68 + 0.32 * g
  const all = move(S, 56, FLOOR, 7 * (1 - g), mood === 'done' ? -2 - 1.5 * Math.cos(2 * t) : 0)

  // Eyes are placed last, snapped to the cells of the 56-column plate so each pupil lands in one.
  const [lx, ly] = all.point(...head.point(hx - 7, ey)), [rx] = all.point(...head.point(hx + 7, ey))
  const gap = 2 * Math.round((rx - lx) / 2), ex = 2 * Math.round((lx + rx - gap) / 4 - 0.5) + 1
  const eyeY = 4 * Math.round((ly - 2) / 4) + 2, r = 5 * (1 + 0.15 * (1 - g)) * hs * S
  const eyes = [ex, ex + gap].flatMap((x) => eye(x, eyeY, r, mood, { look: [0, 0.1] }))
  return {
    ...size,
    parts: [
      ...legs.map(all.part),
      ...[
        part(coat, { tone: 0.9, relief: 10, tex: mul(hatch(44, sway), fall, shadow(move(1, 0, 0, 0, -low).shape(front))) }),
        part(tail, { tone: 0.78, relief: 2.5, tex: hatch(48, sway, 0.3) }),
      ].map(body.part).map(all.part),
      ...[
        ...ears.map((d) => part(d, { tone: 0.7, relief: 2 })),
        ...horns.map((d) => part(d, { tone: 1, relief: 2.5 })),
        part(face, { tone: 0.9, relief: 6 }),
      ].map(head.part).map(all.part),
      ...eyes,
      ...[
        part(fringe, { tone: 0.84, relief: 8, tex: hatch(hy - 4, sway, 0.26) }),
        part(muzzle, { tone: 1, relief: 5, ink: false }),
        ...[...nostrils, lips].map((d) => part(d, { tone: 0.1, ink: false })),
      ].map(head.part).map(all.part),
    ],
  }
}
