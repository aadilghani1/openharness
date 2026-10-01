/** UI contracts mirror desktop HarnessActivity/EngineMark; pure sorting is shared with tests. */
export const ACTIVITY = {
  needsInput: ['?', 'Needs you'], failed: ['✗', 'Failed'], done: ['✓', 'Done'], working: ['⠋', 'Working'],
  starting: ['◌', 'Starting'], idle: ['', 'Idle'], stopped: ['Ⅱ', 'Stopped'], offline: ['⊘', 'Offline'], unknown: ['—', 'Unknown'],
}
export const SPINNER = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏']
export const COLUMNS = [
  { key: 'name', label: 'Harness', width: 280, required: true },
  { key: 'activity', label: 'Status', width: 116 }, { key: 'engine', label: 'Agent', width: 114 },
  { key: 'machine', label: 'Machine', width: 104 }, { key: 'project', label: 'Project', width: 180 },
  { key: 'branch', label: 'Branch', width: 184 },
  { key: 'cpu', label: 'CPU %', width: 86, numeric: true, help: 'Process tree CPU, as reported by ps. Can exceed 100% across cores; averaging varies by OS.' },
  { key: 'rssBytes', label: 'RAM', width: 92, numeric: true, help: 'Resident memory of the engine and its child processes. Shared pages may be counted more than once.' },
  { key: 'tokens', label: 'Tokens', width: 86, numeric: true },
  { key: 'lastActivity', label: 'Last active', width: 128, numeric: true },
  { key: 'model', label: 'Model', width: 190, optional: true },
  { key: 'enginePid', label: 'PID', width: 80, numeric: true, optional: true },
  { key: 'agentId', label: 'Harness ID', width: 220, optional: true },
  { key: 'sessionId', label: 'Conversation ID', width: 220, optional: true },
  { key: 'home', label: 'Folder', width: 240, optional: true },
  { key: 'actions', label: '', width: 100, required: true },
]
export function visibleRows(rows, { query = '', filter = 'all', sort = 'lastActivity', direction = -1 } = {}) {
  const q = query.trim().toLocaleLowerCase()
  const rank = Object.keys(ACTIVITY)
  return rows.filter(row => (filter === 'all' || row.activity === filter) && (!q ||
    [row.name, row.title, row.engine, row.machine, row.project, row.branch, row.model, row.agentId, row.sessionId, row.home].some(v => v?.toLocaleLowerCase().includes(q))))
    .sort((a, b) => {
      let av = a[sort], bv = b[sort]
      if (av == null && bv != null) return 1
      if (bv == null && av != null) return -1
      if (sort === 'activity') { av = rank.indexOf(av); bv = rank.indexOf(bv) }
      const compared = typeof av === 'number' && typeof bv === 'number' ? av - bv : String(av ?? '').localeCompare(String(bv ?? ''), undefined, { numeric: true })
      return compared * direction || a.id.localeCompare(b.id)
    })
}
export const number = n => n == null ? '—' : Intl.NumberFormat('en', { notation: 'compact', maximumFractionDigits: 1 }).format(n)
export const memory = n => n == null ? '—' : n >= 1024 ** 3 ? (n / 1024 ** 3).toFixed(1) + ' GB' : Math.round(n / 1024 ** 2) + ' MB'
export const age = (stamp, now = Date.now()) => {
  if (stamp == null) return '—'
  const s = Math.max(0, (now - stamp) / 1000)
  return s < 60 ? 'now' : s < 3600 ? Math.floor(s / 60) + 'm ago' : s < 86400 ? Math.floor(s / 3600) + 'h ago' : Math.floor(s / 86400) + 'd ago'
}
