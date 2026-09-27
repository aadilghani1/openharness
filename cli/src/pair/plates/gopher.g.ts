// Generated from daemons/plates/gopher.mjs by daemons/tools/generate.mjs. Do not edit.
// @ts-nocheck
import { circle, ellipse, box, seg, union, meet, blend, part, eye } from './plate.g.js'

// gopher: the Gopher protocol (University of Minnesota, 1991), named after the campus mascot; for a moment it was bigger than the web.
export const size = { w: 100, h: 86 }

// Deterministic value noise for the dirt: clods and grains, the same every frame.
const hash = (i, j) => { const s = Math.sin(i * 127.1 + j * 311.7) * 43758.5453; return s - Math.floor(s) }
function noise(x, y) {
  const i = Math.floor(x), j = Math.floor(y), fx = x - i, fy = y - j
  const u = fx * fx * (3 - 2 * fx), v = fy * fy * (3 - 2 * fy)
  const a = hash(i, j), b = hash(i + 1, j), c = hash(i, j + 1), d = hash(i + 1, j + 1)
  return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v
}

// Move a part's frame: `to` maps a canvas point back into the part's own coordinates; `k` is how
// much it scales distances (for relief).
function warp(p, to, k = 1) {
  return {
    ...p,
    d: (x, y) => k * p.d(...to(x, y)),
    ...(p.relief ? { relief: p.relief * k } : {}),
    ...(p.tex ? { tex: (x, y) => p.tex(...to(x, y)) } : {}),
  }
}
// Scale about the floor point, so the young sit on the same ground, smaller.
const grow = (p, s, fx, fy) => (s === 1 ? p : warp(p, (x, y) => [(x - fx) / s + fx, (y - fy) / s + fy], s))
// Tilt the head about the neck (positive leans it to the right, clockwise on screen).
function tilt(p, a, ox, oy) {
  if (!a) return p
  const c = Math.cos(a), s = Math.sin(a)
  return warp(p, (x, y) => { const dx = x - ox, dy = y - oy; return [ox + dx * c + dy * s, oy - dx * s + dy * c] })
}

// Per mood: how far out of the hole it stands, the ears (positive droops them), the head's tilt.
const MOOD = {
  idle: { rise: 0, ears: 0, tilt: 0 },
  work: { rise: -1.5, ears: 0, tilt: 0.05 },
  need: { rise: 3, ears: -0.5, tilt: -0.08 },
  done: { rise: 3, ears: 0, tilt: 0 },
  fail: { rise: -4, ears: 1, tilt: -0.12 },
  back: { rise: 1.5, ears: 0, tilt: -0.06 },
  nap: { rise: -3, ears: 0.6, tilt: 0.16 },
  boop: { rise: 1, ears: -0.4, tilt: 0.04 },
}

export function model({ t = 0, mood = 'idle', age = '2.0' } = {}) {
  const a = Math.max(0.1, Math.min(2, +age || 2))
  const g = a <= 1 ? ((a - 0.1) / 0.9) * 0.55 : 0.55 + (a - 1) * 0.45 // 0 hatchling, 1 grown
  const m = MOOD[mood] || MOOD.idle
  const cx = 50, floor = 86
  const asleep = mood === 'nap'

  // life: rising a little out of the hole, a look left and right, a twitching nose
  const up = 1.8 * (1 - Math.cos(t)) + m.rise + (mood === 'done' ? 2.5 * Math.abs(Math.sin(t)) : 0)
  const look = asleep ? 0 : Math.sin(t)
  const twitch = asleep ? 0 : Math.max(0, Math.sin(t * 3)) // an irregular sniff
  const breathe = 1 + (asleep ? 0.035 : 0.02) * Math.sin(t * 2)
  const lean = m.tilt + (asleep ? 0.02 : 0.04) * Math.sin(t)
  const Y = (y) => y - up // everything on the gopher rides up with `up`

  // proportions: a pup is head and eyes; the grown one has the cheek pouches, teeth and claws
  const hs = 1.2 - 0.2 * g // head scale
  const bs = 0.8 + 0.2 * g // body scale
  const teeth = 0.3 + 0.7 * g
  const pouch = 0.72 + 0.28 * g
  const hx = cx + look * 1.4 // the head turns a little with the look
  const fx = hx + look * 1.2 // and the face a little further

  // ---- the mound: a lumpy dome of turned earth, a dark hole in its crown
  const holeY = 74
  const mound = blend(9,
    ellipse(cx, 96, 49, 22),
    ellipse(cx, holeY + 1, 34, 8.5), // the crater ring the gopher pushed up
    ellipse(cx - 27, 84, 17, 7),
    ellipse(cx + 28, 85, 16, 6),
  )
  const clods = union(circle(cx - 41, 80, 2.6), circle(cx + 40, 79, 2.2), circle(cx - 31, 75, 1.8), circle(cx + 46, 84, 1.9))
  const hole = ellipse(cx, holeY, 25, 5)
  const dirt = (x, y) => 0.72 + 0.5 * (noise(x * 0.5, y * 0.8) - 0.5) + 0.3 * (noise(x * 1.6 + 9, y * 2.2) - 0.5)
  const lip = meet(mound, (x, y) => Math.max(holeY - y, -hole(x, y))) // the rim in front of the gopher

  // ---- the body: a plump sausage standing in the hole
  const body = blend(12,
    ellipse(cx, Y(68), 20 * bs * breathe, 16 * bs),
    ellipse(cx, Y(51) + (1 - bs) * 10, 16 * bs * breathe, 12 * bs),
  )
  // the head's shadow on the chest, so the teeth and paws stand out against it
  const chin = (x, y) => 1 - 0.4 * Math.exp(-(((x - hx) / 13) ** 2) - (((y - Y(47)) / 6) ** 2))

  // little paws held up at the chest under the teeth, digging claws hanging down
  const pawY = Y(49.5) + (mood === 'work' ? 1.5 * Math.sin(t * 2) : 0)
  const paw = (px, py, down = 1) => ({
    hand: ellipse(px, py + 0.5, 4.2 * bs, 4.4 * bs),
    claws: union(...[-1, 0, 1].map((k) => seg(px + k * 2 * bs, py + down * 3.5 * bs, px + k * 2.4 * bs, py + down * (4.6 + 2.8 * teeth) * bs, 0.85 * bs, 0.4 * bs))),
  })
  const waving = mood === 'back'
  const paws = [-1, 1].map((s) => {
    if (waving && s > 0) return null
    const px = cx + s * 4.6 * bs
    return { arm: seg(cx + s * 12 * bs, Y(57), px + s * 1.5, pawY + 1, 3.6 * bs, 3 * bs), ...paw(px, pawY) }
  }).filter(Boolean)
  // on `back` the right paw comes up beside the cheek in a little wave
  const wx = cx + 24 * bs + Math.sin(t * 2) * 1.5, wy = Y(44)
  const wave = waving ? { arm: seg(cx + 13 * bs, Y(58), wx, wy + 2, 3.8 * bs, 3.2 * bs), ...paw(wx, wy, -1) } : null

  // ---- the head: round, with fat cheek pouches low on each side
  const headY = Y(24) + (1 - bs) * 18
  const rx = 20 * hs, ry = 17 * hs
  const earX = 17.5 * hs + m.ears * 2, earY = headY - 11 * hs + m.ears * 3
  const ears = [-1, 1].map((s) => circle(hx + s * earX, earY, 4.7 * hs))
  const earIn = [-1, 1].map((s) => circle(hx + s * (earX + 0.6), earY + 0.6, 2.3 * hs))

  const cheek = [11 * pouch * hs, 9 * pouch * hs]
  const head = blend(8,
    ellipse(hx, headY, rx, ry),
    ellipse(hx - 15 * hs, headY + 8 * hs, ...cheek),
    ellipse(hx + 15 * hs, headY + 8 * hs, ...cheek),
  )

  const mzY = headY + (10.5 - g) * hs
  const muzzle = ellipse(fx, mzY, 10 * hs, 7 * hs)
  const nb = mood === 'boop' ? 1.3 : 1 // a booped nose scrunches up big
  const nose = ellipse(fx + look * 0.4, mzY - 3.6 * hs - twitch, (3.6 + twitch) * hs * nb, (2.4 + twitch * 0.4) * hs * nb)
  const mouthY = mzY + 4 * hs
  const mouth = ellipse(fx, mouthY, 5.5 * hs, 2.8 * hs)
  const tw = 2.1 * hs, th = 5 * teeth * hs
  const tooth = [-1, 1].map((s) => box(fx + s * (tw + 0.35), mouthY + th * 0.9, tw, th, 0.7))
  const gum = box(fx, mouthY + th * 0.9, tw * 2 + 1.4, th + 1.1, 1.4) // a dark ring so the teeth pop

  // whiskers sit behind the head, so only the tips past the cheeks show
  const whiskers = union(...[-1, 1].flatMap((s) => [
    seg(fx + s * 20 * hs, mzY - 1 * hs, fx + s * (20 + 13 * g) * hs, mzY - (1 + 3 * g) * hs - twitch * 0.5, 0.45, 0.25),
    seg(fx + s * 20 * hs, mzY + 1.5 * hs, fx + s * (20 + 12 * g) * hs, mzY + (1.5 + 1.5 * g) * hs + twitch * 0.5, 0.45, 0.25),
  ]))

  const eyeR = 5.8 * hs * (1.12 - 0.12 * g) // a pup's eyes are big for its face
  const eyes = [-1, 1].flatMap((s) => eye(fx + s * (10.5 - g) * hs, headY - (3 - 2 * g) * hs, eyeR, mood, { look: [look * 0.6, 0.15] }))

  const neck = [hx, headY + 16 * hs]
  const earParts = [
    ...ears.map((d) => part(d, { relief: 3, tone: 0.8 })),
    ...earIn.map((d) => part(d, { tone: 0.2, ink: false })),
  ].map((p) => tilt(p, lean, ...neck))
  const headParts = [
    part(whiskers, { tone: 0.75, ink: false }),
    part(head, { relief: 9, tone: 0.86 }),
    part(muzzle, { relief: 4, tone: 0.98, ink: false }),
    part(mouth, { tone: 0.05, ink: false }),
    part(gum, { tone: 0.12, ink: false }),
    ...tooth.map((d) => part(d, { tone: 1, ink: false })),
    part(nose, { tone: 0.08, ink: false }),
    ...eyes,
  ].map((p) => tilt(p, lean, ...neck))

  const pawParts = (p) => [part(p.arm, { relief: 3, tone: 0.66 }), part(p.claws, { tone: 0.95 }), part(p.hand, { relief: 3, tone: 1.25 })]
  const gopher = [
    ...earParts,
    part(body, { relief: 10, tone: 0.78, tex: chin }),
    ...paws.flatMap(pawParts),
    ...headParts,
    ...(wave ? pawParts(wave) : []),
  ]

  const earth = [
    part(mound, { relief: 7, tone: 0.6, tex: dirt }),
    part(clods, { relief: 1.5, tone: 0.62, tex: dirt }),
    part(hole, { tone: 0.03, ink: false }),
  ]
  const front = [part(lip, { relief: 4, tone: 0.64, tex: dirt })]

  const s = 0.66 + 0.34 * g
  const parts = [...earth, ...gopher, ...front].map((p) => grow(p, s, cx, floor))
  return { ...size, parts }
}
