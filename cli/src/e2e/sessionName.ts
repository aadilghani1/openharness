/**
 * One namespaced name per matrix run, stamped identically on the trace, the watchdog session and
 * the report, so every artifact of a run is grep-able and the audit answers: what version of which
 * coding-agent, which test, which grid model, when.
 *
 * Convention: `<engine>@<version>-><testcase>@<grid-model>--<timestamp>`
 * e.g. `codex@0.156.0->grid-switch@grid-gpt-5-mini--20260921T1805Z`
 */
export function sessionName(opts: {
  engine: string
  version: string
  testcase: string
  gridModel?: string
  at?: Date
}): string {
  const model = opts.gridModel && opts.gridModel.trim() ? sanitize(opts.gridModel) : 'none'
  const ts = (opts.at ?? new Date())
    .toISOString()
    .replace(/[-:]/g, '')
    .replace(/\.\d{3}Z$/, 'Z')
  return `${opts.engine}@${sanitize(opts.version)}->${sanitize(opts.testcase)}@${model}--${ts}`
}

function sanitize(v: string): string {
  return v.replace(/[^A-Za-z0-9._@-]/g, '-')
}

/**
 * The agent's working folder — short, and with ONE separator class, so a model that reconstructs the
 * cwd when it writes a file has nothing confusable to mis-transcribe.
 *
 * Two failures on this box, by two different actors, both from the folder being an unpronounceable
 * 55-char string of mixed separators:
 *
 *   * claude 2.1.274 (the CLIENT) rewrote the `->` in the path to a `-` when it built a Write path,
 *     so its file landed in a sibling folder and every write step failed as "out/hello-1.txt does not
 *     exist" (grid-dev, 2026-09-25; 2.1.273 did not). That fix kept letters, digits, `.`, `_` and
 *     `-` only.
 *   * DeepSeek-V4-Flash-0731 (the MODEL, on a grid) reconstructed the cwd and wrote `to_grid` as
 *     `to-grid` — a single misplaced character, because the name still mixed `_`, `-` and `.`
 *     (grid-dev, 2026-09-28, claude 2.1.277). Same symptom: the file is written, "does not exist"
 *     where the check looks, it just sits in a sibling directory.
 *
 * The full session name still identifies the run everywhere it matters (the trace, the bundle), so
 * the working folder does not need to be readable back to a person: engine + timestamp, `-`
 * separated, nothing else. `claude@2.1.277->grid-switch@none--20260928T181658Z` -> `claude-20260928T181658Z`.
 */
export function workspaceDirName(session: string): string {
  const m = /^([^@]+)@.*--([0-9TZ]+)$/.exec(session)
  if (!m) return `e2e-${session.replace(/[^A-Za-z0-9-]/g, '-')}`
  return `${m[1]}-${m[2]}`
}
