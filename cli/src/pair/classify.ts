/**
 * What a dialog asks, read on the machine that owns it (daemons/BRAIN.md, "the floor"). Three questions:
 *
 *   DENY-CLASS  Never approved by a key, a rule, a recommendation or the pair: pushes, force flags,
 *               destructive deletes and resets, sudo, piping a download into a shell, deploy, publish,
 *               drop, merge. Read over the WHOLE dialog — every line of the command, its prose and its
 *               options — because a wrapped `&& git push` sits on the second line. It leans wide: a false
 *               positive costs a key, a false negative approves a push.
 *   ALLOW-CLASS What a `[y]` key may approve at all: a permission prompt for a read, a test, a build, a
 *               linter or formatter, or an edit to a file in the project. Everything else — including every
 *               question that is not a permission prompt — gets `[g]` (open the pane) and no `[y]`.
 *   PERSISTENT  An option that answers more than this once ("don't ask again", "allow all edits during
 *               this session", "always"). The daemon never picks one, for any caller: `y` is a one-time yes.
 */
import { isAbsolute, normalize, relative } from 'node:path'

const DENY_PATTERNS: RegExp[] = [
  /\bpush(ed|es|ing)?\b/i,                                               // git push in any form
  /--force(-with-lease|-if-includes)?\b|\bforce[- ]?(push|with-lease)?\b|(^|\s)-f(\s|$)/i,
  /\bbranch\s+(-[a-zA-Z]*D|--delete\s+--force)\b/,                        // git branch -D
  /\brm\s+(-[a-zA-Z]*[rR][a-zA-Z]*|--recursive|-[a-zA-Z]*\s+-[a-zA-Z]*[rR])/, // rm -r, -rf, -fr, -R, --recursive
  /\breset\s+--hard\b/i,
  /\bclean\s+-[a-zA-Z]*f/i,                                               // git clean -f, -fd, -fdx
  /\bsudo\b|\bdoas\b/i,
  /\|\s*(sudo\s+)?(ba|z|da|k|c|tc|fi)?sh\b/i,                             // | sh, | bash
  /\b(curl|wget|fetch)\b[^\n]*\|/i,                                        // a download piped anywhere
  /\bch(mod|own|grp)\s+(-[a-zA-Z]*R|--recursive)/,
  /\bmkfs(\.\w+)?\b/i,
  /\bdd\s+[^\n]*\bif=/i,
  /\bdeploy(s|ed|ing|ment)?\b/i,
  /\bpublish(es|ed|ing)?\b/i,
  /\bdrop\s+(table|database|schema|index|column|collection|view)\b|\bdropdb\b|\bdrop\b(?!down)/i,
  /\btruncate\s+table\b/i,
  /\bmerge(s|d)?\b/i,
]

/** A deny-class dialog: never approved by anything but the person's own hands in the pane. */
export function isDenyClass(dialog: string, options: readonly string[] = []): boolean {
  const text = [dialog, ...options].join('\n')
  return DENY_PATTERNS.some((pattern) => pattern.test(text))
}

/** Options that answer for more than this once, and the one-time yes (pair/floor.ts, where the floor uses them). */
export { isOneTimeYes, isPersistentOption } from './floor.js'

// ── allow-class ─────────────────────────────────────────────────────────────────────────────────────

/** Commands a `[y]` may approve: reads, tests, builds, linters and formatters. Anchored at a segment. */
const ALLOW_COMMANDS: RegExp[] = [
  /^(ls|pwd|cat|head|tail|wc|grep|egrep|fgrep|rg|ag|tree|file|stat|du|df|which|type|echo|printf|sort|uniq|cut|tr|jq|yq|diff|cmp|basename|dirname|realpath|date|true|nl|column|less|more)(\s|$)/,
  /^find(\s|$)(?!.*\s-(delete|exec|execdir|ok|okdir|fprint|fprintf|fls)\b)/,
  /^sed\s+-n(\s|$)(?!.*\s-i)/,
  /^git\s+(status|diff|log|show|rev-parse|ls-files|ls-tree|blame|describe|shortlog|grep|reflog|stash\s+list|remote(\s+-v)?)(\s|$)/,
  /^git\s+branch(\s+(-a|-r|-v|-vv|--all|--remotes|--list|--show-current))*$/,
  /^cd(\s+[^\s]+)?$/,
  /^(npm|pnpm|yarn|bun)\s+(run\s+)?(test|tests|check|lint|typecheck|type-check|tsc|build|format|fmt|prettier)(:[\w:-]+)?(\s|$)/,
  /^(npx|bunx|pnpm\s+exec|pnpm\s+dlx|yarn)\s+(vitest|jest|mocha|ava|tsc|eslint|prettier|biome|playwright\s+test|stylelint)(\s|$)/,
  /^(vitest|jest|mocha|tsc|eslint|prettier|biome|stylelint)(\s|$)/,
  /^(pytest|mypy|ruff|black|isort|flake8|pylint|pyright)(\s|$)/,
  /^python3?\s+-m\s+(pytest|unittest|mypy|ruff|black|isort|compileall)(\s|$)/,
  /^go\s+(test|build|vet|fmt)(\s|$)/,
  /^gofmt(\s|$)/,
  /^cargo\s+(test|build|check|clippy|fmt|doc)(\s|$)/,
  /^make(\s+(test|tests|check|build|lint|fmt|format|all))?$/,
  /^(flutter|dart)\s+(test|analyze|format|build)(\s|$)/,
  /^(\.\/)?gradlew?\s+(test|build|check|assemble\w*)(\s|$)/,
  /^mvn\s+(test|compile|verify|package)(\s|$)/,
  /^swift\s+(test|build)(\s|$)/,
  /^(rspec|ctest)(\s|$)/,
  /^mix\s+(test|format|compile)(\s|$)/,
  /^(bundle\s+exec\s+)?(rspec|rubocop|rake\s+(test|spec))(\s|$)/,
]

/** A redirection that writes somewhere (anything but stderr folding and /dev/null), or a substitution. */
const WRITES = /(^|[^0-9&>])>{1,2}(?!>|\s*(&1\b|\/dev\/null\b))|\$\(|`|<\(|>\(/

/** One command line is allowed when EVERY segment of it is an allowed command. */
export function isAllowedCommand(command: string): boolean {
  const text = command.replace(/\s+/g, ' ').trim()
  if (!text || WRITES.test(text) || isDenyClass(text)) return false
  const segments = text.split(/&&|\|\||;|\|/).map((segment) => segment.trim()).filter(Boolean)
  if (!segments.length) return false
  return segments.every((segment) => {
    const bare = segment.replace(/^([A-Z_][A-Z0-9_]*=\S*\s+)+/, '')   // FOO=1 npm test
    return ALLOW_COMMANDS.some((pattern) => pattern.test(bare))
  })
}

/** A path in the project: relative without `..`, or absolute under the harness's folder. */
export function inProject(path: string, cwd?: string | null): boolean {
  const p = path.trim().replace(/^["'`]|["'`]$/g, '').replace(/[?.,:]$/, '')
  if (!p || p.startsWith('~')) return false
  if (!isAbsolute(p)) return !normalize(p).split(/[\\/]/).includes('..')
  if (!cwd || !isAbsolute(cwd)) return false
  const rel = relative(cwd, p)
  return !!rel && !rel.startsWith('..') && !isAbsolute(rel)
}

const FILE_HEADER = /^(edit|write|create|update|read|view)( file)?$/i
const SEARCH_HEADER = /^(glob|grep|search|list( files)?|ls)$/i
const BASH_HEADER = /^(bash( command)?|run( command)?|shell( command)?|execute( shell)?( command)?)$/i
const EDIT_QUESTION = /make this edit to (.+?)\?\s*$/i

/**
 * Whether a `[y]` may approve this dialog. `dialog` is the whole dialog, line by line, as painted.
 * Only a permission prompt can be allow-class; anything unrecognised is not.
 */
export function isAllowClass(dialog: string, opts: { permission: boolean; cwd?: string | null }): boolean {
  if (!opts.permission || !dialog.trim() || isDenyClass(dialog)) return false
  const lines = dialog.split('\n').map((line) => line.trim())
  // Claude's edit prompt names its file in the question itself.
  for (const line of lines) {
    const edit = EDIT_QUESTION.exec(line)
    if (edit) return inProject(edit[1]!, opts.cwd)
  }
  // Codex (and anything that prints the command itself with a `$ ` prompt): every command line counts.
  const dollar = lines.filter((line) => line.startsWith('$ ')).map((line) => line.slice(2))
  if (dollar.length) return dollar.every(isAllowedCommand)
  const headerAt = lines.findIndex((line) => FILE_HEADER.test(line) || SEARCH_HEADER.test(line) || BASH_HEADER.test(line))
  if (headerAt < 0) return false
  const header = lines[headerAt]!
  // The block under the header, to the first blank line.
  const block: string[] = []
  for (const line of lines.slice(headerAt + 1)) {
    if (!line) { if (block.length) break; continue }
    block.push(line)
  }
  if (!block.length) return SEARCH_HEADER.test(header)
  if (FILE_HEADER.test(header)) return block.length === 1 && inProject(block[0]!, opts.cwd)
  if (SEARCH_HEADER.test(header)) return block.every((line) => !/(^|\s)(\/|~)/.test(line) || inProject(line.split(/\s+/).pop()!, opts.cwd))
  // Bash: the command's lines, then (usually) one line of description written as a sentence. A trailing
  // line that reads like prose is the description; anything else must be an allowed command, together.
  const command = [...block]
  while (command.length > 1 && /^[A-Z][a-z]+(\s|$)/.test(command[command.length - 1]!) && !/[|;&<>$`]/.test(command[command.length - 1]!)) command.pop()
  return isAllowedCommand(command.join(' '))
}
