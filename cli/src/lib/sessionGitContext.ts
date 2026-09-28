import { stat } from 'node:fs/promises'
import { randomUUID } from 'node:crypto'
import { sep } from 'node:path'
import { agentProject, type AgentProject } from './agentProject.js'
import type { SessionWork, WorkPullRequest } from './sessionWork.js'
import type { GitHistory } from './sessionGitHistory.js'

export type SessionGitContext = {
  state: 'workspace' | 'observed' | 'multiple' | 'uncertain' | 'unavailable'
  current: AgentProject | null
  observedAt: string | null
  /** The location is confirmed historical work; newer tool activity could not yet be resolved. */
  activityUncertain?: boolean
  /** Paths describe observed work, never worktree ownership or deletion eligibility. */
  locations: Array<{ cwd: string; at: string }>
  pullRequests: WorkPullRequest[]
  truncated: boolean
  history?: GitHistory
  /** Changes only with the display snapshot; clients reject older list/push responses. */
  version?: { epoch: string; revision: number }
}

/** Overlapping projections all finish with the newest requested observation. Versions survive
 * cache eviction within a daemon, and do not advance during unchanged roster polling. */
export class SessionGitContextReader {
  private epoch = randomUUID()
  private revision = 0
  private entries = new Map<string, { pending: Promise<SessionGitContext>; users: number; json?: string; value?: SessionGitContext }>()
  async read(key: string, resolve: () => Promise<SessionGitContext>): Promise<SessionGitContext> {
    const pending = resolve()
    let entry = this.entries.get(key)
    if (!entry) {
      entry = { pending, users: 0 }
      this.entries.set(key, entry)
    }
    entry.pending = pending
    entry.users++
    try {
      let selected: Promise<SessionGitContext>, value: SessionGitContext
      do { selected = entry.pending; value = await selected } while (selected !== entry.pending)
      const json = JSON.stringify(value)
      if (entry.json !== json) {
        entry.json = json
        entry.value = { ...value, version: { epoch: this.epoch, revision: ++this.revision } }
      }
      return entry.value!
    } finally {
      entry.users--
      // Never evict an entry while an older projection still references it.
      for (const [oldKey, old] of this.entries) {
        if (this.entries.size <= 512) break
        if (!old.users) this.entries.delete(oldKey)
      }
    }
  }
}
type Inspect = (cwd: string) => Promise<AgentProject | null>
async function inspect(cwd: string): Promise<AgentProject | null> {
  if (!(await stat(cwd).catch(() => null))?.isDirectory()) return null
  return agentProject(cwd)
}

/** Display-only projection. Registry cwd and the legacy project keep their launch semantics. */
export async function sessionGitContext(home: AgentProject | null, work?: SessionWork | null,
  read: Inspect = inspect): Promise<SessionGitContext> {
  const context: SessionGitContext = {
    state: 'workspace', current: home, observedAt: null,
    locations: work?.locations ?? [], pullRequests: work?.pullRequests ?? [], truncated: work?.truncated ?? false,
  }
  if (!work) return context
  context.current = null
  context.observedAt = work.current.reduce<string | null>((at, row) => at && at > row.at ? at : row.at, null)
  if (!work.current.length) return { ...context, state: 'uncertain' }
  if (work.uncertain) context.activityUncertain = true
  // One tool can touch many folders. Resolve only a bounded set; exceeding it cannot imply one.
  if (work.current.length > 8) return { ...context, state: 'multiple', truncated: true }
  const projects = await Promise.all(work.current.map(row => read(row.cwd).catch(() => null)))
  if (projects.some(p => !p)) return { ...context, state: 'unavailable' }
  const roots = new Map<string, AgentProject>()
  for (const project of projects) if (project) roots.set(project.root ?? project.cwd, project)
  // Different files in one checkout are one useful workspace in the details view. Only collapse
  // paths under roots Git actually resolved; similarly named sibling worktrees remain distinct.
  const knownRoots = [...new Set([...roots.values()].flatMap(p => p.root ? [p.root] : []))].sort((a, b) => b.length - a.length)
  const locations = new Map<string, { cwd: string; at: string }>()
  for (const row of context.locations) {
    const cwd = knownRoots.find(root => row.cwd === root || row.cwd.startsWith(root.endsWith(sep) ? root : root + sep)) ?? row.cwd
    const previous = locations.get(cwd)
    if (!previous || previous.at < row.at) locations.set(cwd, { ...row, cwd })
  }
  context.locations = [...locations.values()].sort((a, b) => b.at.localeCompare(a.at))
  if (roots.size !== 1) return { ...context, state: 'multiple' }
  const project = [...roots.values()][0]
  // Working on src/ or tui/ should still identify the checkout, independent of the last file tool.
  context.current = project.root ? { ...project, cwd: project.root } : project
  return { ...context, state: 'observed' }
}
