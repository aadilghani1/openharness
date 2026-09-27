// Generated from daemons/plates/tim.mjs by daemons/tools/generate.mjs. Do not edit.
// @ts-nocheck
import { ellipse, tube, path, blend, part, eye } from './plate.g.js'

// tim, the octopus: tmux improved, the way vim is vi improved. Eight arms, eight panes. It will do
// git's octopus merge too, which takes more than two branches at once.
export const size = { w: 114, h: 96 }

// One arm per row: where it leaves the body (x from the middle, y), its heading (0 = right,
// PI/2 = down, left side), its length, the curl in its last stretch (positive turns up and out),
// how much it waves, and its phase.
const ARMS = [
  { x: -22, y: 43, a: Math.PI + 0.35, len: 32, curl: 9, wave: 0.4, ph: 0.0 },
  { x: -16, y: 49, a: 2.3, len: 44, curl: -4.6, wave: 0.6, ph: 1.4 },
  { x: -9, y: 53, a: 1.95, len: 40, curl: 4.4, wave: 1.2, ph: 2.3 },
  { x: -3, y: 54, a: 1.66, len: 38, curl: -4.8, wave: 1.4, ph: 3.1 },
]

// Growth: a hatchling is mostly head with stubby arms; each version is drawn smaller and set on
// the same floor.
const AGES = { '0.1': { s: 0.56, arm: 0.42 }, '1.0': { s: 0.8, arm: 0.72 }, '2.0': { s: 1, arm: 1 } }

// Mood body language: the top arms go up for joy and alarm, everything droops on a failure.
const LIFT = { done: -0.35, back: -0.35, need: -0.5, boop: -0.3, fail: 0.4, nap: 0.2 }

export function model({ t = 0, mood = 'idle', age = '2.0' } = {}) {
  const g = AGES[age] ?? AGES['2.0']
  const cx = 57, lift = LIFT[mood] ?? 0
  const back = [], front = []
  for (const side of [-1, 1]) {
    for (const [i, arm] of ARMS.entries()) {
      const sway = Math.sin(t + arm.ph + (side > 0 ? 1.1 : 0))
      const a = arm.a + (i === 0 ? lift : lift * 0.35)
      const heading = side < 0 ? a : Math.PI - a
      const s = side < 0 ? 1 : -1
      // a gentle S along the arm, then a tight spiral at the tip
      const bend = (u) => s * (arm.wave * 0.06 * Math.sin(u * Math.PI * 2 + sway) + (arm.curl * 0.05 * Math.pow(Math.max(0, u - 0.45) / 0.55, 2) * (1 + 0.25 * sway)) / g.arm)
      const pts = path(cx - side * arm.x, arm.y, heading + s * 0.08 * sway, arm.len * g.arm, bend)
      ;(i < 2 ? back : front).push(part(tube(pts, 4.2, 0.7 + (1 - g.arm) * 1.6), { relief: 3.5, tone: 0.86 }))
    }
  }
  const breath = 1 + 0.025 * Math.sin(t)
  const head = blend(10, ellipse(cx, 21, 29 * breath, 22 * breath), ellipse(cx, 40, 21, 10))
  const eyes = [-1, 1].flatMap((side) => eye(cx + side * 12, 39, 9.5, mood, { look: [-side, 0.3] }))
  const parts = [...back, ...front.reverse(), part(head, { relief: 8, tone: 0.8 }), ...eyes]
  return { ...size, parts: g.s === 1 ? parts : parts.map((p) => scaled(p, g.s, cx, 92)) }
}

// A part drawn at scale s about (px, py).
function scaled(p, s, px, py) {
  const from = (x, y) => [px + (x - px) / s, py + (y - py) / s]
  return { ...p, d: (x, y) => s * p.d(...from(x, y)), tex: p.tex && ((x, y) => p.tex(...from(x, y))) }
}
