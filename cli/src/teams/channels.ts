import { z } from 'zod'
import { Address, Id, OperationId, QuestionSpec, TeamError, requireTeam, type Member } from './model.js'
import { channelTeamId, type TeamService } from './service.js'

const Tab = z.object({ id: Id, name: z.string().min(1).max(100), channelHost: Id.optional(), panes: z.array(Address).max(32) })
export const ChannelDesk = z.object({ enabled: z.boolean().default(false), settingsRevision: z.number().int().nonnegative().default(0),
  revision: z.number().int().nonnegative(), tabs: z.array(Tab).max(100) })
export type ChannelDesk = z.infer<typeof ChannelDesk>

export interface ChannelDependencies {
  machineId: string
  service: TeamService
  readDesk(): Promise<unknown>
  writeSettings?(enabled: boolean): Promise<unknown>
  enabledChanged?(enabled: boolean): void
  forward(machineId: string, payload: Record<string, unknown>): Promise<Record<string, unknown>>
}

/** The saved desk is the membership authority. Focus and window lifetime never
 * participate in routing. One sticky host keeps each tab's durable ledger. */
export class ChannelDirectory {
  private desk: ChannelDesk | null = null
  private flight: Promise<ChannelDesk> | null = null
  private timer: ReturnType<typeof setInterval> | null = null
  private stopped = false
  private readAt = 0
  private syncedAt = 0
  private retryAfter = 0
  private enabled = false
  private disabling = false
  private configuring = false
  constructor(private readonly deps: ChannelDependencies) {}

  start(): void {
    if (this.timer || this.stopped) return
    const poll = () => {
      if (Date.now() < this.retryAfter) return
      void this.refresh().then(() => { this.retryAfter = 0 }).catch(() => { this.retryAfter = Date.now() + 60_000 })
    }
    poll()
    this.timer = setInterval(poll, 15_000)
    this.timer.unref?.()
  }

  refresh(force = false): Promise<ChannelDesk> {
    if (force && this.flight) return this.flight.then(() => this.refresh(true))
    if (!force && this.desk && Date.now() - this.readAt < 3000) return Promise.resolve(this.desk)
    return this.flight ??= this.read().catch(error => { this.setEnabled(false); throw error }).finally(() => { this.flight = null })
  }

  private setEnabled(enabled: boolean): void {
    enabled = enabled && !this.disabling
    this.enabled = enabled
    this.deps.service.setChannelsEnabled(enabled)
    this.deps.enabledChanged?.(enabled)
  }

  private async read(): Promise<ChannelDesk> {
    const desk = ChannelDesk.parse(await this.deps.readDesk())
    if (this.stopped) throw new TeamError('STOPPED', 'The daemon is shutting down.')
    if (this.desk && this.desk.settingsRevision > desk.settingsRevision) return this.desk
    const changed = !this.enabled || this.desk?.revision !== desk.revision || JSON.stringify(this.desk?.tabs) !== JSON.stringify(desk.tabs)
    this.readAt = Date.now()
    this.setEnabled(desk.enabled)
    if (!desk.enabled) { this.desk = desk; return desk }
    if (this.desk?.enabled && this.desk.revision > desk.revision) return this.desk
    // Unknown hosts indicate an older backend. Never guess a replacement owner:
    // moving a pane must not create a second ledger or send introductions twice.
    const owned = desk.tabs.filter(tab => tab.channelHost === this.deps.machineId)
    if (changed || Date.now() - this.syncedAt >= 15_000) {
      await Promise.all(owned.map(tab => this.deps.service.syncChannel({
        tabId: tab.id, name: tab.name, revision: desk.revision, members: tab.panes,
      })))
      this.syncedAt = Date.now()
    }
    this.desk = desk
    if (!this.stopped) this.deps.service.closeMissingChannels(new Set(desk.tabs.map(t => t.id)), desk.revision)
    return desk
  }

  async request(payload: Record<string, unknown>): Promise<Record<string, unknown>> {
    requireTeam(payload.memberKey === undefined, 'CHANNEL_SCOPE', 'Use your supplied member commands to consult your own channel.')
    const action = z.enum(['channel_settings', 'channel_configure', 'channel_list', 'channel_get', 'channel_consult', 'channel_cross_consult', 'channel_cross_ask']).parse(payload.action)
    if (action === 'channel_configure') {
      requireTeam(this.deps.writeSettings, 'CHANNELS_UNSUPPORTED', 'Update Harness to configure swarm collaboration.')
      const enabled = z.boolean().parse(payload.enabled)
      requireTeam(!this.configuring, 'CHANNEL_SETTINGS_BUSY', 'Another swarm setting change is being saved. Refresh and try again.')
      this.configuring = true
      // Stop local delivery immediately on OFF; a failed write stays disabled
      // here until a fresh authoritative read can reconcile the account choice.
      if (!enabled) { this.disabling = true; this.setEnabled(false) }
      try {
        await this.deps.writeSettings(enabled)
        const updated = await this.refresh(true)
        this.disabling = false
        this.setEnabled(updated.enabled)
        return { enabled: updated.enabled, revision: updated.settingsRevision }
      } finally { this.disabling = false; this.configuring = false }
    }
    if (action === 'channel_cross_ask') requireTeam(payload.crossChannel === true, 'CROSS_CHANNEL_EXPLICIT', 'Cross-channel work needs explicit user direction and --cross-channel.')
    const desk = await this.refresh(action === 'channel_settings' || action === 'channel_consult' || action === 'channel_cross_consult' || action === 'channel_cross_ask')
    if (action === 'channel_settings') return { enabled: desk.enabled, revision: desk.settingsRevision }
    requireTeam(desk.enabled && this.enabled, 'CHANNELS_DISABLED', 'Enable Swarm collaboration in Settings → Experimental first.')
    if (action === 'channel_list') return { revision: desk.revision, channels: desk.tabs.map(tab => ({
      tabId: tab.id, name: tab.name, machineId: tab.channelHost, teamId: channelTeamId(tab.id), members: tab.panes,
    })) }
    const tabId = Id.parse(payload.tabId)
    const tab = desk.tabs.find(t => t.id === tabId)
    requireTeam(tab, 'CHANNEL_NOT_FOUND', 'This tab is no longer on your desk.')
    requireTeam(tab.channelHost || tab.panes.length, 'CHANNEL_EMPTY', 'Add an owned agent pane to this tab to start its swarm.')
    requireTeam(tab.channelHost, 'CHANNELS_UNSUPPORTED', 'Update the Harness backend to enable tab channels.')
    if (tab.channelHost !== this.deps.machineId) {
      requireTeam(!payload.channelForwarded, 'CHANNEL_MOVED', 'Channel routing changed; retry the same request.')
      return this.deps.forward(tab.channelHost, { ...payload, channelForwarded: true })
    }
    const teamId = channelTeamId(tabId)
    if (action === 'channel_consult' || action === 'channel_cross_consult') return { teamId, machineId: tab.channelHost,
      consultation: this.deps.service.consult(teamId, OperationId.parse(payload.id), Address.parse(payload.from), { kind: 'owner' }, action === 'channel_cross_consult') }
    if (action === 'channel_cross_ask') {
      OperationId.parse(payload.id)
      z.string().trim().min(1).max(8000).parse(payload.text)
      const targetTabId = Id.parse(payload.targetTabId)
      requireTeam(targetTabId !== tabId, 'SAME_CHANNEL', 'Use the scoped ask command for a peer in your own channel.')
      const source = await this.deps.service.snapshot(teamId, { kind: 'owner' })
      requireTeam(source.state === 'active', 'TEAM_PAUSED', 'Collaboration in this channel is paused.')
      const address = Address.parse(payload.from)
      const from = (source.members as Member[]).find(m => m.enabled && m.machineId === address.machineId && m.agentId === address.agentId)
      requireTeam(from, 'NOT_A_MEMBER', 'The source agent is no longer in this tab.')
      const destination = await this.request({ action: 'channel_get', tabId: targetTabId })
      const target = destination.team as Record<string, unknown>
      requireTeam(target?.state === 'active', 'TEAM_PAUSED', 'Collaboration in the destination channel is paused.')
      const to = (target.members as Member[]).find(m => m.enabled && (m.id === payload.to || m.name === payload.to))
      requireTeam(to, 'MEMBER_NOT_FOUND', 'Read the destination channel’s members and choose an exact member ID or name.')
      requireTeam(from.machineId !== to.machineId || from.agentId !== to.agentId, 'SELF_MESSAGE', 'Choose another agent.')
      // One durable direct conversation per pair of channel participants. Neither
      // tab's membership expands; ordinary scoped discovery remains unchanged.
      const bridgeId = channelTeamId(JSON.stringify([tabId, targetTabId, Address.parse(from), Address.parse(to)]))
      let bridge: Record<string, unknown>
      try { bridge = await this.deps.service.snapshot(bridgeId, { kind: 'owner' }) }
      catch (error) {
        if (!(error instanceof TeamError) || error.code !== 'TEAM_NOT_FOUND') throw error
        bridge = await this.deps.service.create({ id: bridgeId, name: 'Explicit cross-channel consultation',
          bridge: { sourceTabId: tabId, targetTabId },
          members: [{ ...Address.parse(from), name: from.name, role: from.role }, { ...Address.parse(to), name: to.name, role: to.role }],
        }, { kind: 'owner' })
      }
      const participants = bridge.members as Member[]
      const request = QuestionSpec.parse({ ...payload, from: participants[0].id, to: participants[1].id,
        context: `Explicit cross-channel request from tab ${tabId} to tab ${targetTabId}. ${payload.context ?? ''}` })
      return { teamId: bridgeId, machineId: this.deps.machineId,
        exchange: this.deps.service.ask(bridgeId, request, { kind: 'owner' }) }
    }
    return { team: await this.deps.service.snapshot(teamId, { kind: 'owner' }) }
  }

  stop(): void { this.stopped = true; this.setEnabled(false); if (this.timer) clearInterval(this.timer); this.timer = null }
}
