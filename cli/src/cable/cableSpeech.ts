import { randomInt } from 'node:crypto'
import { directCreatureSpeech } from './creatureVoice.js'

const MAX_BYTES = 960_000
const WIRE_WINDOW = 8192
const CHUNK_BYTES = 2048
const PRO_SPEECH_VOLUME = 90
const PRO_SPEECH_GAIN = 4
const PRO_SPEECH_CEILING = 0.63

/** Shape one PCM16LE payload in place; no buffering, state, or extra samples.
 * This is applied only to the capability-gated Pro speech output, never mic input. */
export function applyProSpeechGain(pcm: Buffer): Buffer {
  if (pcm.length % 2) throw new Error('invalid_pcm')
  for (let at = 0; at < pcm.length; at += 2) {
    const sample = pcm.readInt16LE(at)
    const shaped = Math.round(32767 * PRO_SPEECH_CEILING *
      Math.tanh((sample / 32768) * PRO_SPEECH_GAIN / PRO_SPEECH_CEILING))
    pcm.writeInt16LE(Math.max(-32768, Math.min(32767, shaped)), at)
  }
  return pcm
}
export interface SpeechProvider {
  stream(plan: ReturnType<typeof directCreatureSpeech>, signal: AbortSignal): AsyncIterable<Buffer>
}
export interface SpeechWire {
  json(message: Record<string, unknown>): Promise<boolean>
  pcm(payload: Buffer): Promise<boolean>
}
interface DeviceState {
  id: number; active: boolean; playing: boolean; received: number; consumed: number; credit: number; error: number
}
interface Playback {
  id: number; abort: AbortController; state?: DeviceState; sent: number; ended: boolean
  wake?: () => void
}

/** One conversation, not a notification speaker. Only a new turn after a voice
 * submission can consume the one-shot reply intent. Nothing is persisted/replayed. */
export class CableSpeech {
  private enabled = false
  private readonly busy = new Set<string>()
  private intent?: { agentId: string; expires: number; started: boolean }
  private current?: Playback
  constructor(private readonly wire: SpeechWire, private readonly provider: () => Promise<SpeechProvider | null>) {}

  capability(supported: boolean): void {
    if (!supported) this.cancel()
    this.enabled = supported
  }
  arm(agentId: string): void {
    this.cancel()
    if (this.enabled && agentId && !this.busy.has(agentId)) this.intent = { agentId, expires: Date.now() + 180_000, started: false }
  }
  processing(agentId: string): void {
    this.busy.add(agentId)
    if (this.intent?.agentId === agentId) this.intent.started = true
  }
  /** A terminal footer proves existing work, not the start of our voice turn. */
  observeBusy(agentId: string): void {
    this.busy.add(agentId)
    if (this.intent?.agentId === agentId && !this.intent.started) this.intent = undefined
  }
  completed(agentId: string): void { this.busy.delete(agentId) }
  failed(agentId: string): void {
    this.busy.delete(agentId)
    if (this.intent?.agentId === agentId || this.playingAgent === agentId) this.cancel()
  }
  focus(agentId: string): void {
    if (this.intent && this.intent.agentId !== agentId) this.cancel()
    if (this.current && this.playingAgent !== agentId) this.cancel()
  }
  private playingAgent = ''
  cancel(): void {
    this.intent = undefined
    const old = this.current
    this.current = undefined; this.playingAgent = ''
    if (old) {
      old.abort.abort(); old.wake?.()
      this.abortWire(old.id)
    }
  }
  disconnect(): void { this.cancel(); this.enabled = false; this.busy.clear() }

  state(message: Record<string, unknown>): void {
    const p = this.current
    if (!p || message.id !== p.id) return
    if (Number.isInteger(message.error) && (message.error as number) > 0 && (message.error as number) <= 1000) {
      p.abort.abort(); p.wake?.(); return
    }
    const number = (key: string, max: number) => Number.isInteger(message[key]) &&
      (message[key] as number) >= 0 && (message[key] as number) <= max
    if (!number('received', p.sent) || !number('consumed', p.sent) ||
        !number('credit', MAX_BYTES + WIRE_WINDOW) || !number('error', 1000) ||
        typeof message.active !== 'boolean' || typeof message.playing !== 'boolean') return
    const next = message as unknown as DeviceState
    if (next.consumed > next.received || next.credit < next.received ||
        next.credit > next.received + WIRE_WINDOW || (p.state &&
        (next.received < p.state.received || next.consumed < p.state.consumed))) return
    p.state = next
    if (next.error || (!next.active && !p.ended)) p.abort.abort()
    p.wake?.()
  }

  async summary(agentId: string, recap: string, text: string, selected: string, silent: boolean): Promise<void> {
    const intent = this.intent
    if (!intent || intent.agentId !== agentId || silent || !intent.started) return
    this.intent = undefined
    if (!this.enabled || selected !== agentId || Date.now() > intent.expires) return
    let plan: ReturnType<typeof directCreatureSpeech>
    try { plan = directCreatureSpeech(text.trim().length <= 260 ? text : recap) }
    catch { try { plan = directCreatureSpeech(recap) } catch { return } }
    if (!plan.caption) return
    const p: Playback = { id: randomInt(1, 0x1_0000_0000), abort: new AbortController(), sent: 0, ended: false }
    this.current = p; this.playingAgent = agentId
    const deadline = setTimeout(() => { p.abort.abort(); p.wake?.() }, 45_000)
    try {
      const voice = await this.wait(p, () => this.provider())
      if (!voice || this.current !== p || p.abort.signal.aborted) return
      if (!await this.wait(p, () => this.wire.json({ t: 'speech.begin', id: p.id, agentId, sr: 16000, volume: PRO_SPEECH_VOLUME,
        caption: plan.caption, emotion: plan.emotion }), 4000)) return
      await this.until(p, () => !!p.state?.active, 2000)
      for await (const chunk of voice.stream(plan, p.abort.signal)) {
        if (!Buffer.isBuffer(chunk) || chunk.length % 2 || p.sent + chunk.length > MAX_BYTES) throw new Error('invalid_pcm')
        for (let at = 0; at < chunk.length;) {
          // The first PCM frame starts the Pro codec. Its initial credit is
          // ring space, not speaker readiness: a burst during codec startup
          // lost the second USB frame on the physical P4. Wait for the actual
          // playing acknowledgement before filling the normal credit window.
          // The first sound is sent immediately; there is no fixed sleep or retry.
          if (p.sent) await this.until(p, () => !!p.state?.playing, 4000)
          await this.until(p, () => (p.state?.credit ?? 0) - p.sent >= 2, 4000)
          const n = Math.min(CHUNK_BYTES, chunk.length - at, (p.state!.credit - p.sent) & ~1)
          const payload = Buffer.allocUnsafe(8 + n)
          payload.writeUInt32LE(p.id, 0); payload.writeUInt32LE(p.sent, 4)
          chunk.copy(payload, 8, at, at + n)
          applyProSpeechGain(payload.subarray(8))
          p.sent += n // reserve before an immediately resolving loopback ACK
          if (!await this.wait(p, () => this.wire.pcm(payload), 4000)) throw new Error('disconnected')
          // The USB serial peripheral cannot back-pressure an arriving burst.
          // Credit bounds ring occupancy; a receipt also proves this individual
          // frame crossed the link before the next one can be submitted.
          await this.until(p, () => (p.state?.received ?? 0) === p.sent, 4000)
          at += n
        }
      }
      if (this.current !== p || p.abort.signal.aborted || !p.sent) throw new Error('cancelled')
      p.ended = true
      if (!await this.wait(p, () => this.wire.json({ t: 'speech.end', id: p.id, bytes: p.sent }), 4000)) throw new Error('disconnected')
      await this.until(p, () => !!p.state && !p.state.active && !p.state.playing && p.state.consumed === p.sent, 35_000)
    } catch {
      // Text already reached the device. Never show provider bodies/keys, speak
      // transport failures, or retry a sentence that may already have been heard.
    } finally {
      clearTimeout(deadline)
      p.abort.abort(); p.wake?.()
      if (this.current === p) {
        this.current = undefined; this.playingAgent = ''
        this.abortWire(p.id)
      }
    }
  }
  /** Best effort: an unplugged or blocked port must not hold cancellation open. */
  private abortWire(id: number): void {
    try { void this.wire.json({ t: 'speech.abort', id }).catch(() => {}) }
    catch { /* A failed cleanup write never revives a cancelled utterance. */ }
  }
  /** Configuration and writes may finish late or never finish. Cancellation owns
   * each wait; an obsolete result can never start or resume an utterance. */
  private wait<T>(p: Playback, work: () => Promise<T>, timeout?: number): Promise<T> {
    if (this.current !== p || p.abort.signal.aborted) {
      return Promise.reject(new Error('cancelled'))
    }
    return new Promise<T>((resolve, reject) => {
      let timer: ReturnType<typeof setTimeout> | undefined
      const cleanup = () => { clearTimeout(timer); p.abort.signal.removeEventListener('abort', aborted) }
      const aborted = () => { cleanup(); reject(new Error('cancelled')) }
      p.abort.signal.addEventListener('abort', aborted, { once: true })
      if (timeout) timer = setTimeout(() => { p.abort.abort(); p.wake?.() }, timeout)
      try { work().then(value => { cleanup(); resolve(value) }, error => { cleanup(); reject(error) }) }
      catch (error) { cleanup(); reject(error) }
    })
  }
  private async until(p: Playback, ready: () => boolean, timeout: number): Promise<void> {
    const expires = Date.now() + timeout
    while (true) {
      if (this.current !== p || p.abort.signal.aborted) throw new Error('cancelled')
      if (ready()) return
      const left = expires - Date.now()
      if (left <= 0) throw new Error('speech_timeout')
      await new Promise<void>(resolve => {
        const timer = setTimeout(done, left)
        function done() { clearTimeout(timer); if (p.wake === done) p.wake = undefined; resolve() }
        p.wake = done
      })
    }
  }
}
