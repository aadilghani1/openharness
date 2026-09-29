// Real session and CRC-framed loopback, injected speech only. Never opens a serial
// port, loads host credentials or makes a provider request.
import { mkdtempSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { CableDecoder, CableType, encodeCableFrame } from './cableFrame.js'
import { CableSession, type CableHost, type CablePort } from './cableSession.js'
import { applyProSpeechGain, type SpeechProvider } from './cableSpeech.js'
import { createCreatureVoiceProvider } from './creatureVoice.js'
import { DialLog } from './dialLog.js'

const settle = async () => { for (let i = 0; i < 30; i++) await Promise.resolve() }
const cleanup: Array<{ session: CableSession; directory: string }> = []
afterEach(async () => {
  for (const { session, directory } of cleanup.splice(0)) {
    await session.stop(); rmSync(directory, { recursive: true, force: true })
  }
  vi.useRealTimers()
})

class SpeechLoopback implements CablePort {
  readonly path = '/dev/speech-test-loopback'
  isOpen = true
  sent: Record<string, unknown>[] = []
  frames: Uint8Array[] = []
  speech: Buffer[] = []
  autoCredit = true
  private decoder = new CableDecoder()
  private id = 0
  private received = 0
  constructor(private onData: (data: Buffer) => void, private onClosed: (why: string) => void) {}
  async write(bytes: Uint8Array) {
    if (!this.isOpen) throw new Error('test port is closed')
    this.frames.push(Uint8Array.from(bytes))
    this.decoder.feed(Buffer.from(bytes), frame => {
      if (frame.type === CableType.Json) {
        const msg = JSON.parse(Buffer.from(frame.payload).toString('utf8')) as Record<string, unknown>
        this.sent.push(msg)
        if (msg.t === 'speech.begin') {
          this.id = msg.id as number; this.received = 0; this.ack()
        }
        if (msg.t === 'speech.end') this.ack({ active: false, playing: false, credit: this.received })
      } else if (frame.type === CableType.Speech) {
        const payload = Buffer.from(frame.payload)
        this.speech.push(payload)
        this.received = payload.readUInt32LE(4) + payload.length - 8
        if (this.autoCredit) this.ack()
      }
    })
  }
  async close(why = 'unplugged') {
    if (!this.isOpen) return
    this.isOpen = false; this.onClosed(why)
  }
  say(msg: Record<string, unknown>) {
    this.onData(Buffer.from(encodeCableFrame(CableType.Json, Buffer.from(JSON.stringify(msg)))))
  }
  pcm(bytes: Buffer) { this.onData(Buffer.from(encodeCableFrame(CableType.Pcm, bytes))) }
  ack(fields: Record<string, unknown> = {}) {
    this.say({ t: 'speech.state', id: this.id, active: true, playing: this.received > 0,
      received: this.received, consumed: this.received, credit: this.received + 8192, error: 0, ...fields })
  }
  types() { return this.sent.map(m => m.t) }
}

async function connect(options: { capability?: string | null; bytes?: Buffer;
  provider?: () => Promise<SpeechProvider | null>; host?: Partial<CableHost> } = {}) {
  const stream = vi.fn(async function* () { yield options.bytes ?? Buffer.from([1, 2, 3, 4]) })
  const provider = vi.fn(options.provider ?? (async () => ({ stream })))
  const agents = [{ id: 'a1', name: 'Design', engine: 'claude' }, { id: 'a2', name: 'Build', engine: 'codex' }]
  const host: CableHost = {
    creatureVoice: provider,
    localMachine: () => ({ id: 'local', name: 'Computer' }),
    listMachines: async () => ({ machines: [{ id: 'local', name: 'Computer', state: 'ready', local: true }], source: 'backend' }),
    selectedMachine: () => 'local', selectMachine: async () => ({ ok: true }),
    listSwarms: () => ({ selected: 'tab', swarms: [], tiles: [] }), listUnread: () => [], selectSwarm: vi.fn(),
    appName: () => 'harness', voiceLang: () => 'en', listAgents: async () => agents,
    agentTotal: () => agents.length, activeSwarm: () => 'tab',
    describe: id => { const a = agents.find(row => row.id === id); return a ? { name: a.name, engine: a.engine, machine: '' } : undefined },
    sendTurn: vi.fn(), stopTurn: vi.fn(), scrolled: vi.fn(), answer: vi.fn(), focus: vi.fn(), openAgent: vi.fn(),
    forkAgent: async id => ({ ok: true, agentId: id + '-fork' }), updateAgent: vi.fn(), listModels: async () => [],
    recentSummaries: async () => [], transcribe: async () => 'Tell me how the field is doing.',
    route: async () => ({ agentId: 'a1', confidence: 0.9, reason: 'selected' }), log: () => {}, ...options.host,
  }
  let port!: SpeechLoopback
  const directory = mkdtempSync(join(tmpdir(), 'cable-speech-'))
  const session = new CableSession(host, new DialLog(directory), async (data, closed) => {
    port = new SpeechLoopback(data, closed); return port
  })
  cleanup.push({ session, directory }); session.start()
  await vi.waitFor(() => expect(port).toBeDefined())
  const capability = options.capability === undefined ? 'pcm16-v1' : options.capability
  port.say({ t: 'hello', product: 'harness', mac: 'test-pro', hw: 'test-pro', ...(capability ? { speech: capability } : {}) })
  await vi.waitFor(() => expect(port.types()).toContain('agents.end'))
  await session.focusAgent('a1')
  let recording = 0
  async function voice(agentId = 'a1', review = false) {
    const uploadId = 'test-voice-' + ++recording
    port.say({ t: 'voice.begin', uploadId, agentId, sr: 16000 })
    port.pcm(Buffer.alloc(3200, 1)); port.say({ t: 'voice.end', uploadId, review })
    await vi.waitFor(() => expect(port.sent.some(m => m.uploadId === uploadId &&
      ['voice.transcript', 'voice.draft', 'voice.error'].includes(m.t as string))).toBe(true))
    return port.sent.find(m => m.uploadId === uploadId && ['voice.transcript', 'voice.draft', 'voice.error'].includes(m.t as string))!
  }
  async function answer(text = 'The field is ready.') {
    await session.turnStarted('a1', 'Working')
    await session.summary('a1', text, text)
  }
  return { session, port, host, stream, provider, voice, answer }
}

describe('creature speech through the actual cable session', () => {
  it('preserves voice submission and sends a single reply as ten CRC-framed 2048-byte chunks', async () => {
    const bytes = Buffer.from(Array.from({ length: 20 * 1024 }, (_, i) => i % 251))
    const f = await connect({ bytes })
    await f.voice(); expect(f.host.sendTurn).toHaveBeenCalledExactlyOnceWith('a1', 'Tell me how the field is doing.')
    await f.session.summary('a1', 'Old.', 'Old.')
    expect(f.provider).not.toHaveBeenCalled()
    await f.answer(); await vi.waitFor(() => expect(f.port.types()).toContain('speech.end'))
    expect(f.port.speech).toHaveLength(10)
    const id = f.port.sent.find(m => m.t === 'speech.begin')!.id
    for (const [i, payload] of f.port.speech.entries()) {
      expect(payload.readUInt32LE(0)).toBe(id); expect(payload.readUInt32LE(4)).toBe(i * 2048)
      expect(payload.length).toBe(2056)
    }
    expect(Buffer.concat(f.port.speech.map(p => p.subarray(8)))).toEqual(applyProSpeechGain(Buffer.from(bytes)))
    expect(f.port.sent.find(m => m.t === 'speech.end')).toEqual({ t: 'speech.end', id, bytes: 20 * 1024 })
    await f.session.summary('a1', 'Repeated.', 'Repeated.'); await settle()
    expect(f.provider).toHaveBeenCalledOnce()
    expect(f.port.types().indexOf('summary')).toBeLessThan(f.port.types().indexOf('speech.begin'))
  })

  it.each([null, 'pcm16-v0', 'other'])('keeps legacy or unsupported capability %s completely text-only', async capability => {
    const f = await connect({ capability }); await f.voice(); await f.answer(); await settle()
    expect(f.host.sendTurn).toHaveBeenCalledOnce(); expect(f.port.types()).toContain('summary')
    expect(f.provider).not.toHaveBeenCalled(); expect(f.port.speech).toEqual([])
  })

  it('never speaks restored history, unsolicited summaries or silent subagent results', async () => {
    const f = await connect({ host: { recentSummaries: async () => [{ recap: 'Old result.', text: 'Old result.' }] } })
    await vi.waitFor(() => expect(f.port.sent.some(m => m.t === 'summary' && m.restore === true)).toBe(true))
    await f.answer('Unsolicited.'); await settle(); expect(f.provider).not.toHaveBeenCalled()
    await f.voice(); await f.session.turnStarted('a1')
    await f.session.summary('a1', 'Subagent complete.', 'Subagent complete.', false, true)
    await f.session.summary('a2', 'Another pane.', 'Another pane.'); await settle()
    expect(f.provider).not.toHaveBeenCalled()
    await f.session.summary('a1', 'Your answer.', 'Your answer.', true)
    await vi.waitFor(() => expect(f.port.types()).toContain('speech.end'))
    expect(f.provider).toHaveBeenCalledOnce()
  })

  it('does not mistake a previously busy turn for the new voice turn', async () => {
    const f = await connect()
    await f.session.turnStarted('a1'); await f.voice(); await f.answer('Earlier work finished.')
    await settle(); expect(f.provider).not.toHaveBeenCalled()
    await f.voice(); await f.answer('The new reply.')
    await vi.waitFor(() => expect(f.port.types()).toContain('speech.end'))
    expect(f.provider).toHaveBeenCalledOnce()
  })

  it('does not arm an already busy agent recovered from its terminal footer', async () => {
    const f = await connect({ host: { activityText: async () => 'Working' } })
    await f.session['refreshFocusedActivity']()
    expect(f.port.sent.some(m => m.t === 'turn.started' && m.text === 'Working')).toBe(true)
    await f.voice(); await f.answer('Earlier work finished.')
    await settle(); expect(f.provider).not.toHaveBeenCalled()
  })

  it('arms a reviewed draft only when its explicit Send command succeeds', async () => {
    const f = await connect()
    const draft = await f.voice('a1', true)
    expect(draft.t).toBe('voice.draft'); expect(f.host.sendTurn).not.toHaveBeenCalled()
    await f.answer('Unrelated result while reviewing.'); await settle(); expect(f.provider).not.toHaveBeenCalled()
    f.port.say({ t: 'draft.command', draftId: draft.id, revision: draft.revision, requestId: 'send-it', op: 'send' })
    await vi.waitFor(() => expect(f.host.sendTurn).toHaveBeenCalledOnce())
    await f.answer('Sent and answered.')
    await vi.waitFor(() => expect(f.port.types()).toContain('speech.end'))
    expect(f.provider).toHaveBeenCalledOnce()
  })

  it.each(['refused', 'throws'] as const)('does not arm a voice send that %s', async reason => {
    const sendTurn = vi.fn(() => { if (reason === 'throws') throw new Error('not reachable'); return { ok: false as const } })
    const f = await connect({ host: { sendTurn } })
    const reply = await f.voice(); expect(reply.t).toBe('voice.error')
    await f.answer(); await settle(); expect(f.provider).not.toHaveBeenCalled()
  })

  it.each(['new voice', 'dial focus', 'desktop focus', 'disconnect', 'tab', 'machine'] as const)
    ('cancels a held provider read on %s, through real session events', async cause => {
      const cancelled = vi.fn()
      const body = new ReadableStream<Uint8Array>({ cancel: cancelled })
      const provider = createCreatureVoiceProvider({ apiKey: 'test-secret-only', voiceId: 'test-voice', model: 'eleven_v4',
        fetchImpl: async () => new Response(body, { headers: { 'content-type': 'audio/pcm' } }) })
      const f = await connect({ provider: async () => provider })
      await f.voice(); await f.answer(); await vi.waitFor(() => expect(body.locked).toBe(true))
      if (cause === 'new voice') f.port.say({ t: 'voice.begin', uploadId: 'interrupt', agentId: 'a1' })
      if (cause === 'dial focus') f.port.say({ t: 'focus', agentId: 'a2' })
      if (cause === 'desktop focus') await f.session.followApp('local', 'a2')
      if (cause === 'disconnect') await f.port.close('cable removed')
      if (cause === 'tab') f.port.say({ t: 'swarm.select', swarmId: 'another-tab' })
      if (cause === 'machine') f.port.say({ t: 'machine.select', machineId: 'local' })
      await vi.waitFor(() => expect(cancelled).toHaveBeenCalledOnce())
      expect(body.locked).toBe(false); expect(f.port.speech).toEqual([])
      expect(f.port.types()).not.toContain('speech.end')
      if (cause !== 'disconnect') expect(f.port.types()).toContain('speech.abort')
    })

  it('obeys actual framed receipts and zero-received firmware rejection after partial playback', async () => {
    const f = await connect({ bytes: Buffer.alloc(20_000, 5) }); f.port.autoCredit = false
    await f.voice(); await f.answer(); await vi.waitFor(() => expect(f.port.speech).toHaveLength(1))
    const id = f.port.sent.find(m => m.t === 'speech.begin')!.id
    f.port.say({ t: 'speech.state', id: (id as number) - 1, error: 100, received: 0 })
    await settle(); expect(f.port.types()).not.toContain('speech.abort')
    f.port.ack({ received: 2048, consumed: 0, credit: 10240 })
    await vi.waitFor(() => expect(f.port.speech).toHaveLength(2))
    f.port.say({ t: 'speech.state', id, error: 100, received: 0 })
    await vi.waitFor(() => expect(f.port.types()).toContain('speech.abort'))
    expect(f.port.speech).toHaveLength(2); expect(f.port.types()).not.toContain('speech.end')
  })

  it('keeps unusable Markdown as a text result without an uncaught speech rejection', async () => {
    const f = await connect(); await f.voice(); await f.session.turnStarted('a1')
    await f.session.summary('a1', '[angry]', '\x60\x60\x60sh\nsecret()', false)
    await settle()
    expect(f.port.types()).toContain('summary'); expect(f.provider).not.toHaveBeenCalled()
    expect(f.port.types()).not.toContain('speech.begin')
  })
})
