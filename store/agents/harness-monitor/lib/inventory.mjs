/** One row per machine/agent. Daemon facts are authoritative; missing readings stay unknown. */
import { homedir } from 'node:os'
import { basename, dirname } from 'node:path'
import { existsSync } from 'node:fs'
import { listAgents, machinesReport } from './bridge.mjs'
import { humanIdle } from './policy.mjs'

export function parseModel(selected) {
  if (typeof selected !== 'string' || !selected) return { model: null, effort: null }
  const body = selected.startsWith('runtime-v1:') ? selected.split(':').slice(3).join(':') : selected
  const at = body.lastIndexOf('@')
  return at <= 0 ? { model: body || null, effort: null } : { model: body.slice(0, at), effort: body.slice(at + 1) || null }
}
export function tilde(path, home = homedir()) {
  if (typeof path !== 'string' || !path) return ''
  return path === home || path.startsWith(home + '/') ? '~' + path.slice(home.length) : path
}
export function projectOf(agent) {
  const project = agent.project, cwd = project?.cwd || ''
  return { project: project?.name || basename(project?.root || cwd) || (cwd ? basename(dirname(cwd)) : '') || '—',
    cwd, branch: project?.branch || null, remote: project?.remote || null }
}
const time = value => {
  const n = typeof value === 'number' ? value : Date.parse(value)
  return Number.isFinite(n) && n > 0 ? n : null
}
const reading = value => typeof value === 'number' && Number.isFinite(value) && value >= 0 ? value : null
export const rowId = (machineId, agentId) => JSON.stringify([machineId, agentId])

export function mergeRows(agents, { state = {}, machine = null, local = true, now = Date.now(), home = homedir(), online = true } = {}) {
  return agents.map(agent => {
    const id = rowId(machine?.machineId ?? null, agent.id)
    const stopped = agent.status === 'stopped'
    const terminalAvailable = agent.terminal?.available === true && !stopped
    const { project, cwd, branch, remote } = projectOf(agent)
    // updatedAt is real conversation activity, not registry touchedAt or transcript mtime.
    const lastActivity = time(agent.updatedAt) ?? time(agent.createdAt)
    const idleMs = lastActivity == null ? null : Math.max(0, now - lastActivity)
    const monitor = agent.monitor
    let activity = !online ? 'offline' : stopped ? 'stopped'
      : agent.launch?.state === 'starting' ? 'starting'
      : agent.launch?.state === 'failed' ? (agent.launch.error === 'RESUME_UNCONFIRMED' ? 'needsInput' : 'failed')
      : monitor?.activityKnown ? monitor.activity : 'unknown'
    if (!['working', 'needsInput', 'done', 'idle', 'starting', 'failed', 'stopped', 'offline', 'unknown'].includes(activity)) activity = 'idle'
    const self = agent.dsh === 'autonomous/harness-monitor'
    const canControl = online && !self && agent.resumeMode != null && agent.launch?.state !== 'starting'
    return {
      id, agentId: agent.id, sessionId: agent.sessionId || null,
      name: agent.name || agent.title || 'Untitled harness', title: agent.title || null,
      engine: agent.engine, ...parseModel(agent.selectedModel),
      state: !online ? 'offline' : stopped ? 'paused' : terminalAvailable ? (agent.engine === 'terminal' ? 'terminal' : 'running') : 'gone',
      activity, activityKnown: monitor?.activityKnown === true,
      stateSince: lastActivity, pausedAt: stopped ? lastActivity : null,
      pane: agent.tmuxPane || null, paneTarget: null,
      project, cwd, home: local ? tilde(cwd, home) : cwd, branch, remote,
      lastActivity, idleMs, idle: idleMs == null ? '—' : humanIdle(idleMs), createdAt: time(agent.createdAt),
      attached: false, working: activity === 'working', needsInput: activity === 'needsInput',
      pinned: self || (state.pins ?? []).includes(id) || (local && (state.pins ?? []).includes(agent.id)),
      workspaceGone: local && Boolean(cwd) && !existsSync(cwd),
      rssBytes: online ? stopped ? 0 : reading(monitor?.rssBytes) : null,
      cpu: online ? stopped ? 0 : reading(monitor?.cpu) : null,
      enginePid: online && !stopped ? reading(monitor?.pid) : null,
      tokens: reading(agent.tokenUsage?.totalTokens), dsh: agent.dsh ?? null, dshName: agent.dshName ?? null,
      verdict: agent.verdict?.ready ?? null,
      machine: machine?.name ?? 'This machine', machineId: machine?.machineId ?? null,
      local, online, self, canStop: canControl && terminalAvailable,
      canOpen: online && (terminalAvailable || (stopped && agent.resumeMode != null)), resumeMode: agent.resumeMode ?? null,
      unavailable: !online ? 'Reconnect this machine.' : self ? 'Manage this assistant from its monitor tab.' : agent.launch?.detail ?? null,
    }
  })
}

/** Cache is scoped to this viewer, never an account-global singleton. Offline machines retain rows. */
export async function collect({
  state = {}, now = Date.now(), includeRemote = true, timeoutMs = 8000, home = homedir(),
  remoteIntervalMs = 15_000, remote = { at: 0, answers: new Map() },
  reportMachines = machinesReport, agentsFor = listAgents,
} = {}) {
  const report = await reportMachines()
  const machines = report.machines.filter(m => includeRemote || m.current)
  const problems = report.error ? [{ machine: 'This machine', error: report.error }] : []
  const answers = remote.answers ??= new Map()
  const failed = remote.failed ??= new Set()
  const previouslyOnline = remote.online ??= new Set()
  const due = remoteIntervalMs <= 0 || !remote.at || now - remote.at >= remoteIntervalMs
  await Promise.all(machines.filter(m => m.online && (m.current || due || !answers.has(m.machineId) || !previouslyOnline.has(m.machineId) || failed.has(m.machineId))).map(async machine => {
    try { answers.set(machine.machineId, await agentsFor(machine.machineId, { timeoutMs })); failed.delete(machine.machineId) }
    catch (error) { failed.add(machine.machineId); problems.push({ machine: machine.name, error: error.message }) }
  }))
  if (due) remote.at = now
  remote.online = new Set(machines.filter(m => !report.error && m.online).map(m => m.machineId))
  if (!report.error) {
    const known = new Set(machines.map(m => m.machineId))
    for (const id of answers.keys()) if (!known.has(id)) { answers.delete(id); failed.delete(id) }
    remote.machines = machines
  }
  const visibleMachines = report.error ? (remote.machines ?? []) : machines
  const rows = visibleMachines.flatMap(machine => mergeRows(answers.get(machine.machineId) ?? [], {
    state, machine, local: machine.current, online: !report.error && machine.online && !remote.failed.has(machine.machineId), now, home,
  }))
  for (const machine of visibleMachines.filter(m => !m.online)) problems.push({ machine: machine.name, error: 'Offline — showing the last known sessions.' })
  rows.sort((a, b) => (a.idleMs ?? Infinity) - (b.idleMs ?? Infinity) || a.id.localeCompare(b.id))
  return { rows, machines: visibleMachines, problems, observedAt: now, degraded: problems.length > 0 }
}

export function summarize(rows) {
  const by = state => rows.filter(row => row.state === state).length
  return { total: rows.length, running: by('running'), paused: by('paused'), gone: by('gone'), terminals: by('terminal'),
    needsInput: rows.filter(row => row.needsInput).length, working: rows.filter(row => row.working).length,
    held: rows.reduce((sum, row) => sum + (row.rssBytes ?? 0), 0),
    projects: new Set(rows.map(row => row.project)).size, machines: new Set(rows.map(row => row.machineId)).size }
}

export function resolveRef(ref, rows) {
  const text = String(ref ?? '').trim()
  if (!text) return { error: 'Name a harness: a row number, a %pane, an id, or part of its name.' }
  if (/^\d+$/.test(text)) return rows[Number(text) - 1] ? { row: rows[Number(text) - 1] } : { error: 'There is no row ' + text + '.' }
  const exact = rows.filter(row => row.id === text || row.agentId === text || row.id.startsWith(text) || row.agentId?.startsWith(text) || row.pane === text)
  if (exact.length === 1) return { row: exact[0] }
  if (exact.length > 1) return { error: text + ' matches ' + exact.length + ' harnesses. Use the full machine/agent id.' }
  const names = rows.filter(row => row.name.toLowerCase() === text.toLowerCase())
  if (names.length === 1) return { row: names[0] }
  const loose = rows.filter(row => (row.name + ' ' + (row.title ?? '')).toLowerCase().includes(text.toLowerCase()))
  return loose.length === 1 ? { row: loose[0] } : { error: loose.length ? text + ' matches ' + loose.length + ' harnesses.' : 'No harness matches ' + text + '.' }
}
