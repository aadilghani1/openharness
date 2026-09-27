// Generated from daemons/plates/tux.mjs by daemons/tools/generate.mjs. Do not edit.
// @ts-nocheck
import { circle, ellipse, seg, tube, path, cut, blend, part, eye } from './plate.g.js'

// tux: the Linux penguin. Linus Torvalds said a penguin bit him at a zoo in Canberra; Larry Ewing drew the mascot in the GIMP in 1996.
export const size = { w: 100, h: 84 }

const clamp01 = (v) => Math.max(0, Math.min(1, v))
const mix = (a, b, k) => a + (b - a) * k

// Turn a shape by `a` radians about (cx, cy).
function turn(cx, cy, a) {
  const c = Math.cos(a), s = Math.sin(a)
  return (d) => (x, y) => {
    const dx = x - cx, dy = y - cy
    return d(cx + dx * c + dy * s, cy - dx * s + dy * c)
  }
}

// The penguin is drawn in its own frame: origin on the floor between its feet, y down, full-grown
// units. place() scales it by s, rocks it by rot about that floor point and lifts it by hop.
function place(px, py, s, rot, hop) {
  const c = Math.cos(rot), sn = Math.sin(rot)
  const local = (x, y) => {
    const dx = x - px, dy = y - py + hop
    return [(dx * c + dy * sn) / s, (-dx * sn + dy * c) / s]
  }
  return (d) => (x, y) => s * d(...local(x, y))
}

// Body language per mood. The left flipper (the one that waves): its heading (radians, y down, so
// -PI/2 is straight up), how far it swings and how fast (turns per loop), and its curl. The right
// flipper: its heading and curl. Then a happy hop, the waddle-rock, the head's tilt and droop.
const MOODS = {
  idle: { arm: -2.5, swing: 0.22, speed: 2, curl: 0.06, rest: 1.3, restCurl: 0.035, hop: 0, sway: 0.03, tilt: -0.05, droop: 0 },
  work: { arm: 0.5, swing: 0.07, speed: 4, curl: 0.02, rest: 1.3, restCurl: 0.035, hop: 0, sway: 0.01, tilt: 0.06, droop: 0.5 },
  need: { arm: -1.75, swing: 0.14, speed: 4, curl: 0.03, rest: 1.3, restCurl: 0.035, hop: 0, sway: 0.02, tilt: -0.12, droop: 0 },
  done: { arm: -2.2, swing: 0.2, speed: 2, curl: 0.05, rest: -0.95, restCurl: -0.05, hop: 3, sway: 0.02, tilt: -0.04, droop: 0 },
  fail: { arm: 1.85, swing: 0, speed: 0, curl: -0.03, rest: 1.4, restCurl: 0.03, hop: 0, sway: 0.008, tilt: 0.1, droop: 1 },
  back: { arm: -2.3, swing: 0.38, speed: 2, curl: 0.06, rest: 1.3, restCurl: 0.035, hop: 0, sway: 0.03, tilt: -0.1, droop: 0 },
  nap: { arm: 1.85, swing: 0, speed: 0, curl: -0.03, rest: 1.4, restCurl: 0.03, hop: 0, sway: 0.012, tilt: 0.14, droop: 0.6 },
  boop: { arm: -2.95, swing: 0.04, speed: 2, curl: 0.04, rest: -0.2, restCurl: -0.04, hop: 0, sway: 0.008, tilt: 0, droop: 0 },
}

export function model({ t = 0, mood = 'idle', age = '2.0' } = {}) {
  const g = clamp01((parseFloat(age) - 0.1) / 1.9) // 0 hatchling .. 1 full grown
  const M = MOODS[mood] || MOODS.idle

  const s = mix(0.72, 1, g)
  const breath = Math.sin(t) * (mood === 'nap' ? 2.5 : 1)
  const hop = M.hop * Math.abs(Math.sin(t))
  const X = place(50, 82, s, M.sway * Math.sin(t), hop)
  const P = (d, o = {}, to = X) => part(to(d), { ...o, relief: o.relief && o.relief * s })

  // proportions: a chick is mostly head, the grown bird mostly belly
  const headR = 23
  const headY = mix(-48, -57, g) + M.droop * 2
  const bodyRx = mix(22, 29, g), bodyRy = mix(20, 28, g)
  const bodyY = -bodyRy - 1
  const H = turn(0, headY + headR * 0.8, M.tilt + (mood === 'nap' ? 0.05 : 0.025) * Math.sin(t)) // the head's own tilt

  const backTone = 0.47
  const coatTone = mix(0.82, 0.47, g) // a chick's grey down
  const bellyTone = mix(0.92, 0.96, g)
  const fw = mix(3.8, 5.6, g), ft = mix(2.4, 2, g) // flipper root and tip radius

  const parts = []

  // body and head: one dark pear
  const body = ellipse(0, bodyY, bodyRx * (1 + 0.012 * breath), bodyRy)
  const head = H(ellipse(0, headY, headR, headR * 0.92))
  parts.push(P(blend(14, body, head), { relief: 12, tone: backTone }))
  if (g < 1) {
    // a chick: grey down on the body, the dark head sitting on it
    parts.push(P(body, { relief: 12, tone: coatTone, ink: false }))
    parts.push(P(head, { relief: 10, tone: backTone, ink: g < 0.6 }))
  }

  // the white front: one bib from the cheeks down to the belly, under a dark hood that comes to a
  // point between the eyes (a chick has the mask, and only a hint of the bib)
  const bellyRx = mix(13, 21.5, g) * (1 + 0.02 * breath), bellyRy = mix(12, 23, g)
  const belly = ellipse(0, bodyY + 2, bellyRx, bellyRy)
  const mask = H(cut(ellipse(0, headY + headR * 0.12, headR * 0.84, headR * 0.74), circle(0, headY - headR * 0.64, headR * 0.3)))
  parts.push(P(belly, { relief: 10, tone: bellyTone, ink: false }))
  parts.push(P(mask, { relief: 8, tone: 0.97, ink: false }))
  if (g > 0.5) parts.push(P(blend(8, belly, mask), { relief: 10, tone: 0.96, ink: false }))

  // a tuft of down on top that the grown bird has lost
  if (g < 0.8) {
    const k = 1 - g / 0.8
    parts.push(P(H(tube(path(1, headY - headR * 0.88, -1.75, 9 * k, (u) => 0.1 + 0.25 * u), 2.4 * k + 0.4, 0.5)), { relief: 1.5, tone: backTone }))
  }

  // flippers: a chick's are stubs held out from its sides
  const fx = bodyRx - mix(1.5, 5, g), fy = bodyY - bodyRy * mix(0.3, 0.42, g), fl = mix(9, 21, g)

  // flipper on the right (the bird's left): down its side, the tip resting on the belly
  const rest = tube(path(fx, fy, M.rest - (1 - g) * 0.6, fl, (u) => M.restCurl * u), fw, ft)
  parts.push(P(rest, { relief: 3, tone: coatTone }))

  // flipper on the left (the bird's right): out to the side and up, a small wave
  const armA = M.arm - M.swing * Math.sin(M.speed * t)
  const waving = tube(path(-fx, fy, armA, fl, (u) => M.curl * u), fw, ft)
  parts.push(P(waving, { relief: 3, tone: coatTone }))

  // feet: big and flat in front, toes splayed, planted while the body rocks
  const planted = place(50, 82, s, 0, hop)
  const footS = mix(0.65, 1, g)
  for (const side of [-1, 1]) {
    const x = side * mix(8, 11.5, g)
    const toes = [-1, 0, 1].map((i) => ellipse(x + side * 1.5 + i * 5.4 * footS, -2, 3.3 * footS, 2.7 * footS, i * 0.4))
    const foot = blend(3, ellipse(x, -3.6, 8.5 * footS, 3.2 * footS), ...toes)
    parts.push(P(foot, { relief: 2, tone: 0.72 }, planted))
  }

  // beak: a short dark wedge, pointed down
  const bw = mix(4.6, 5.8, g), by = headY + headR * 0.33
  parts.push(P(H(blend(2, ellipse(0, by, bw, bw * 0.45), seg(0, by, 0, by + bw * 0.95, bw * 0.5, bw * 0.12))), { relief: 2, tone: 0.35 }))

  // eyes; their height is tuned so each age's pupils land on a text row in the 56-column plate
  const er = mix(6.6, 5.5, g)
  const G1 = 0.9 / 1.9 // age 1.0
  const lift = g < G1 ? mix(5.1, 4.2, g / G1) : mix(4.2, 1.75, (g - G1) / (1 - G1))
  const blink = mood === 'idle' && Math.cos(t - 1.25 * Math.PI) > 0.97 // once a loop, on the sixth frame
  for (const side of [-1, 1]) {
    for (const p of eye(side * headR * 0.42, headY - lift, er, blink ? 'nap' : mood, { look: [0, -0.2] })) parts.push({ ...p, d: X(H(p.d)) })
  }

  return { ...size, parts }
}
