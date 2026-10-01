import { ACTIVITY, SPINNER, COLUMNS, visibleRows, number, memory, age } from './table.js'
const el = id => document.getElementById(id)
const dom = {
  search: el('search'), filter: el('filter'), columns: el('columns'), columnOptions: el('column-options'),
  grid: el('grid'), table: el('table'), colgroup: el('colgroup'), head: el('head'), body: el('body'),
  empty: el('empty'), count: el('count'), message: el('message'), updated: el('updated'), problems: el('problems'),
  assistant: el('assistant'), choice: el('assistant-choice'), free: el('assistant-free'), other: el('assistant-other'), cancel: el('assistant-cancel'),
  refresh: el('refresh'), cleanup: el('cleanup'), cleanupDialog: el('cleanup-dialog'), cleanupPlan: el('cleanup-plan'),
  cleanupSummary: el('cleanup-summary'), cleanupCancel: el('cleanup-cancel'), cleanupApply: el('cleanup-apply'),
}
const token = document.querySelector('meta[name="hps-token"]').content
let saved = {}
try { saved = JSON.parse(localStorage.getItem('harness-monitor.table.v2') || '{}') } catch { /* private browsing */ }
const state = {
  rows: [], snapshot: null, query: typeof saved.query === 'string' ? saved.query : '',
  filter: ['all', ...Object.keys(ACTIVITY)].includes(saved.filter) ? saved.filter : 'all',
  sort: COLUMNS.some(c => c.key === saved.sort && c.key !== 'actions') ? saved.sort : 'lastActivity', direction: saved.direction === 1 ? 1 : -1,
  visible: new Set(Array.isArray(saved.visible) ? saved.visible : COLUMNS.filter(c => !c.optional).map(c => c.key)),
  widths: {}, selected: null, busy: new Set(), cleanupIds: [], cleanupRows: [], nodes: new Map(), shown: [], assistantIntroSeen: saved.assistantIntroSeen === true,
}
for (const col of COLUMNS) state.widths[col.key] = Math.max(64, Math.min(600, Number(saved.widths?.[col.key]) || col.width))
const text = (node, value) => { if (node.textContent !== String(value)) node.textContent = value }
function persist() {
  try { localStorage.setItem('harness-monitor.table.v2', JSON.stringify({ query: state.query, filter: state.filter, sort: state.sort, direction: state.direction, visible: [...state.visible], widths: state.widths, assistantIntroSeen: state.assistantIntroSeen })) } catch { /* optional */ }
}
function element(tag, value, className) {
  const node = document.createElement(tag)
  if (value != null) node.textContent = value
  if (className) node.className = className
  return node
}
function message(value) { text(dom.message, value) }
async function post(path, payload) {
  const response = await fetch(path, { method: 'POST', headers: { 'content-type': 'application/json', 'x-hps-token': token }, body: JSON.stringify(payload) })
  const result = await response.json()
  if (!response.ok || result.error) throw new Error(result.error || 'Request failed. Refresh and try again.')
  return result
}
// Both the native webview and the remote viewer renderer consume this small, bounded navigation queue.
// No scripts, prompts, process controls or paths cross the host bridge.
window.harnessHostQueue = []
function host(action) {
  if (window.HarnessHost?.postMessage) window.HarnessHost.postMessage(JSON.stringify(action))
  else if (window.harnessEmbedded) {
    if (window.harnessHostQueue.length < 8) window.harnessHostQueue.push(action)
  } else { message('Open this viewer inside Harness to use this action.'); return false }
  return true
}
function openRow(id) {
  const row = state.rows.find(r => r.id === id)
  if (!row?.canOpen || state.busy.has(id)) return
  host({ action: 'open', machineId: row.machineId, agentId: row.agentId })
}
async function stopRows(ids, manual) {
  const expected = (manual ? state.rows : state.cleanupRows).filter(row => ids.includes(row.id)).map(({ id, sessionId, lastActivity }) => ({ id, sessionId, lastActivity }))
  ids.forEach(id => state.busy.add(id)); render()
  try {
    const reply = await post('/api/act', { verb: 'pause', ids, manual, expected })
    const failures = reply.results.filter(r => !r.ok)
    message(failures.length ? failures.map(r => r.name + ': ' + r.detail).join(' · ') : (reply.results.length === 1 ? 'Stopped. History retained.' : reply.results.length + ' sessions stopped.'))
  } catch (error) { message(error.message) }
  finally { ids.forEach(id => state.busy.delete(id)); render() }
}
const activeColumns = () => COLUMNS.filter(c => c.required || state.visible.has(c.key))
function resizeColumns() {
  for (const col of dom.colgroup.children) col.style.width = state.widths[col.dataset.key] + 'px'
  for (const header of dom.head.querySelectorAll('th[data-key]')) {
    const grip = header.querySelector('.resize')
    if (grip) { grip.setAttribute('aria-valuemin', '64'); grip.setAttribute('aria-valuemax', '600'); grip.setAttribute('aria-valuenow', String(state.widths[header.dataset.key])) }
  }
  dom.table.style.width = activeColumns().reduce((sum, c) => sum + state.widths[c.key], 0) + 'px'
}
function buildColumns() {
  dom.colgroup.replaceChildren(); dom.head.replaceChildren(); state.nodes.clear(); dom.body.replaceChildren()
  const tr = element('tr')
  for (const col of activeColumns()) {
    const width = element('col'); width.dataset.key = col.key; dom.colgroup.append(width)
    const th = element('th', null, col.numeric ? 'numeric' : ''); th.scope = 'col'; th.dataset.key = col.key
    if (col.key !== 'actions') {
      const sort = element('button', col.label); sort.type = 'button'; sort.title = col.help || 'Sort by ' + col.label
      sort.onclick = () => { state.direction = state.sort === col.key ? -state.direction : col.numeric ? -1 : 1; state.sort = col.key; persist(); render() }
      th.append(sort)
      const grip = element('span', null, 'resize'); grip.tabIndex = 0; grip.role = 'separator'; grip.setAttribute('aria-orientation', 'vertical'); grip.setAttribute('aria-label', 'Resize ' + col.label)
      const change = width => { state.widths[col.key] = Math.max(64, Math.min(600, width)); resizeColumns() }
      grip.onpointerdown = event => {
        event.preventDefault(); const start = event.clientX, width = state.widths[col.key]
        grip.setPointerCapture(event.pointerId)
        grip.onpointermove = move => change(width + move.clientX - start)
        grip.onpointerup = () => { grip.onpointermove = null; persist() }
        grip.onpointercancel = () => { grip.onpointermove = null; persist() }
      }
      grip.onkeydown = event => { if (['ArrowLeft', 'ArrowRight'].includes(event.key)) { event.preventDefault(); change(state.widths[col.key] + (event.key === 'ArrowLeft' ? -16 : 16)); persist() } }
      th.append(grip)
    }
    tr.append(th)
  }
  dom.head.append(tr); resizeColumns(); render()
}
for (const col of COLUMNS.filter(c => !c.required)) {
  const label = element('label'), check = element('input'); check.type = 'checkbox'; check.checked = state.visible.has(col.key)
  check.onchange = () => { if (check.checked) state.visible.add(col.key); else state.visible.delete(col.key); persist(); buildColumns() }
  label.append(check, document.createTextNode(col.label)); dom.columnOptions.append(label)
}
const iconNames = new Set(['codex', 'opencode', 'cursor', 'pi', 'hermes', 'commandcode', 'devin', 'muse', 'amp', 'kilo', 'grok', 'copilot', 'agy', 'claude'])
const engineNames = { codex: 'Codex', claude: 'Claude', opencode: 'OpenCode', cursor: 'Cursor', terminal: 'Terminal', pi: 'Pi', hermes: 'Hermes', copilot: 'Copilot', gemini: 'Gemini' }
function createRow(row) {
  const tr = element('tr'); tr.dataset.id = row.id
  tr.onclick = () => { state.selected = row.id; select(); dom.grid.focus({ preventScroll: true }) }
  tr.ondblclick = event => { if (!event.target.closest('button')) openRow(row.id) }
  for (const col of activeColumns()) {
    const td = element('td', null, col.numeric ? 'numeric' : ''); td.dataset.key = col.key
    if (col.key === 'actions') {
      td.className = 'actions'
      const open = element('button', 'Open'), stop = element('button', '×', 'stop')
      open.onclick = event => { event.stopPropagation(); openRow(row.id) }
      stop.onclick = event => { event.stopPropagation(); void stopRows([row.id], true) }
      td.append(open, stop)
    } else if (col.key === 'activity') {
      const status = element('span', null, 'status'); status.append(element('span', null, 'mark'), element('span')); td.append(status)
    } else if (col.key === 'engine') {
      const span = element('span', null, 'engine'), img = element('img'), label = element('span'); img.alt = ''; img.hidden = true
      span.append(img, label); td.append(span)
    }
    tr.append(td)
  }
  return tr
}
function updateRow(tr, row) {
  for (const td of tr.children) {
    const key = td.dataset.key
    if (key === 'activity') {
      const [mark, label] = ACTIVITY[row.activity] || ['—', 'Unknown']
      const status = td.firstChild; status.className = 'status ' + row.activity
      text(status.children[0], mark); text(status.children[1], label)
      td.title = row.activityKnown || ['offline', 'stopped', 'starting', 'failed'].includes(row.activity) ? label : 'Update this machine’s Harness daemon to report activity.'
    } else if (key === 'engine') {
      const img = td.firstChild.children[0]; const icon = iconNames.has(row.engine) ? row.engine : null
      img.hidden = !icon
      img.className = ['cursor', 'opencode', 'grok', 'copilot'].includes(icon) ? 'dark-tile' : ''
      if (icon && img.getAttribute('src') !== 'icons/' + icon + '.png') img.src = 'icons/' + icon + '.png'
      text(td.firstChild.children[1], engineNames[row.engine] || row.engine || '—')
    } else if (key === 'actions') {
      const [open, stop] = td.children
      open.disabled = !row.canOpen || state.busy.has(row.id); stop.disabled = !row.canStop || state.busy.has(row.id)
      open.title = row.canOpen ? (row.state === 'paused' ? (row.resumeMode === 'fresh' ? 'Open a new conversation with the saved settings' : 'Resume this session') : 'Open this session') : row.unavailable || 'Session unavailable'
      stop.title = row.canStop ? 'Stop session; keep history' : row.unavailable || 'Already stopped or unavailable'
      stop.setAttribute('aria-label', 'Stop ' + row.name)
      open.setAttribute('aria-label', 'Open ' + row.name)
    } else {
      const value = key === 'cpu' ? (row.cpu == null ? '—' : row.cpu.toFixed(1)) : key === 'rssBytes' ? memory(row.rssBytes)
        : key === 'tokens' ? number(row.tokens) : key === 'lastActivity' ? age(row.lastActivity) : row[key] ?? '—'
      text(td, value); td.title = key === 'lastActivity' && row.lastActivity ? new Date(row.lastActivity).toLocaleString() : String(row[key] ?? '')
    }
  }
}
function select() {
  for (const [id, node] of state.nodes) node.setAttribute('aria-selected', String(id === state.selected))
}
function render() {
  const focused = dom.body.contains(document.activeElement) ? document.activeElement : null
  const { scrollTop, scrollLeft } = dom.grid
  state.shown = visibleRows(state.rows, state)
  const ids = new Set(state.shown.map(r => r.id))
  for (const [id, node] of state.nodes) if (!ids.has(id)) { node.remove(); state.nodes.delete(id) }
  // Keyed updates preserve row buttons, focus, selection and the scroll container on every sample.
  let at = dom.body.firstChild
  for (const row of state.shown) {
    let node = state.nodes.get(row.id)
    if (!node) { node = createRow(row); state.nodes.set(row.id, node) }
    updateRow(node, row)
    if (at !== node) dom.body.insertBefore(node, at)
    at = node.nextSibling
  }
  select()
  if (focused?.isConnected && document.activeElement !== focused) focused.focus({ preventScroll: true })
  dom.grid.scrollTop = scrollTop; dom.grid.scrollLeft = scrollLeft
  for (const th of dom.head.querySelectorAll('th')) {
    const col = COLUMNS.find(c => c.key === th.dataset.key)
    if (!col || col.key === 'actions') continue
    th.setAttribute('aria-sort', state.sort === col.key ? (state.direction === 1 ? 'ascending' : 'descending') : 'none')
    text(th.firstChild, col.label + (state.sort === col.key ? (state.direction === 1 ? ' ↑' : ' ↓') : ''))
  }
  dom.empty.hidden = state.shown.length > 0
  text(dom.empty, state.snapshot?.status === 'starting' ? 'Connecting to your machines…' : state.rows.length ? 'No harnesses match this search.' : 'No harnesses found on your connected machines.')
  text(dom.count, state.shown.length + (state.shown.length === state.rows.length ? '' : ' of ' + state.rows.length) + ' harnesses')
  text(dom.updated, state.snapshot?.observedAt ? 'Updated ' + age(state.snapshot.observedAt) : 'Connecting…')
}
dom.search.value = state.query; dom.filter.value = state.filter
dom.search.oninput = () => { state.query = dom.search.value; persist(); render() }
dom.filter.onchange = () => { state.filter = dom.filter.value; persist(); render() }
dom.grid.onkeydown = event => {
  if (event.target.closest('button') || event.target.classList.contains('resize')) return
  if (['ArrowUp', 'ArrowDown', 'Home', 'End'].includes(event.key)) {
    event.preventDefault(); const index = state.shown.findIndex(r => r.id === state.selected)
    const next = event.key === 'Home' ? 0 : event.key === 'End' ? state.shown.length - 1 : Math.max(0, Math.min(state.shown.length - 1, index + (event.key === 'ArrowUp' ? -1 : 1)))
    state.selected = state.shown[next]?.id ?? null; select(); state.nodes.get(state.selected)?.scrollIntoView({ block: 'nearest', inline: 'nearest' })
  } else if (event.key === 'Enter' && state.selected) { event.preventDefault(); openRow(state.selected) }
}
document.addEventListener('keydown', event => {
  if ((event.key === '/' || ((event.metaKey || event.ctrlKey) && event.key === 'f')) && !document.querySelector('dialog[open]') && !['INPUT', 'TEXTAREA'].includes(event.target.tagName)) { event.preventDefault(); dom.search.focus() }
})
dom.refresh.onclick = async () => {
  dom.refresh.disabled = true
  try { await post('/api/refresh', {}); message('') } catch (error) { message(error.message) }
  finally { dom.refresh.disabled = false }
}
function showAssistant(chooseModel = false) {
  if (!host({ action: 'assistant', chooseModel })) return
  state.assistantIntroSeen = true; persist(); dom.choice.close()
}
dom.assistant.onclick = () => state.assistantIntroSeen ? showAssistant() : dom.choice.showModal()
dom.cancel.onclick = () => dom.choice.close()
dom.free.onclick = () => showAssistant()
dom.other.onclick = () => showAssistant(true)
dom.cleanup.onclick = () => {
  const entries = (state.snapshot?.plan ?? []).filter(e => e.action === 'pause').slice(0, 64)
  state.cleanupIds = entries.map(e => e.id)
  state.cleanupRows = state.rows.filter(row => state.cleanupIds.includes(row.id))
  dom.cleanupPlan.replaceChildren()
  for (const entry of entries) { const node = element('div', entry.name, 'plan-row'); node.append(element('small', entry.why)); dom.cleanupPlan.append(node) }
  text(dom.cleanupSummary, entries.length ? entries.length + ' sessions are eligible under your current cleanup rules.' : 'No sessions are eligible under your current cleanup rules.')
  dom.cleanupApply.disabled = !entries.length; dom.cleanupDialog.showModal()
}
dom.cleanupCancel.onclick = () => dom.cleanupDialog.close()
dom.cleanupApply.onclick = async () => { const ids = [...state.cleanupIds]; dom.cleanupDialog.close(); await stopRows(ids, false) }
let stream
function connect() {
  if (stream || document.hidden) return
  stream = new EventSource('/events')
  stream.addEventListener('snapshot', event => {
    try {
      const snapshot = JSON.parse(event.data)
      state.snapshot = snapshot; state.rows = snapshot.rows ?? []
      dom.problems.hidden = !snapshot.problems?.length
      text(dom.problems, (snapshot.problems ?? []).map(p => p.machine + ': ' + p.error).join(' · ')); render()
    } catch { message('Could not read the monitor update. Refresh and try again.') }
  })
  stream.onerror = () => { message('Connection interrupted. Reconnecting…') }
  stream.onopen = () => { if (dom.message.textContent === 'Connection interrupted. Reconnecting…') message('') }
}
document.addEventListener('visibilitychange', () => { if (document.hidden) { stream?.close(); stream = null } else connect() })
const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)')
setInterval(() => {
  if (document.hidden || reducedMotion.matches) return
  const mark = SPINNER[Math.floor(Date.now() / 100) % SPINNER.length]
  for (const node of dom.body.querySelectorAll('.working .mark')) text(node, mark)
}, 100)
buildColumns(); connect()
