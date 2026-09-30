/** Local owner controls. Agent tools get a different, host-scoped recall path. */
import { randomBytes } from 'node:crypto'
import { z } from 'zod'
import { libraryCommandSchema, libraryQuerySchema, type LibraryPreview } from './library.js'
import { MemoryError, parse } from './types.js'
import type { CodingMemoryRuntime } from './runtime.js'
import type { CallerVerdict } from '../pair/learn/approval.js'

const requestSchema = z.discriminatedUnion('action', [
  z.object({ action: z.literal('status') }).strict(),
  z.object({ action: z.literal('list'), query: libraryQuerySchema.optional() }).strict(),
  z.object({ action: z.literal('show'), id: z.string().min(1).max(200) }).strict(),
  z.object({ action: z.literal('preview'), command: libraryCommandSchema }).strict(),
  z.object({ action: z.literal('apply'), capability: z.string().regex(/^[0-9a-f]{32}$/) }).strict(),
])
type Runtime = Pick<CodingMemoryRuntime, 'ownerKey' | 'libraryStatus' | 'libraryPage' | 'libraryDetail' | 'libraryPreview' | 'libraryApply'>
interface Deps {
  runtime(): Runtime | null
  /** Must verify the OS owner as well as rejecting a process inside an agent's harness. */
  verify(connId: string): Promise<CallerVerdict>
  now?: () => number
}
interface Capability { owner: string; connId: string; pid: number; expires: number; preview: LibraryPreview }
const TTL_MS = 2 * 60_000

export class MemoryControl {
  private readonly capabilities = new Map<string, Capability>()
  private readonly now: () => number
  constructor(private readonly deps: Deps) { this.now = deps.now ?? Date.now }

  async local(payload: Record<string, unknown>, connId: string): Promise<Record<string, unknown>> {
    // A token-bearing agent cannot turn itself into the person with `confirmed`, a claimed owner,
    // another agentId, or an independently supplied command at apply time.
    if (payload.token) return { ok: false, error: 'PERSON_ONLY' }
    const runtime = this.deps.runtime()
    if (!runtime) return { ok: false, error: 'UNSUPPORTED' }
    const owner = runtime.ownerKey()
    if (!owner) return { ok: false, error: 'MEMORY_UNAVAILABLE' }
    try {
      const { verb: _verb, requestId: _requestId, token: _token, ...input } = payload
      const request = parse(requestSchema, input)
      const verdict = await this.deps.verify(connId)
      if (!verdict.ok) return { ok: false, error: verdict.error, detail: verdict.detail }
      if (runtime !== this.deps.runtime() || owner !== runtime.ownerKey()) throw new MemoryError('owner_changed')
      this.prune(owner)
      switch (request.action) {
        case 'status': return { ok: true, ...await runtime.libraryStatus(owner) }
        case 'list': return { ok: true, ...await runtime.libraryPage(owner, request.query) }
        case 'show': {
          const detail = await runtime.libraryDetail(owner, request.id)
          return detail ? { ok: true, ...detail } : { ok: false, error: 'NOT_FOUND' }
        }
        case 'preview': {
          const preview = await runtime.libraryPreview(owner, request.command)
          if (owner !== runtime.ownerKey()) throw new MemoryError('owner_changed')
          const capability = randomBytes(16).toString('hex')
          this.capabilities.set(capability, { owner, connId, pid: verdict.pid, expires: this.now() + TTL_MS, preview })
          if (this.capabilities.size > 32) this.capabilities.delete(this.capabilities.keys().next().value!)
          return { ok: true, capability, expiresInMs: TTL_MS, preview }
        }
        case 'apply': {
          const capability = this.capabilities.get(request.capability)
          this.capabilities.delete(request.capability) // Spend once, including a mismatched caller.
          if (!capability || capability.owner !== owner || capability.connId !== connId || capability.pid !== verdict.pid) {
            throw new MemoryError('preview_required')
          }
          return { ok: true, ...await runtime.libraryApply(owner, capability.preview) }
        }
      }
    } catch (error) { return { ok: false, error: error instanceof MemoryError ? error.code.toUpperCase() : 'MEMORY_UNAVAILABLE' } }
  }

  private prune(owner: string): void {
    for (const [id, capability] of this.capabilities) {
      if (capability.owner !== owner || capability.expires <= this.now()) this.capabilities.delete(id)
    }
  }
}
