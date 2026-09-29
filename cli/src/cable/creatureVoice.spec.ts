import { EventEmitter } from 'node:events'
import WebSocket from 'ws'
import { afterEach, describe, expect, it, vi } from 'vitest'
import {
  CREATURE_PCM_CHUNK_BYTES, CREATURE_PCM_MAX_BYTES, CREATURE_VOICE_AUDITION,
  CREATURE_VOICE_SETTINGS, CreatureVoiceError, createCreatureVoiceProvider,
  creatureSpeakableText, directCreatureSpeech,
  type CreatureVoiceConfig, type CreatureVoiceSocket,
} from './creatureVoice.js'

const credentials = { apiKey: 'test-secret-key-only', voiceId: 'test-voice-id' }
const collect = async (stream: AsyncIterable<Buffer>) => {
  const chunks: Buffer[] = []
  for await (const chunk of stream) chunks.push(chunk)
  return chunks
}
const result = (chunks: Buffer[]) => Buffer.concat(chunks)
const tick = () => new Promise<void>(resolve => queueMicrotask(resolve))
afterEach(() => vi.useRealTimers())

class Socket extends EventEmitter {
  readyState: WebSocket['readyState'] = WebSocket.CONNECTING
  sent: Record<string, unknown>[] = []
  close = vi.fn(() => { this.readyState = WebSocket.CLOSED })
  terminate = vi.fn(() => { this.readyState = WebSocket.CLOSED })
  send = vi.fn((data: string) => { this.sent.push(JSON.parse(data) as Record<string, unknown>) })
  open() { this.readyState = WebSocket.OPEN; this.emit('open') }
  frame(value: unknown) { this.emit('message', Buffer.from(JSON.stringify(value)), false) }
  audio(bytes: number[] | Buffer) { this.frame({ audio: Buffer.from(bytes).toString('base64') }) }
  final() { this.frame({ is_final: true }) }
}
function websocket(extra: Partial<CreatureVoiceConfig> = {}) {
  const socket = new Socket()
  const socketFactory = vi.fn(() => socket as unknown as CreatureVoiceSocket)
  const fetchImpl = vi.fn<typeof fetch>()
  const provider = createCreatureVoiceProvider({ ...credentials, socketFactory, fetchImpl, ...extra })
  return { socket, socketFactory, fetchImpl, provider }
}
function http(chunks: number[][], extra: Partial<CreatureVoiceConfig> = {}) {
  const cancel = vi.fn()
  const body = new ReadableStream<Uint8Array>({
    start(controller) { for (const bytes of chunks) controller.enqueue(Uint8Array.from(bytes)); controller.close() },
    cancel,
  })
  const fetchImpl = vi.fn<typeof fetch>(async () => new Response(body, { headers: { 'Content-Type': 'audio/pcm' } }))
  const provider = createCreatureVoiceProvider({ ...credentials, model: 'eleven_v4', fetchImpl, ...extra })
  return { provider, fetchImpl, cancel }
}

describe('creature speech director', () => {
  it('preserves ordinary words, numbers, punctuation and negation without a model call', () => {
    const text = 'Please do not delete the branch. One plus one is 2.'
    expect(directCreatureSpeech('**Please** do not delete the branch. One plus one is 2.')).toEqual({
      caption: text, speechText: '[curious, playful] ' + text, emotion: 'curious',
    })
  })

  it('strips code, URLs, images, Markdown and externally supplied performance tags', () => {
    const text = '# Read this\n[shouting] **Keep** [the summary](https://example.test/private).\n' +
      '![diagram](https://example.test/image)\n\x60\x60\x60sh\nrm -rf secrets\n\x60\x60\x60\n' +
      'Use \x60code_here()\x60 carefully. https://example.test/private\n<break time="10s"/>[angry]'
    const plan = directCreatureSpeech(text)
    expect(plan.caption).toContain('Keep the summary.')
    expect(plan.caption).not.toMatch(/https|secrets|shouting|angry|diagram|code_here|break|[#*[\]<>]/)
    expect(plan.speechText).toBe('[curious, playful] ' + plan.caption)
  })

  it('removes unclosed blocks/directives, hidden controls and full-width directives', () => {
    expect(creatureSpeakableText('Ready.\n~~~js\nneverSpeak()')).toBe('Ready.')
    expect(creatureSpeakableText('Ready. [shouting')).toBe('Ready.')
    expect(creatureSpeakableText('［angry］Ready.\u200b')).toBe('Ready.')
    expect(creatureSpeakableText('&#91;shouting&#93;Ready.')).toBe('Ready.')
    expect(creatureSpeakableText('Ready.<script>steal()</script>')).toBe('Ready.')
    expect(() => creatureSpeakableText('[excited] \x60onlyCode()\x60')).toThrowError(CreatureVoiceError)
  })

  it('makes ordinary replies curious and playful, including a legacy neutral override', () => {
    for (const text of ['Hello.', 'One plus one is two.', 'What would you like to try next?']) {
      for (const options of [{}, { emotion: 'neutral' as const }]) {
        const plan = directCreatureSpeech(text, options)
        expect(plan).toMatchObject({ caption: text, emotion: 'curious', speechText: '[curious, playful] ' + text })
      }
    }
    expect(directCreatureSpeech('The field is ready.', { emotion: 'neutral' }).emotion).toBe('curious')
  })

  it('makes real successes happy or excited without inventing words or laughter', () => {
    for (const text of ['Good news. All checks passed.', 'The field is ready.', 'Saved.',
      'All tests passed with no errors.', 'The error is resolved.']) {
      expect(directCreatureSpeech(text)).toMatchObject({ caption: text, emotion: 'happy', speechText: '[happy, warm] ' + text })
    }
    const text = 'It worked! The little world is moving now.'
    expect(directCreatureSpeech(text)).toMatchObject({ caption: text, emotion: 'excited', speechText: '[excited, delighted] ' + text })
    expect(directCreatureSpeech('Is the field ready?').emotion).toBe('curious')
  })

  it('makes failures gentle and reassuring even when the caller requests a cheerful or neutral voice', () => {
    const failures = ['The stream disconnected.', 'Why did the build fail?', 'Good news, except one error remains.',
      'The message could not be confirmed.', 'The field is not ready.']
    for (const text of failures) {
      for (const emotion of [undefined, 'neutral', 'curious', 'happy', 'sad', 'angry', 'excited'] as const) {
        const plan = directCreatureSpeech(text, { emotion })
        expect(plan).toMatchObject({ caption: text, emotion: 'sad', speechText: '[gentle, reassuring] ' + text })
        expect(plan.speechText).not.toMatch(/laugh|excited|happy|playful|cry|sob/)
      }
    }
  })

  it('allows all explicit moods while keeping words out of performance brackets', () => {
    expect(new Set(CREATURE_VOICE_AUDITION.map(line => line.emotion)).size).toBe(6)
    for (const line of CREATURE_VOICE_AUDITION) {
      const plan = directCreatureSpeech(line.text, line)
      expect(plan.emotion).toBe(line.emotion === 'neutral' ? 'curious' : line.emotion)
      expect(plan.caption).toBe(line.text)
      expect(plan.caption).not.toMatch(/[[\]]/)
      expect(plan.speechText.endsWith(line.text)).toBe(true)
    }
  })

  it('never infers anger and downgrades anger aimed at the listener', () => {
    expect(directCreatureSpeech('That stubborn glitch is back.').emotion).toBe('curious')
    expect(directCreatureSpeech('That stubborn glitch is back.', { emotion: 'angry' }).emotion).toBe('curious')
    expect(directCreatureSpeech('Your error caused this.', { emotion: 'angry', angerTarget: 'situation' }).emotion).toBe('sad')
    expect(directCreatureSpeech('I hate this.', { emotion: 'angry', angerTarget: 'situation' }).emotion).toBe('curious')
    const text = 'That stubborn glitch is back.'
    expect(directCreatureSpeech(text, { emotion: 'angry', angerTarget: 'situation' })).toMatchObject({
      caption: text, emotion: 'angry', angerTarget: 'situation', speechText: '[mildly frustrated, controlled voice] ' + text,
    })
  })

  it('refuses an oversize passage rather than truncating a qualification or negation', () => {
    expect(() => directCreatureSpeech('x'.repeat(221))).toThrowError('too long')
    expect(() => directCreatureSpeech('x'.repeat(601))).toThrowError('too long')
    expect(() => directCreatureSpeech('x'.repeat(12_001))).toThrowError('too long')
  })

  it('selects complete leading sentences for the Pro caption and marks the excerpt', () => {
    const lead = 'The landscape is ready. The text stays easy to read.'
    const plan = directCreatureSpeech(lead + ' ' + 'More detail remains on the desktop. '.repeat(10))
    expect(plan.caption.length).toBeLessThanOrEqual(220)
    expect(plan.caption.startsWith(lead)).toBe(true)
    expect(plan.caption.endsWith('.')).toBe(true)
    expect(plan.isExcerpt).toBe(true)
    expect(plan.speechText).toBe('[happy, warm] ' + plan.caption)
  })
})

describe('creature voice configuration and HTTP quality stream', () => {
  it('does not guess a voice or accept an origin/path through configuration', () => {
    expect(() => createCreatureVoiceProvider({})).toThrowError('not configured')
    for (const extra of [
      { voiceId: '../another-host' }, { apiKey: 'secret\r\nInjected: key' },
      { timeoutMs: 30_001 }, { maxAudioBytes: CREATURE_PCM_MAX_BYTES + 2 }, { maxAudioBytes: 3 },
    ]) expect(() => createCreatureVoiceProvider({ ...credentials, ...extra })).toThrowError('invalid')
  })

  it('streams v4 PCM from the fixed HTTPS origin, blocks redirects and repairs odd network splits', async () => {
    const { provider, fetchImpl } = http([[1], [2, 3, 4], [5], [6]])
    const chunks = await collect(provider.stream(directCreatureSpeech('Hello.')))
    expect(result(chunks)).toEqual(Buffer.from([1, 2, 3, 4, 5, 6]))
    expect(chunks.every(chunk => chunk.length % 2 === 0 && chunk.length <= CREATURE_PCM_CHUNK_BYTES)).toBe(true)
    const [url, options] = fetchImpl.mock.calls[0]
    expect(url).toBe('https://api.elevenlabs.io/v1/text-to-speech/test-voice-id/stream?output_format=pcm_16000')
    expect(options?.redirect).toBe('error')
    expect(options?.headers).toMatchObject({ 'xi-api-key': credentials.apiKey })
    expect(JSON.parse(options?.body as string)).toEqual({
      text: '[curious, playful] Hello.', model_id: 'eleven_v4', voice_settings: CREATURE_VOICE_SETTINGS,
    })
    expect(JSON.stringify({ url, body: options?.body })).not.toContain(credentials.apiKey)
    expect(options?.signal?.aborted).toBe(true)
  })

  it('does not trust caller-supplied speechText performance tags', async () => {
    const { provider, fetchImpl } = http([[0, 0]])
    await collect(provider.stream({ caption: '[shouting] Hello.', speechText: '[shouting] EVIL', emotion: 'neutral' }))
    expect(JSON.parse(fetchImpl.mock.calls[0][1]?.body as string).text).toBe('[curious, playful] Hello.')
  })

  it('caps output chunks even when one network read holds the whole reply', async () => {
    const bytes = new Array(12_000).fill(7)
    const { provider } = http([bytes])
    const chunks = await collect(provider.stream('Hello.'))
    expect(chunks.map(chunk => chunk.length)).toEqual([4096, 4096, 3808])
    expect(result(chunks)).toEqual(Buffer.from(bytes))
  })

  it.each([401, 422, 429, 503])('returns a safe error for HTTP %s without reading vendor detail', async status => {
    const vendor = vi.fn<typeof fetch>(async () => new Response('SECRET, private words, provider detail', { status }))
    const provider = createCreatureVoiceProvider({ ...credentials, model: 'eleven_v4', fetchImpl: vendor })
    const error = await collect(provider.stream('Hello.')).catch(value => value as CreatureVoiceError)
    expect(error).toMatchObject({ code: 'rejected', audioStarted: false })
    expect(JSON.stringify(error)).not.toMatch(/SECRET|private words|provider detail/)
    expect(vendor).toHaveBeenCalledTimes(1)
  })

  it('refuses encoded, empty, missing, or partial-sample audio', async () => {
    for (const response of [
      new Response(Buffer.from([0, 0]), { headers: { 'Content-Type': 'audio/mpeg' } }),
      new Response(null),
    ]) {
      const provider = createCreatureVoiceProvider({ ...credentials, model: 'eleven_v4', fetchImpl: async () => response })
      await expect(collect(provider.stream('Hello.'))).rejects.toMatchObject({ code: 'protocol', audioStarted: false })
    }
    await expect(collect(http([]).provider.stream('Hello.'))).rejects.toMatchObject({ code: 'protocol' })
    const partial = http([[0, 0], [1]])
    await expect(collect(partial.provider.stream('Hello.'))).rejects.toMatchObject({ code: 'protocol', audioStarted: true })
    expect(partial.fetchImpl).toHaveBeenCalledTimes(1)
  })

  it('refuses excess audio rather than silently cutting a successful utterance', async () => {
    const { provider, fetchImpl } = http([[1, 2], [3, 4, 5, 6]], { maxAudioBytes: 4 })
    const iterator = provider.stream('Hello.')
    expect((await iterator.next()).value).toEqual(Buffer.from([1, 2]))
    await expect(iterator.next()).rejects.toMatchObject({ code: 'audio_limit', audioStarted: true })
    expect(fetchImpl).toHaveBeenCalledTimes(1)
  })

  it('handles a pre-aborted signal without making a request', async () => {
    const { provider, fetchImpl } = http([[0, 0]])
    const controller = new AbortController(); controller.abort('PRIVATE caller reason')
    await expect(collect(provider.stream('Hello.', controller.signal))).rejects.toMatchObject({ code: 'aborted', audioStarted: false })
    expect(fetchImpl).not.toHaveBeenCalled()
  })

  it('bounds a fetch that never settles and cancels a late response body', async () => {
    vi.useFakeTimers()
    let finish!: (response: Response) => void
    const fetchImpl = vi.fn<typeof fetch>(() => new Promise<Response>(resolve => { finish = resolve }))
    const provider = createCreatureVoiceProvider({ ...credentials, model: 'eleven_v4', fetchImpl, timeoutMs: 50 })
    const pending = expect(collect(provider.stream('Hello.'))).rejects.toMatchObject({ code: 'deadline', audioStarted: false })
    await vi.advanceTimersByTimeAsync(50); await pending
    const cancel = vi.fn()
    finish(new Response(new ReadableStream({ cancel })))
    await tick(); await tick()
    expect(cancel).toHaveBeenCalledOnce()
    expect(vi.getTimerCount()).toBe(0)
  })

  it('aborts a hanging body read after audio, clears the deadline, and never retries', async () => {
    const cancel = vi.fn()
    const fetchImpl = vi.fn<typeof fetch>(async () => new Response(new ReadableStream<Uint8Array>({
      start(controller) { controller.enqueue(Uint8Array.from([1, 2])) }, cancel,
    })))
    const provider = createCreatureVoiceProvider({ ...credentials, model: 'eleven_v4', fetchImpl })
    const controller = new AbortController(), iterator = provider.stream('Hello.', controller.signal)
    expect((await iterator.next()).value).toEqual(Buffer.from([1, 2]))
    const pending = expect(iterator.next()).rejects.toMatchObject({ code: 'aborted', audioStarted: true })
    controller.abort(); await pending
    expect(cancel).toHaveBeenCalledOnce()
    expect(fetchImpl).toHaveBeenCalledOnce()
  })

  it('sanitizes exceptions and cleans the body on an early consumer return', async () => {
    const cancel = vi.fn()
    const fetchImpl = vi.fn<typeof fetch>(async () => new Response(new ReadableStream<Uint8Array>({
      start(controller) { controller.enqueue(Uint8Array.from([1, 2])) }, cancel,
    })))
    const provider = createCreatureVoiceProvider({ ...credentials, model: 'eleven_v4', fetchImpl })
    const iterator = provider.stream('Hello.')
    await iterator.next(); await iterator.return(undefined)
    expect(cancel).toHaveBeenCalledOnce()
    const failing = createCreatureVoiceProvider({ ...credentials, model: 'eleven_v4',
      fetchImpl: async () => { throw new Error('test-secret-key-only / PRIVATE transcript') },
    })
    const error = await collect(failing.stream('Hello.')).catch(value => value as CreatureVoiceError)
    expect(error).toMatchObject({ code: 'unavailable', audioStarted: false })
    expect(String(error)).not.toMatch(/secret|PRIVATE/)
  })
})

describe('Eleven v4 Turbo dialogue WebSocket', () => {
  it('registers one voice, sends plain-directed words, flushes short text and consumes final audio', async () => {
    const { provider, socket, socketFactory, fetchImpl } = websocket()
    const pending = collect(provider.stream('Hi.'))
    socket.open(); socket.audio([1]); socket.audio([2, 3]); socket.audio([4]); socket.final()
    expect(result(await pending)).toEqual(Buffer.from([1, 2, 3, 4]))
    expect(provider.model).toBe('eleven_v4_turbo')
    expect(socketFactory.mock.calls[0]).toMatchObject([
      'wss://api.elevenlabs.io/v1/text-to-dialogue/stream-input?model_id=eleven_v4_turbo&output_format=pcm_16000',
      { headers: { 'xi-api-key': credentials.apiKey }, followRedirects: false, handshakeTimeout: 30_000 },
    ])
    expect(socket.sent).toEqual([
      { voices: [credentials.voiceId], voice_settings: CREATURE_VOICE_SETTINGS },
      { inputs: [{ text: '[curious, playful] Hi.', voice_id: credentials.voiceId }] },
      { close_socket: true },
    ])
    expect(JSON.stringify(socket.sent)).not.toContain(credentials.apiKey)
    expect(socket.close).toHaveBeenCalledWith(1000)
    expect(fetchImpl).not.toHaveBeenCalled()
    expect(socket.listenerCount('message')).toBe(0)
  })

  it('does not treat a turn-boundary marker as the final stream acknowledgement', async () => {
    const { provider, socket } = websocket()
    const pending = collect(provider.stream('Hello.'))
    socket.open(); socket.audio([1, 2]); socket.frame({ is_final_audio_for_turn: true })
    socket.audio([3, 4]); socket.final()
    expect(result(await pending)).toEqual(Buffer.from([1, 2, 3, 4]))
  })

  it('cleans a stalled connection on deadline without exposing socket details', async () => {
    vi.useFakeTimers()
    const { provider, socket } = websocket({ timeoutMs: 50 })
    const pending = expect(collect(provider.stream('Hello.'))).rejects.toMatchObject({ code: 'deadline', audioStarted: false })
    await vi.advanceTimersByTimeAsync(50); await pending
    expect(socket.terminate).toHaveBeenCalled()
    expect(socket.listenerCount('message')).toBe(0)
    expect(vi.getTimerCount()).toBe(0)
    expect(() => socket.emit('error', new Error('late handshake failure'))).not.toThrow()
  })

  it('interrupts after emitted audio and never restarts the sentence', async () => {
    const { provider, socket, socketFactory } = websocket()
    const iterator = provider.stream('Hello.'), first = iterator.next()
    socket.open(); socket.audio([1, 2])
    expect((await first).value).toEqual(Buffer.from([1, 2]))
    socket.emit('close', 1006, Buffer.from('PRIVATE vendor close reason'))
    await expect(iterator.next()).rejects.toMatchObject({ code: 'interrupted', audioStarted: true })
    expect(socketFactory).toHaveBeenCalledOnce()
  })

  it.each([
    { error: 'PRIVATE provider secret' }, { type: 'error', message: 'PRIVATE' },
    { audio: 'not valid base64!' }, { audio: 123 }, [],
  ])('rejects malformed or error frames safely: %j', async frame => {
    const { provider, socket } = websocket()
    const pending = collect(provider.stream('Hello.')).catch(value => value as CreatureVoiceError)
    socket.open(); socket.frame(frame)
    const error = await pending
    expect(error).toBeInstanceOf(CreatureVoiceError)
    expect(String(error)).not.toContain('PRIVATE')
    expect(socket.terminate).toHaveBeenCalled()
  })

  it('bounds queued audio before the consumer drains it', async () => {
    const { provider, socket } = websocket({ maxAudioBytes: 4 })
    const pending = expect(collect(provider.stream('Hello.'))).rejects.toMatchObject({ code: 'audio_limit', audioStarted: false })
    socket.open(); socket.audio([1, 2]); socket.audio([3, 4, 5, 6]); await pending
  })

  it('rejects a final odd byte without inventing a sample', async () => {
    const { provider, socket } = websocket()
    const pending = expect(collect(provider.stream('Hello.'))).rejects.toMatchObject({ code: 'protocol', audioStarted: false })
    socket.open(); socket.audio([1]); socket.final(); await pending
  })

  it('aborts immediately during live playback and removes listeners', async () => {
    const { provider, socket } = websocket()
    const controller = new AbortController(), iterator = provider.stream('Hello.', controller.signal)
    const first = iterator.next(); socket.open(); socket.audio([1, 2]); await first
    const pending = expect(iterator.next()).rejects.toMatchObject({ code: 'aborted', audioStarted: true })
    controller.abort('PRIVATE'); await pending
    expect(socket.terminate).toHaveBeenCalled()
    expect(socket.listenerCount('message')).toBe(0)
  })
})
