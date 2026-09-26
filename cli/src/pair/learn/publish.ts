/**
 * TEACH (daemons/LEARNING.md): how an approved lesson reaches the agents, without writing into any
 * engine's private folders (`~/.claude`, `~/.codex`, `.claude/skills`, `.agents/skills`, `~/.hermes` …).
 *
 *   skills  Through the Store runtime path (dsh/runtime.ts): every harness session's runtime links
 *           `<runtime>/lessons` to the lessons folder's `skills/`, and its CONTEXT.md — which every engine
 *           reads through the bootstrap — gets one index line per skill. A skill made in a project is listed
 *           only in that project's sessions. A revert takes the folder away, so the link stops reaching it at
 *           once; the index is rewritten at the next launch.
 *   notes   Into a marked `<!-- harness:lessons -->` block in the project's AGENTS.md — or CLAUDE.md when that
 *           is the one it has — ONLY when the file already exists and is a plain file. Never a new file in a
 *           repo unless the person asked for exactly that (`create`), and never through a symlink. Each
 *           note is its own marked section, so a revert removes exactly it.
 */
import { existsSync, lstatSync, readFileSync, realpathSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import type { LessonRecord, LessonStore } from './store.js'
import { projectHash } from './types.js'

/** What dsh/runtime.ts links and lists for one session. */
export interface RuntimeLessons {
  /** The lessons folder's `skills/`. */
  dir: string
  skills: Array<{ name: string; description: string }>
}

function hashesOf(dir: string): Set<string> {
  const hashes = new Set<string>()
  const plain = projectHash(dir)
  if (plain) hashes.add(plain)
  try { const real = projectHash(realpathSync(dir)); if (real) hashes.add(real) } catch { /* gone */ }
  return hashes
}

/** The approved skills a session in `workspace` loads: every one made in no project, or in this one. */
export function runtimeLessons(store: Pick<LessonStore, 'approved' | 'skillsDir'>, workspace: string): RuntimeLessons | null {
  const here = hashesOf(workspace)
  const skills = store.approved()
    .filter((r) => r.kind === 'skill' && (!r.project || here.has(r.project)))
    .map((r) => ({ name: r.name, description: r.description }))
    .sort((a, b) => a.name.localeCompare(b.name))   // a stable CONTEXT.md from launch to launch
  return skills.length ? { dir: store.skillsDir, skills } : null
}

/** A note's project folder, found among the folders harnesses run in: the store only keeps its hash. */
export function findProject(hash: string | null, folders: readonly string[]): string | null {
  if (!hash) return null
  return folders.find((folder) => hashesOf(folder).has(hash)) ?? null
}

// ── AGENTS.md notes ───────────────────────────────────────────────────────────────────────────────────

export const LESSONS_BEGIN = '<!-- harness:lessons -->'
export const LESSONS_END = '<!-- /harness:lessons -->'
const HEADER = [
  LESSONS_BEGIN,
  '## Lessons',
  '',
  'Approved in Harness from what agents did in this project. `harness pair lessons revert <id>` takes one back.',
  '',
]
const INSTRUCTION_FILES = ['AGENTS.md', 'CLAUDE.md'] as const

function isPlainFile(path: string): boolean {
  try { const stat = lstatSync(path); return stat.isFile() && !stat.isSymbolicLink() } catch { return false }
}

/** The project's instruction file a note may go in: AGENTS.md, else CLAUDE.md — an existing plain file. */
export function noteFile(projectDir: string): string | null {
  for (const name of INSTRUCTION_FILES) if (isPlainFile(join(projectDir, name))) return join(projectDir, name)
  return null
}

export type PublishResult = { ok: true; file: string; created?: boolean } | { ok: false; error: 'NO_INSTRUCTION_FILE' | 'NOT_A_FILE' | 'EDITED' | 'NOT_A_NOTE'; detail?: string }

const sectionBegin = (id: string): string => `<!-- lesson:${id} -->`
const sectionEnd = (id: string): string => `<!-- /lesson:${id} -->`

/** The block's bounds, or 'edited' when its markers are not exactly one pair in order. */
function block(text: string): { start: number; end: number } | null | 'edited' {
  const starts = text.split(LESSONS_BEGIN).length - 1
  const ends = text.split(LESSONS_END).length - 1
  if (!starts && !ends) return null
  if (starts !== 1 || ends !== 1) return 'edited'
  const start = text.indexOf(LESSONS_BEGIN)
  const end = text.indexOf(LESSONS_END)
  return end > start ? { start, end: end + LESSONS_END.length } : 'edited'
}

/**
 * Write a note into the project's block. Only into a file that exists, unless `create` (the person asked
 * for a new AGENTS.md by name). Every byte outside the block is kept.
 */
export function publishNote(projectDir: string, record: LessonRecord, opts: { create?: boolean } = {}): PublishResult {
  if (record.kind !== 'note') return { ok: false, error: 'NOT_A_NOTE' }
  let file = noteFile(projectDir)
  let created = false
  if (!file) {
    const blocked = INSTRUCTION_FILES.map((name) => join(projectDir, name)).find((path) => existsSync(path) || isLink(path))
    if (blocked) return { ok: false, error: 'NOT_A_FILE', detail: `${blocked} is not a plain file` }
    if (!opts.create) return { ok: false, error: 'NO_INSTRUCTION_FILE', detail: 'the project has no AGENTS.md or CLAUDE.md' }
    file = join(projectDir, 'AGENTS.md')
    created = true
  }
  const before = created ? '' : readFileSync(file, 'utf8')
  const found = block(before)
  if (found === 'edited') return { ok: false, error: 'EDITED', detail: `the ${LESSONS_BEGIN} block in ${file} was edited; fix its markers first` }
  const section = [sectionBegin(record.id), ...(record.lines ?? [record.description]).map((line) => `- ${line}`), sectionEnd(record.id)].join('\n')
  let after: string
  if (!found) {
    const lead = !before ? '' : before.endsWith('\n\n') ? '' : before.endsWith('\n') ? '\n' : '\n\n'
    after = `${before}${lead}${[...HEADER, section, LESSONS_END].join('\n')}\n`
  } else {
    const inner = withoutSection(before.slice(found.start, found.end), record.id)
    const at = inner.lastIndexOf(LESSONS_END)
    after = `${before.slice(0, found.start)}${inner.slice(0, at)}${section}\n${inner.slice(at)}${before.slice(found.end)}`
  }
  writeFileSync(file, after, created ? { flag: 'wx', mode: 0o644 } : {})
  return { ok: true, file, ...(created ? { created: true } : {}) }
}

/** Take one note back out; the whole block goes with its last note. Nothing else in the file changes. */
export function unpublishNote(projectDir: string, id: string): { ok: true; file: string | null } | { ok: false; error: 'EDITED'; detail: string } {
  for (const name of INSTRUCTION_FILES) {
    const file = join(projectDir, name)
    if (!isPlainFile(file)) continue
    const before = readFileSync(file, 'utf8')
    if (!before.includes(sectionBegin(id))) continue
    const found = block(before)
    if (!found || found === 'edited') return { ok: false, error: 'EDITED', detail: `the ${LESSONS_BEGIN} block in ${file} was edited; remove lesson ${id} by hand` }
    const inner = withoutSection(before.slice(found.start, found.end), id)
    const empty = !/<!-- lesson:[a-f0-9]+ -->/.test(inner)
    let after: string
    if (empty) {
      const head = before.slice(0, found.start).replace(/\n\n$/, '\n')
      const tail = before.slice(found.end).replace(/^\n/, '')
      after = `${head}${tail}`
    } else after = `${before.slice(0, found.start)}${inner}${before.slice(found.end)}`
    writeFileSync(file, after)
    return { ok: true, file }
  }
  return { ok: true, file: null }
}

function withoutSection(text: string, id: string): string {
  const begin = text.indexOf(sectionBegin(id))
  if (begin < 0) return text
  const endMarker = sectionEnd(id)
  const end = text.indexOf(endMarker, begin)
  if (end < 0) return text
  const stop = end + endMarker.length + (text[end + endMarker.length] === '\n' ? 1 : 0)
  return `${text.slice(0, begin)}${text.slice(stop)}`
}

function isLink(path: string): boolean {
  try { return lstatSync(path).isSymbolicLink() } catch { return false }
}
