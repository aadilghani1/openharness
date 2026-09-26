// The reference renderer for daemons/roster.json. The desktop (Dart) and hn (Rust) ports must draw
// exactly what this draws; daemons/tools/frames.test.mjs pins the frames they are checked against.
//
// Placeholders in sprites and portraits:
//   {e}          an eye: the mood's eye, or the lid while blinking (never in noBlinkMoods)
//   {<part>}     a moving part (d.parts): its `rest` glyph, or a frame of `work` every `ms` while working
//   {<moodPart>} a mood-driven part (d.moodParts): its value for the mood, else its idle value

export function eyeFor(roster, d, mood) {
  if (d.eyes && d.eyes[mood] != null) return d.eyes[mood]
  return roster.rules.eyes[mood] ?? 'o'
}

function fill(tpl, roster, d, mood, { t = 0, lid = null, motion = true } = {}) {
  const blinking = lid && !roster.rules.noBlinkMoods.includes(mood)
  const eye = blinking ? (d.lid ?? lid) : eyeFor(roster, d, mood)
  const moving = motion && mood === 'work'
  return tpl.replace(/\{([a-zA-Z]+)\}/g, (whole, key) => {
    if (key === 'e') return eye
    const mp = d.moodParts?.[key]
    if (mp) return mp[mood] ?? mp.idle
    const part = d.parts?.[key]
    if (part) return moving ? part.work[Math.floor(t / part.ms) % part.work.length] : part.rest
    return whole
  })
}

/** One line for the status bar. versionIndex is 0, 1 or 2 (0.1, 1.0, 2.0); t is milliseconds. */
export function renderSprite(roster, d, versionIndex, mood, { t = 0, lid = null, motion = true } = {}) {
  const { versions, statusCells, backFrameMs } = roster.rules
  const last = versions.length - 1
  const moving = motion && (mood === 'work' || mood === 'back')
  let tpl = d.sprites[versions[versionIndex]]
  if (moving && versionIndex === last) {
    const ms = mood === 'back' ? backFrameMs : d.workMs
    tpl = d.work[Math.floor(t / ms) % d.work.length]
  }
  let s = fill(tpl, roster, d, mood, { t, lid, motion: false })
  // Younger versions have no moving part yet; they borrow the twirling baton.
  if (moving && versionIndex < last && s.length <= statusCells - 2) s += ' ' + '|/-\\'[Math.floor(t / 130) % 4]
  if (mood === 'nap' && s.length < statusCells) s += 'z'
  return s
}

/** The portrait for a version, falling back to the nearest one drawn. */
export function portraitFor(roster, d, version) {
  if (d.portraits[version]) return d.portraits[version]
  const drawn = roster.rules.versions.filter(v => d.portraits[v])
  const at = roster.rules.versions.indexOf(version)
  const below = drawn.filter(v => roster.rules.versions.indexOf(v) <= at)
  return d.portraits[below.length ? below[below.length - 1] : drawn[0]]
}

export function renderPortrait(roster, d, version, mood, { t = 0, lid = null, motion = true } = {}) {
  return portraitFor(roster, d, version).map(line => fill(line, roster, d, mood, { t, lid, motion }))
}

/** The status cell: the sprite centred in statusCells, with one cell of gutter each side. */
export function statusCell(roster, sprite) {
  const pad = roster.rules.statusCells - sprite.length
  return ' ' + ' '.repeat(Math.max(0, Math.floor(pad / 2))) + sprite + ' '.repeat(Math.max(0, Math.ceil(pad / 2))) + ' '
}
