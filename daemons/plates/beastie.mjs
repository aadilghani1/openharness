import { circle, ellipse, box, seg, tube, path, union, cut, blend, part, eye } from '../tools/plate.mjs'

// beastie: say "BSD" fast and you get "beastie", the Berkeley daemon; the whole collection is named
// after daemons, Unix's background processes, and this is the first one.
export const size = { w: 100, h: 86 }

const FLOOR = 84, CX = 54

// A simple polygon (convex or not), for arrowheads and fangs (iq's polygon distance).
function poly(pts) {
  return (x, y) => {
    let d = (x - pts[0][0]) ** 2 + (y - pts[0][1]) ** 2, s = 1
    for (let i = 0, j = pts.length - 1; i < pts.length; j = i, i++) {
      const [ax, ay] = pts[i], [bx, by] = pts[j]
      const ex = bx - ax, ey = by - ay, wx = x - ax, wy = y - ay
      const h = Math.max(0, Math.min(1, (wx * ex + wy * ey) / (ex * ex + ey * ey)))
      const qx = wx - ex * h, qy = wy - ey * h
      d = Math.min(d, qx * qx + qy * qy)
      const c1 = y >= ay, c2 = y < by, c3 = ex * wy > ey * wx
      if ((c1 && c2 && c3) || (!c1 && !c2 && !c3)) s = -s
    }
    return s * Math.sqrt(d)
  }
}

// An arrowhead whose back sits at (x, y), pointing along `a`: `len` long, its barbs `wide` apart,
// a notch cut into the back. The tail's spade and the trident's points.
function arrow(x, y, a, len, wide, notch = 0.3) {
  const c = Math.cos(a), s = Math.sin(a), px = -s, py = c
  return poly([
    [x + c * len, y + s * len],
    [x + px * wide / 2, y + py * wide / 2],
    [x + c * len * notch, y + s * len * notch],
    [x - px * wide / 2, y - py * wide / 2],
  ])
}

// Growth 0 (hatchling) to 1 (full grown), and a value that runs baby -> young -> adult along it.
const growth = (age) => { const a = +age; return a <= 1 ? Math.max(0, (a - 0.1) / 0.9) * 0.5 : 0.5 + Math.min(1, a - 1) * 0.5 }
const by = (g, baby, young, adult) => (g < 0.5 ? baby + (young - baby) * (g / 0.5) : young + (adult - young) * ((g - 0.5) / 0.5))

export function model({ t = 0, mood = 'idle', age = '2.0' } = {}) {
  const g = growth(age)
  const k = by(g, 0.66, 0.82, 1) // overall scale; the model below is in local units, feet on y = 0
  const droop = mood === 'fail' ? 1 : mood === 'nap' ? 0.5 : 0 // ears and tail hang
  const perk = mood === 'need' || mood === 'boop' ? 1 : 0 // ears up
  const hop = mood === 'done' ? 4 : 0 // a hop for joy; the trident stays planted and the hand slides
  const lift = 0.35 * Math.sin(t) // breathing
  const tap = 2.2 * Math.max(0, Math.sin(2 * t)) * (1 - droop) // the trident rises and taps the floor, twice a loop
  const flick = (Math.sin(t) + 0.45 * Math.sin(2 * t)) * (1 - 0.6 * droop) // the tail's sway, snappier at the turn

  // ---- body plan
  const headY = by(g, -37, -43, -47.4) - lift, headRx = by(g, 21, 20.5, 20.5), headRy = by(g, 17.5, 16.8, 17.2)
  const bodyY = by(g, -13.5, -17.5, -20) - lift * 0.8, bodyRx = by(g, 10.5, 10.8, 11), bodyRy = by(g, 9, 10.5, 11.5)
  const hipY = bodyY + bodyRy * 0.7, shY = bodyY - bodyRy * 0.55

  const legs = [-1, 1].map((sd) => blend(2,
    seg(sd * 4.8, hipY, sd * 6, -3, 3.5, 2.7),
    seg(sd * 5, -2.4, sd * 11.5, -1.6, 2.7, 0.9)))
  const body = ellipse(0, bodyY, bodyRx, bodyRy)
  const belly = ellipse(-0.8, bodyY + bodyRy * 0.2, bodyRx * 0.6, bodyRy * 0.62)

  // ---- the tail: out behind the left hip, a dip, then up in a swoop, ending in the spade.
  // Proud (up) and limp (along the floor) curves, mixed by droop.
  const mix = (a, b) => a + (b - a) * droop
  const tailLen = by(g, 21, 35, 47) * mix(1, 0.86)
  const tailPts = path(-6, hipY - 1.5, Math.PI - mix(0.7, 0.85) + 0.045 * flick, tailLen,
    (u) => mix(u < 0.3 ? 0.058 : u < 0.7 ? 0.026 : 0.07, u < 0.3 ? 0.01 : u < 0.6 ? 0.075 : 0.03) * (47 / tailLen) + 0.01 * flick * u * u)
  const [tx, ty] = tailPts[tailPts.length - 1], [qx, qy] = tailPts[tailPts.length - 4]
  const tailA = Math.atan2(ty - qy, tx - qx)
  const tail = tube(tailPts, by(g, 1.5, 1.7, 1.8), by(g, 1, 1.05, 1.1))
  const spade = arrow(tx - Math.cos(tailA) * 1.5, ty - Math.sin(tailA) * 1.5, tailA, by(g, 5, 9, 12), by(g, 5, 9, 11))

  // ---- the trident, planted at arm's length; a toy fork for the hatchling
  const fx = by(g, 28.5, 30, 31), top = by(g, -25, -56, -62.4) - tap + hop, foot = -0.4 - tap + hop // stays planted through a hop
  const prong = by(g, 5, 8, 10), spread = by(g, 4.6, 6.4, 7.6), sr = by(g, 1.1, 1.2, 1.3)
  const sideTop = top - prong * 0.5
  const yoke = tube([[fx - spread, sideTop], [fx - spread * 0.9, top + 0.6], [fx - spread * 0.5, top + 1.8], [fx, top + 2.1], [fx + spread * 0.5, top + 1.8], [fx + spread * 0.9, top + 0.6], [fx + spread, sideTop]], sr)
  const tipL = by(g, 4.4, 6.4, 8), tipW = by(g, 4, 5.6, 6.8)
  const trident = union(
    seg(fx, foot, fx, top, sr * 1.1, sr),
    yoke,
    seg(fx, top, fx, top - prong, sr),
    arrow(fx, top - prong + 0.5, -Math.PI / 2, tipL, tipW),
    arrow(fx - spread, sideTop + 0.5, -Math.PI / 2 - 0.1, tipL * 0.85, tipW * 0.9),
    arrow(fx + spread, sideTop + 0.5, -Math.PI / 2 + 0.1, tipL * 0.85, tipW * 0.9),
    box(fx, top + 4, sr * 1.8, 0.9))

  // ---- arms: one to the trident, one fist on the hip
  const armR = by(g, 2.4, 2.5, 2.7)
  const handY = by(g, -14, -24, -30) - tap * 0.9 - lift * 0.3
  const reach = tube([[bodyRx * 0.7, shY], [bodyRx * 0.7 + (fx - bodyRx) * 0.45, shY + 4.5], [fx - 1.5, handY + 0.5]], armR, armR * 0.85)
  const hand = circle(fx - 0.2, handY, armR * 1.3)
  const akimbo = union(
    tube([[-bodyRx * 0.7, shY], [-bodyRx - 6, shY + 5.5], [-bodyRx + 1.4, hipY - 2.5]], armR, armR * 0.85),
    circle(-bodyRx + 1.6, hipY - 2.6, armR * 1.2))

  // ---- head, ears, horns
  const earA = -0.82 - 0.25 * perk + 1.05 * droop
  const earLen = by(g, 9, 13, 15)
  const ears = [-1, 1].map((sd) => {
    const bx = sd * headRx * 0.8, byy = headY - 0.5
    const a = sd > 0 ? earA : Math.PI - earA
    const at = (f) => [bx + Math.cos(a) * earLen * f, byy + Math.sin(a) * earLen * f]
    return {
      d: seg(bx, byy, ...at(1), by(g, 5.2, 5.5, 5.8), 0.35),
      inner: seg(...at(0.3), ...at(0.78), 2, 0.3),
    }
  })
  const hornLen = by(g, 4, 9, 13.5)
  const horns = [-1, 1].map((sd) => {
    const bx = sd * headRx * 0.46, byy = headY - headRy * 0.8
    return tube(path(bx, byy, -Math.PI / 2 + sd * 0.6, hornLen, () => -sd * (hornLen > 6 ? 0.1 : 0.05) * (13.5 / hornLen)),
      by(g, 3.2, 3.6, 4), by(g, 1.8, 0.9, 0.5))
  })
  const head = blend(6, ellipse(0, headY, headRx, headRy), ellipse(0, headY + headRy * 0.45, headRx * 0.72, headRy * 0.55))

  // ---- the face
  const er = by(g, 6.6, 6.3, 6.1), ex = by(g, 8.6, 8.6, 8.6), ey = headY - by(g, 1.5, 2.4, 2.6)
  const eyes = [-1, 1].flatMap((sd) => eye(ex * sd, ey, er, mood, { look: [0.25, 0] }))
  const my = headY + by(g, 7.4, 6.9, 6.8)
  const dark = (d) => part(d, { tone: 0.05, ink: false })
  const lit = (d, tone = 1) => part(d, { tone, ink: false })
  const face = []
  if (mood === 'need') face.push(dark(ellipse(0.5, my + 0.6, 2.8, 2.8)))
  else if (mood === 'fail') face.push(dark(cut(ellipse(0.5, my + 4.4, 8, 5), ellipse(0.5, my + 8.2, 9.5, 5))))
  else if (mood === 'nap') face.push(dark(cut(ellipse(0.5, my - 0.6, 5, 2.8), ellipse(0.5, my - 2.4, 5.8, 2.8))))
  else {
    const w = mood === 'work' ? 7 : 10.5
    face.push(dark(cut(ellipse(0.8, my - 1.2, w, 6.4, -0.1), ellipse(0.6, my - 8.4, w + 2.5, 6.6, -0.1))))
    if (mood === 'work') face.push(lit(ellipse(5.2, my + 1.6, 1.8, 2.2, -0.4), 0.72)) // tongue out, concentrating
    else face.push(lit(poly([[1.4, my - 1.8], [5.6, my - 2.1], [3.8, my + 2.4]]))) // one fang
  }
  // brows only when it concentrates (knitted, inner ends down) or fails (worried, inner ends up)
  const slant = mood === 'work' ? 1.2 : -1.2, bY = ey - er - 2
  const brows = mood !== 'work' && mood !== 'fail' ? [] : [-1, 1].map((sd) =>
    dark(seg(sd * (ex + 3.4), bY - slant, sd * (ex - 2.8), bY + slant, 1.1)))

  const parts = [
    part(tail, { relief: 1.8, tone: 0.84 }),
    part(spade, { relief: 3, tone: 0.96, ink: false }),
    part(trident, { relief: 1.4, tone: 1 }),
    ...legs.map((d) => part(d, { relief: 3, tone: 0.8 })),
    part(body, { relief: 8, tone: 0.86 }),
    part(belly, { relief: 5, tone: 0.96, ink: false }),
    part(akimbo, { relief: 2.4, tone: 0.9 }),
    part(reach, { relief: 2.4, tone: 0.9 }),
    part(hand, { relief: 2.4, tone: 0.94 }),
    ...ears.flatMap((e) => [part(e.d, { relief: 3, tone: 0.88 }), part(e.inner, { tone: 0.4, ink: false })]),
    ...horns.map((d) => part(d, { relief: 2.2, tone: 1, tex: (x, y) => 0.86 + 0.14 * Math.sin(y * 2.2) })),
    part(head, { relief: 12, tone: 0.95 }),
    ...eyes, ...face, ...brows,
  ]
  // place the local model on the canvas: centred, feet on the floor, smaller when younger
  const place = (d) => (x, y) => d((x - CX) / k, (y - FLOOR) / k + hop) * k
  return {
    ...size,
    parts: parts.map((p) => ({ ...p, d: place(p.d), relief: p.relief && p.relief * k, tex: p.tex && ((x, y) => p.tex((x - CX) / k, (y - FLOOR) / k + hop)) })),
  }
}
