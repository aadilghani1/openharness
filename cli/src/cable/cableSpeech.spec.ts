import { EventEmitter } from 'node:events'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { applyProSpeechGain, CableSpeech, type SpeechProvider, type SpeechWire } from './cableSpeech.js'
import { createCreatureVoiceProvider, type CreatureVoiceSocket } from './creatureVoice.js'

const settle = async () => { for (let i = 0; i < 24; i++) await Promise.resolve() }
const sessions: CableSpeech[] = []
afterEach(() => { sessions.splice(0).forEach(s => s.disconnect()); vi.useRealTimers() })

function deferred<T>() {
  let resolve!: (value: T) => void, reject!: (error: unknown) => void
  const promise = new Promise<T>((yes, no) => { resolve = yes; reject = no })
  return { promise, resolve, reject }
}
function pcm16(samples: number[]): Buffer {
  const bytes = Buffer.alloc(samples.length * 2)
  samples.forEach((sample, at) => bytes.writeInt16LE(sample, at * 2))
  return bytes
}
function samples(pcm: Buffer): number[] {
  return Array.from({ length: pcm.length / 2 }, (_, at) => pcm.readInt16LE(at * 2))
}
function fixture(options: { bytes?: Buffer; provider?: () => Promise<SpeechProvider | null>;
  autoReady?: boolean; autoCredit?: boolean; autoDrain?: boolean; autoPlaying?: boolean } = {}) {
  const messages: Record<string, unknown>[] = [], frames: Buffer[] = []
  const stream = vi.fn(async function* () { yield options.bytes ?? Buffer.from([1, 2, 3, 4]) })
  const provider = vi.fn(options.provider ?? (async () => ({ stream })))
  let id = 0, received = 0
  const wire: SpeechWire = {
    json: vi.fn(async message => {
      messages.push(message)
      if (message.t === 'speech.begin') {
        id = message.id as number; received = 0
        if (options.autoReady !== false) state()
      }
      if (message.t === 'speech.end' && options.autoDrain !== false) {
        state({ active: false, playing: false, received, consumed: received, credit: received })
      }
      return true
    }),
    pcm: vi.fn(async payload => {
      frames.push(Buffer.from(payload)); received = payload.readUInt32LE(4) + payload.length - 8
      if (options.autoCredit !== false) state({ received, consumed: options.autoPlaying !== false ? received : 0, credit: received + 8192,
        playing: options.autoPlaying !== false })
      return true
    }),
  }
  const speech = new CableSpeech(wire, provider)
  sessions.push(speech); speech.capability(true)
  function state(fields: Record<string, unknown> = {}) {
    speech.state({ id, active: true, playing: received > 0 && options.autoPlaying !== false, received: 0, consumed: 0, credit: 8192, error: 0, ...fields })
  }
  function reply(text = 'The field is ready.', recap = 'The field is ready.') {
    speech.arm('a1'); speech.processing('a1'); speech.completed('a1')
    return speech.summary('a1', recap, text, 'a1', false)
  }
  return { speech, provider, stream, wire, messages, frames, state, reply, id: () => id,
    types: () => messages.map(m => m.t) }
}

describe('Pro reply audio level', () => {
  it('preserves silence and applies the auditioned fourfold soft gain without adding bytes', () => {
    const silence = Buffer.alloc(2048)
    expect(applyProSpeechGain(silence)).toBe(silence)
    expect(silence).toEqual(Buffer.alloc(2048))
    expect(samples(applyProSpeechGain(pcm16([-32768, -16384, -4096, -1000, -1, 0, 1, 1000, 4096, 16384, 32767]))))
      .toEqual([-20643, -20571, -13634, -3951, -4, 0, 4, 3951, 13634, 20571, 20643])
    expect(applyProSpeechGain(Buffer.alloc(0))).toEqual(Buffer.alloc(0))
  })

  it('preserves sign and ordering across every signed 16-bit input with bounded peaks', () => {
    const input = Array.from({ length: 65536 }, (_, i) => i - 32768)
    const output = samples(applyProSpeechGain(pcm16(input)))
    expect(output.length).toBe(input.length)
    expect(output.every((sample, i) => Math.sign(sample) === Math.sign(input[i]))).toBe(true)
    expect(output.every((sample, i) => i === 0 || sample >= output[i - 1])).toBe(true)
    expect(Math.min(...output)).toBe(-20643)
    expect(Math.max(...output)).toBe(20643)
  })

  it('is identical across arbitrary sample-aligned chunks and never touches framing bytes', () => {
    const input = pcm16(Array.from({ length: 7000 }, (_, i) => (i * 37 % 65536) - 32768))
    const expected = applyProSpeechGain(Buffer.from(input))
    const parts: Buffer[] = []
    let at = 0
    for (const size of [2, 510, 2048, 14, 4096, input.length]) {
      const end = Math.min(at + size, input.length)
      const framed = Buffer.alloc(8 + end - at, 0x55)
      input.copy(framed, 8, at, end)
      applyProSpeechGain(framed.subarray(8))
      expect(framed.subarray(0, 8)).toEqual(Buffer.alloc(8, 0x55))
      parts.push(framed.subarray(8)); at = end
    }
    expect(Buffer.concat(parts)).toEqual(expected)
    expect(input).toEqual(pcm16(Array.from({ length: 7000 }, (_, i) => (i * 37 % 65536) - 32768)))
  })

  it('refuses a partial sample before altering the supplied bytes', () => {
    const odd = Buffer.from([1, 2, 3])
    expect(() => applyProSpeechGain(odd)).toThrow('invalid_pcm')
    expect(odd).toEqual(Buffer.from([1, 2, 3]))
  })

  it('sends the boosted first chunk without waiting for later provider audio', async () => {
    const next = deferred<void>(), input = pcm16([-1000, 0, 1000]), original = Buffer.from(input)
    const stream = async function* () { yield input; await next.promise; yield input }
    const f = fixture({ provider: async () => ({ stream }) })
    const done = f.reply(); await settle()
    expect(f.frames).toHaveLength(1)
    expect(f.frames[0].subarray(8)).toEqual(applyProSpeechGain(Buffer.from(input)))
    expect(f.messages[0]).toMatchObject({ t: 'speech.begin', sr: 16000, volume: 90 })
    expect(input).toEqual(original)
    next.resolve(); await done
    expect(f.frames).toHaveLength(2)
    expect(f.frames[1].readUInt32LE(4)).toBe(input.length)
    expect(f.frames[1].subarray(8)).toEqual(f.frames[0].subarray(8))
  })

  it('keeps a device without the Pro speech capability silent', async () => {
    const f = fixture(); f.speech.capability(false); await f.reply()
    expect(f.provider).not.toHaveBeenCalled(); expect(f.frames).toEqual([]); expect(f.messages).toEqual([])
  })
})

describe('spoken replies follow one fresh voice turn', () => {
  it('requires a processing event after arm and consumes the reply once', async () => {
    const f = fixture()
    await f.speech.summary('a1', 'Old result.', 'Old result.', 'a1', false)
    f.speech.arm('a1')
    await f.speech.summary('a1', 'Old result.', 'Old result.', 'a1', false)
    expect(f.provider).not.toHaveBeenCalled()
    f.speech.processing('a1')
    await f.speech.summary('a1', 'Ready.', 'Ready.', 'a1', false)
    await f.speech.summary('a1', 'Duplicate.', 'Duplicate.', 'a1', false)
    expect(f.provider).toHaveBeenCalledOnce()
    expect(f.types()).toEqual(['speech.begin', 'speech.end', 'speech.abort'])
  })

  it('does not arm a voice submission while the same agent is already busy', async () => {
    const f = fixture()
    f.speech.processing('a1'); f.speech.arm('a1'); f.speech.processing('a1')
    f.speech.completed('a1')
    await f.speech.summary('a1', 'The older turn ended.', 'The older turn ended.', 'a1', false)
    expect(f.provider).not.toHaveBeenCalled()
    await f.reply()
    expect(f.provider).toHaveBeenCalledOnce()
  })

  it.each(['before arm', 'after arm'] as const)('does not treat recovered terminal activity %s as a new turn', async when => {
    const f = fixture()
    if (when === 'before arm') f.speech.observeBusy('a1')
    f.speech.arm('a1')
    if (when === 'after arm') f.speech.observeBusy('a1')
    f.speech.processing('a1')
    await f.speech.summary('a1', 'Earlier work.', 'Earlier work.', 'a1', false)
    expect(f.provider).not.toHaveBeenCalled()
  })

  it('does not let a later terminal observation erase an already correlated fresh turn', async () => {
    const f = fixture()
    f.speech.arm('a1'); f.speech.processing('a1'); f.speech.observeBusy('a1')
    await f.speech.summary('a1', 'Fresh reply.', 'Fresh reply.', 'a1', false)
    expect(f.provider).toHaveBeenCalledOnce()
  })

  it('keeps restored and subagent summaries silent without stealing the actual reply', async () => {
    const f = fixture()
    f.speech.arm('a1'); f.speech.processing('a1')
    await f.speech.summary('a1', 'Restored.', 'Restored.', 'a1', true)
    await f.speech.summary('child', 'Subagent.', 'Subagent.', 'a1', false)
    expect(f.provider).not.toHaveBeenCalled()
    await f.speech.summary('a1', 'Actual reply.', 'Actual reply.', 'a1', false)
    expect(f.provider).toHaveBeenCalledOnce()
  })

  it.each(['unselected', 'expired', 'disabled', 'failed', 'disconnected', 'focus'] as const)
    ('keeps a %s reply silent', async reason => {
      vi.useFakeTimers()
      const f = fixture()
      f.speech.arm('a1'); f.speech.processing('a1')
      if (reason === 'expired') vi.setSystemTime(Date.now() + 180_001)
      if (reason === 'disabled') f.speech.capability(false)
      if (reason === 'failed') f.speech.failed('a1')
      if (reason === 'disconnected') f.speech.disconnect()
      if (reason === 'focus') f.speech.focus('a2')
      await f.speech.summary('a1', 'Ready.', 'Ready.', reason === 'unselected' ? 'a2' : 'a1', false)
      expect(f.provider).not.toHaveBeenCalled(); expect(f.messages).toEqual([])
    })

  it('does not cancel a reply when the same pane focus is echoed', async () => {
    const f = fixture()
    f.speech.arm('a1'); f.speech.processing('a1'); f.speech.focus('a1')
    await f.speech.summary('a1', 'Ready.', 'Ready.', 'a1', false)
    expect(f.provider).toHaveBeenCalledOnce()
  })

  it('clears stale busy records when the physical connection ends', async () => {
    const f = fixture()
    f.speech.processing('a1'); f.speech.disconnect(); f.speech.capability(true)
    await f.reply()
    expect(f.provider).toHaveBeenCalledOnce()
  })
})

describe('speech framing and device credit', () => {
  it('sends one startup frame, then waits for playing even when the pending ring has credit', async () => {
    const f = fixture({ bytes: Buffer.alloc(8192, 7), autoPlaying: false })
    const done = f.reply(); await settle()
    expect(f.frames).toHaveLength(1)
    expect(f.frames[0].readUInt32LE(4)).toBe(0)
    f.state({ playing: false, received: 2048, credit: 10240 })
    await settle(); expect(f.frames).toHaveLength(1)
    f.state({ id: (f.id() % 0xffff_ffff) + 1, playing: true, received: 2048, credit: 10240 })
    await settle(); expect(f.frames).toHaveLength(1)
    // Once warm, every subsequent ACK reports the real playing state.
    f.wire.pcm = async payload => {
      f.frames.push(Buffer.from(payload))
      const received = payload.readUInt32LE(4) + payload.length - 8
      f.state({ playing: true, received, consumed: received, credit: received + 8192 })
      return true
    }
    f.wire.json = async message => {
      f.messages.push(message)
      if (message.t === 'speech.end') f.state({ active: false, playing: false,
        received: 8192, consumed: 8192, credit: 8192 })
      return true
    }
    f.state({ playing: true, received: 2048, consumed: 0, credit: 10240 })
    await done
    expect(f.frames.map(p => p.readUInt32LE(4))).toEqual([0, 2048, 4096, 6144])
    expect(f.types()).toContain('speech.end')
  })

  it('cancels a speaker startup wait without sending another frame after a late acknowledgement', async () => {
    const f = fixture({ bytes: Buffer.alloc(8192), autoPlaying: false })
    const done = f.reply(); await settle(); expect(f.frames).toHaveLength(1)
    f.speech.cancel(); await done
    f.state({ playing: true, received: 2048, consumed: 0, credit: 10240 })
    await settle(); expect(f.frames).toHaveLength(1)
    expect(f.types()).not.toContain('speech.end')
  })

  it('transmits exactly 20 KiB, with a session id and consecutive byte offsets on each 2048-byte frame', async () => {
    const bytes = Buffer.from(Array.from({ length: 20 * 1024 }, (_, i) => i % 251))
    const f = fixture({ bytes })
    await f.reply()
    expect(f.frames).toHaveLength(10)
    for (const [i, frame] of f.frames.entries()) {
      expect(frame.length).toBe(8 + 2048)
      expect(frame.readUInt32LE(0)).toBe(f.id())
      expect(frame.readUInt32LE(4)).toBe(i * 2048)
    }
    expect(Buffer.concat(f.frames.map(p => p.subarray(8)))).toEqual(applyProSpeechGain(Buffer.from(bytes)))
    expect(f.messages[0]).toMatchObject({ t: 'speech.begin', agentId: 'a1', sr: 16000, volume: 90,
      caption: 'The field is ready.', emotion: 'happy' })
    expect(f.messages[1]).toEqual({ t: 'speech.end', id: f.id(), bytes: bytes.length })
  })

  it('waits for each receipt and ignores wrong-session, impossible and reordered acknowledgements', async () => {
    const f = fixture({ bytes: Buffer.alloc(8192, 7), autoCredit: false })
    const done = f.reply(); await settle(); expect(f.frames).toHaveLength(1)
    f.state({ id: (f.id() % 0xffff_ffff) + 1, playing: true, received: 2048, credit: 10240 })
    f.state({ received: 2049, consumed: 0, credit: 10241 })
    f.state({ received: 2048, consumed: 2049, credit: 10240 })
    f.state({ received: 2048, consumed: 0, credit: 10241 })
    await settle(); expect(f.frames).toHaveLength(1)
    f.state({ playing: true, received: 2048, consumed: 0, credit: 10240 })
    await settle(); expect(f.frames).toHaveLength(2)
    f.state({ playing: true, received: 1024, consumed: 0, credit: 9216 })
    await settle(); expect(f.frames).toHaveLength(2)
    f.state({ playing: true, received: 4096, consumed: 2048, credit: 12288 })
    await settle(); expect(f.frames).toHaveLength(3)
    f.state({ playing: true, received: 6144, consumed: 1024, credit: 14336 })
    await settle(); expect(f.frames).toHaveLength(3)
    f.state({ playing: true, received: 6144, consumed: 4096, credit: 14336 })
    await settle(); expect(f.frames).toHaveLength(4)
    f.state({ playing: true, received: 8192, consumed: 6144, credit: 16384 })
    await done
    expect(Buffer.concat(f.frames.map(p => p.subarray(8)))).toEqual(applyProSpeechGain(Buffer.alloc(8192, 7)))
  })

  it('does not treat a receipt as permission to exceed ring credit', async () => {
    const f = fixture({ bytes: Buffer.alloc(4096), autoCredit: false })
    const done = f.reply(); await settle(); expect(f.frames).toHaveLength(1)
    f.state({ playing: true, received: 2048, consumed: 0, credit: 2048 })
    await settle(); expect(f.frames).toHaveLength(1)
    f.state({ playing: true, received: 2048, consumed: 512, credit: 4096 })
    await settle(); expect(f.frames).toHaveLength(2)
    f.state({ playing: true, received: 4096, consumed: 2048, credit: 4096 })
    await done; expect(f.types()).toContain('speech.end')
  })

  it('honors a firmware rejection with received=0 after playback has progressed', async () => {
    const f = fixture({ bytes: Buffer.alloc(20_000), autoCredit: false })
    const done = f.reply(); await settle(); expect(f.frames).toHaveLength(1)
    f.state({ playing: true, received: 2048, consumed: 2048, credit: 10240 })
    await settle(); expect(f.frames).toHaveLength(2)
    f.speech.state({ id: f.id(), error: 100, received: 0 })
    await done; expect(f.frames).toHaveLength(2)
    expect(f.types()).toEqual(['speech.begin', 'speech.abort'])
  })

  it('does not accept a rejection for a different session', async () => {
    const f = fixture({ bytes: Buffer.alloc(2048), autoCredit: false })
    const done = f.reply(); await settle()
    f.speech.state({ id: (f.id() % 0xffff_ffff) + 1, error: 100, received: 0 })
    f.state({ playing: true, received: 2048, consumed: 2048, credit: 10240 })
    await done; expect(f.types()).toContain('speech.end')
  })

  it.each([Buffer.alloc(3), Buffer.alloc(960_002)])('rejects invalid PCM before writing any of it', async bytes => {
    const f = fixture({ bytes }); await f.reply()
    expect(f.frames).toEqual([]); expect(f.types()).toEqual(['speech.begin', 'speech.abort'])
  })

  it('does not restart or duplicate audible bytes when a provider fails mid-sentence', async () => {
    const stream = vi.fn(async function* () { yield Buffer.from([1, 2]); throw new Error('private provider response') })
    const f = fixture({ provider: async () => ({ stream }) }); await f.reply()
    expect(stream).toHaveBeenCalledOnce(); expect(f.frames).toHaveLength(1)
    expect(f.types()).toEqual(['speech.begin', 'speech.abort'])
    expect(JSON.stringify(f.messages)).not.toContain('private provider response')
  })
})

describe('speech cancellation and bounded waits', () => {
  it.each([false, true])('closes a held v4 Turbo dialogue socket immediately (audible=%s)', async audible => {
    const socket = Object.assign(new EventEmitter(), {
      readyState: 0,
      send: vi.fn(), close: vi.fn(), terminate: vi.fn(),
    })
    const socketFactory = vi.fn(() => socket as unknown as CreatureVoiceSocket)
    const provider = createCreatureVoiceProvider({ apiKey: 'test-secret-only', voiceId: 'test-voice', socketFactory })
    const f = fixture({ provider: async () => provider })
    const done = f.reply(); await settle()
    expect(socketFactory).toHaveBeenCalledOnce()
    socket.readyState = 1; socket.emit('open')
    if (audible) socket.emit('message', Buffer.from(JSON.stringify({ audio: Buffer.from([1, 2]).toString('base64') })), false)
    await settle(); expect(f.frames).toHaveLength(audible ? 1 : 0)
    f.speech.cancel(); await done
    expect(socket.terminate).toHaveBeenCalled()
    expect(f.types()).toEqual(['speech.begin', 'speech.abort'])
    expect(socket.listenerCount('message')).toBe(0)
  })

  it.each(['cancel', 'new voice', 'focus', 'disconnect', 'failed', 'capability'] as const)
    ('aborts a held HTTP network read on %s', async cause => {
      const bodyCancelled = vi.fn()
      const body = new ReadableStream<Uint8Array>({ cancel: bodyCancelled })
      const fetchImpl = vi.fn<typeof fetch>(async () => new Response(body, { headers: { 'content-type': 'audio/pcm' } }))
      const realProvider = createCreatureVoiceProvider({ apiKey: 'test-secret-only', voiceId: 'test-voice',
        model: 'eleven_v4', fetchImpl })
      const f = fixture({ provider: async () => realProvider })
      const done = f.reply()
      await vi.waitFor(() => expect(body.locked).toBe(true))
      if (cause === 'cancel') f.speech.cancel()
      if (cause === 'new voice') f.speech.arm('a1')
      if (cause === 'focus') f.speech.focus('a2')
      if (cause === 'disconnect') f.speech.disconnect()
      if (cause === 'failed') f.speech.failed('a1')
      if (cause === 'capability') f.speech.capability(false)
      await done
      expect(bodyCancelled).toHaveBeenCalledOnce(); expect(body.locked).toBe(false)
      expect((fetchImpl.mock.calls[0][1]!.signal as AbortSignal).aborted).toBe(true)
      expect(f.frames).toEqual([]); expect(f.types()).toEqual(['speech.begin', 'speech.abort'])
    })

  it('cancels a held read after the first audible bytes without replaying them', async () => {
    const cancel = vi.fn()
    const body = new ReadableStream<Uint8Array>({ start(c) { c.enqueue(Uint8Array.from([1, 2, 3, 4])) }, cancel })
    const provider = createCreatureVoiceProvider({ apiKey: 'test-secret-only', voiceId: 'test-voice', model: 'eleven_v4',
      fetchImpl: async () => new Response(body, { headers: { 'content-type': 'audio/pcm' } }) })
    const f = fixture({ provider: async () => provider })
    const done = f.reply(); await vi.waitFor(() => expect(f.frames).toHaveLength(1))
    f.speech.cancel(); await done
    expect(cancel).toHaveBeenCalledOnce(); expect(f.frames).toHaveLength(1)
    expect(f.types()).not.toContain('speech.end')
  })

  it.each([
    { name: 'ready acknowledgement', options: { autoReady: false }, duration: 2000, frames: 0 },
    { name: 'speaker startup', options: { autoPlaying: false, bytes: Buffer.alloc(8192) }, duration: 4000, frames: 1 },
    { name: 'frame receipt', options: { autoCredit: false, bytes: Buffer.alloc(10_000) }, duration: 4000, frames: 1 },
    { name: 'playback drain', options: { autoDrain: false }, duration: 35_000, frames: 1 },
  ])('bounds the $name wait', async ({ options, duration, frames }) => {
    vi.useFakeTimers()
    const f = fixture(options)
    let ended = false
    const done = f.reply().then(() => { ended = true })
    await settle(); expect(f.frames).toHaveLength(frames)
    await vi.advanceTimersByTimeAsync(duration - 1); expect(ended).toBe(false)
    await vi.advanceTimersByTimeAsync(1); await done
    expect(ended).toBe(true); expect(f.types().at(-1)).toBe('speech.abort')
  })

  it.each([
    ['begin', 'cancel'], ['pcm', 'cancel'], ['end', 'cancel'],
    ['begin', 'timeout'], ['pcm', 'timeout'], ['end', 'timeout'],
  ] as const)('releases a stuck %s write on %s and ignores its late resolution', async (phase, reason) => {
    vi.useFakeTimers()
    const f = fixture(), held = deferred<boolean>()
    const json = f.wire.json, pcm = f.wire.pcm
    f.wire.json = async message => {
      const result = await json(message)
      return message.t === 'speech.' + phase || message.t === 'speech.abort' ? held.promise : result
    }
    f.wire.pcm = async bytes => {
      const result = await pcm(bytes)
      return phase === 'pcm' ? held.promise : result
    }
    let ended = false
    const done = f.reply().then(() => { ended = true })
    await settle(); expect(ended).toBe(false)
    if (phase === 'begin') expect(f.types()).toEqual(['speech.begin'])
    if (phase === 'pcm') expect(f.frames).toHaveLength(1)
    if (phase === 'end') expect(f.types()).toContain('speech.end')
    if (reason === 'cancel') f.speech.cancel()
    else await vi.advanceTimersByTimeAsync(4000)
    await settle(); expect(ended).toBe(true); await done
    const framesAtCancel = f.frames.length
    expect(f.types().at(-1)).toBe('speech.abort')
    held.resolve(true); await settle(); expect(f.frames).toHaveLength(framesAtCancel)
  })

  it('never waits on the best-effort abort write during final cleanup', async () => {
    const f = fixture(), json = f.wire.json
    f.wire.json = async message => {
      const result = await json(message)
      return message.t === 'speech.abort' ? new Promise<boolean>(() => {}) : result
    }
    await f.reply()
    expect(f.types()).toEqual(['speech.begin', 'speech.end', 'speech.abort'])
  })

  it('does not begin speech when configuration arrives after cancellation', async () => {
    const late = deferred<SpeechProvider | null>(), stream = vi.fn(async function* () { yield Buffer.from([0, 0]) })
    const f = fixture({ provider: () => late.promise })
    const done = f.reply(); await settle(); f.speech.cancel()
    late.resolve({ stream }); await done
    expect(stream).not.toHaveBeenCalled(); expect(f.types()).toEqual(['speech.abort'])
  })

  it('consumes a late configuration rejection after cancellation without an unhandled promise', async () => {
    const late = deferred<SpeechProvider | null>()
    const f = fixture({ provider: () => late.promise })
    const done = f.reply(); await settle(); f.speech.cancel(); await done
    late.reject(new Error('late private configuration failure')); await settle()
    expect(f.types()).toEqual(['speech.abort'])
  })

  it('ends cancellation even when configuration never resolves', async () => {
    const f = fixture({ provider: () => new Promise(() => {}) })
    let ended = false
    const done = f.reply().then(() => { ended = true })
    await settle(); f.speech.cancel(); await settle()
    expect(ended).toBe(true); await done
  })

  it('bounds unresolved configuration by the whole-conversation deadline', async () => {
    vi.useFakeTimers()
    const f = fixture({ provider: () => new Promise(() => {}) })
    let ended = false
    const done = f.reply().then(() => { ended = true })
    await vi.advanceTimersByTimeAsync(45_000)
    expect(ended).toBe(true); await done
    expect(f.types()).toEqual(['speech.abort'])
  })

  it('does not throw from malformed or unspeakable Markdown and falls back to a usable recap', async () => {
    const f = fixture()
    await expect(f.reply('[shouting] \x60\x60\x60sh\nsecret()', '[angry]')).resolves.toBeUndefined()
    expect(f.provider).not.toHaveBeenCalled()
    await f.reply('[shouting] \x60\x60\x60sh\nsecret()', 'The text is ready.')
    expect(f.messages[0]).toMatchObject({ caption: 'The text is ready.', emotion: 'happy' })
    expect(JSON.stringify(f.messages)).not.toMatch(/shouting|angry|secret/)
  })

  it('contains configuration failures without exposing their text to the device', async () => {
    const f = fixture({ provider: async () => { throw new Error('provider-private-key') } })
    await expect(f.reply()).resolves.toBeUndefined()
    expect(f.types()).toEqual(['speech.abort'])
    expect(JSON.stringify(f.messages)).not.toContain('provider-private-key')
  })
})
