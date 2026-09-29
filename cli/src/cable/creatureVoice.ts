// Host-only speech. No credentials, provider tags or vendor errors belong on the dial.
import WebSocket from 'ws'

export type CreatureEmotion = 'neutral' | 'curious' | 'happy' | 'sad' | 'angry' | 'excited'
export type CreatureVoiceModel = 'eleven_v4_turbo' | 'eleven_v4'
export interface CreatureSpeechOptions {
  emotion?: CreatureEmotion
  /** Anger is opt-in, mild, and directed at a situation; never inferred from an error. */
  angerTarget?: 'situation'
}
export interface CreatureSpeechPlan {
  readonly caption: string
  readonly speechText: string
  readonly emotion: CreatureEmotion
  readonly angerTarget?: 'situation'
  /** Complete leading sentences were selected; the remainder stays on the desktop. */
  readonly isExcerpt?: true
}
export const CREATURE_PCM_RATE = 16_000
export const CREATURE_PCM_MAX_BYTES = 960_000 // 30 s × 16 kHz × signed 16-bit mono
export const CREATURE_PCM_CHUNK_BYTES = 4096
export const CREATURE_VOICE_MAX_MS = 30_000
export const CREATURE_SPEECH_MAX_CHARS = 220
export const CREATURE_VOICE_SETTINGS = Object.freeze({ stability: 0.5, similarity_boost: 0.75 })

export type CreatureVoiceErrorCode =
  | 'not_configured' | 'invalid_config' | 'empty_text' | 'text_too_long'
  | 'aborted' | 'deadline' | 'unavailable' | 'rejected' | 'protocol' | 'interrupted' | 'audio_limit'

const errorMessages: Record<CreatureVoiceErrorCode, string> = {
  not_configured: 'Companion voice is not configured.',
  invalid_config: 'Companion voice configuration is invalid.',
  empty_text: 'There is no speakable text.',
  text_too_long: 'This passage is too long for one spoken reply.',
  aborted: 'Companion speech was cancelled.',
  deadline: 'Companion speech took too long.',
  unavailable: 'Companion voice is unavailable.',
  rejected: 'The voice provider could not accept this reply.',
  protocol: 'The voice provider returned invalid audio.',
  interrupted: 'Companion speech ended before completion.',
  audio_limit: 'The spoken reply reached its audio limit.',
}
export class CreatureVoiceError extends Error {
  constructor(readonly code: CreatureVoiceErrorCode, readonly audioStarted = false) {
    super(errorMessages[code])
    this.name = 'CreatureVoiceError'
  }
}
class VoiceFault extends Error {
  constructor(readonly code: CreatureVoiceErrorCode) { super(code) }
}

/** Formatting removal, not a paraphrase. Input remains bounded before expression matching. */
export function creatureSpeakableText(input: string): string {
  if (typeof input !== 'string') throw new CreatureVoiceError('empty_text')
  if (input.length > 12_000) throw new CreatureVoiceError('text_too_long')
  const text = input
    .replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f\u200b-\u200f\u202a-\u202e\u2060-\u206f]/g, '')
    .replace(/\uFF3B/g, '[').replace(/\uFF3D/g, ']')
    .replace(/(?:&#(?:0*91|x0*5b);|&lbrack;)/gi, '[')
    .replace(/(?:&#(?:0*93|x0*5d);|&rbrack;)/gi, ']')
    .replace(/<script\b[^>]*>[\s\S]*?(?:<\/script>|$)/gi, ' ')
    .replace(/<style\b[^>]*>[\s\S]*?(?:<\/style>|$)/gi, ' ')
    .replace(/(^|\n)[ \t]*(\x60{3,}|~{3,})[^\n]*\n[\s\S]*?(?:\n[ \t]*\2[^\n]*(?=\n|$)|$)/g, ' ')
    .replace(/\x60+[^\x60]*(?:\x60+|$)/g, ' ')
    .replace(/!\[[^\]]*\]\([^)]*\)/g, ' ')
    .replace(/\[([^\]]+)\]\([^)]*\)/g, '$1')
    .replace(/\[[^\]]*\](?:\[[^\]]*\])?/g, ' ')
    .replace(/\[[^\]]*$/g, ' ')
    .replace(/<[^>]*>/g, ' ')
    .replace(/\b(?:[a-z][a-z0-9+.-]*:\/\/|www\.)[^\s<>()]+/gi, ' ')
    .replace(/^\s{0,3}(?:#{1,6}\s+|>\s*|[-*+]\s+|\d+[.)]\s+)/gm, '')
    .replace(/(\*\*|__|~~)(.*?)\1/g, '$2')
    .replace(/(^|\s)[*_]([^*_]+)[*_](?=\s|[.,!?;:]|$)/g, '$1$2')
    .replace(/\\([\\\x60*_{}[\]()#+.!>-])/g, '$1')
    .replace(/\s+/g, ' ').replace(/\s+([.,!?;:])/g, '$1').trim()
  if (!text || !/[\p{L}\p{N}]/u.test(text)) throw new CreatureVoiceError('empty_text')
  return text
}

const directions: Record<CreatureEmotion, string> = {
  // Keep the shared UI vocabulary compatible, but never use a neutral delivery.
  neutral: '[curious, playful]',
  curious: '[curious, playful]',
  happy: '[happy, warm]',
  sad: '[gentle, reassuring]',
  angry: '[mildly frustrated, controlled voice]',
  excited: '[excited, delighted]',
}
const failure = /\b(?:fail(?:ed|ure|ures)?|errors?|could not|couldn't|cannot|can't|unable|disconnect(?:ed)?|not delivered|not confirmed|did not|didn't|missing|lost|broken|blocked|not (?:yet )?(?:ready|complete|working|fixed|resolved|successful))\b/i
const success = /\b(?:good news|great news|we did it|it worked|all (?:checks|tests) passed|ready|complete(?:d)?|done|fixed|resolved|saved|committed|shipped)\b/i

/** A deterministic director: no LLM call, fabricated dialogue, or external performance tags. */
export function directCreatureSpeech(input: string, options: CreatureSpeechOptions = {}): CreatureSpeechPlan {
  const speakable = creatureSpeakableText(input)
  let caption = speakable
  if (caption.length > CREATURE_SPEECH_MAX_CHARS) {
    let end = 0
    for (const match of caption.matchAll(/[.!?。！？]["'’”)]*(?=\s|$)/g)) {
      const boundary = match.index + match[0].length
      if (boundary > CREATURE_SPEECH_MAX_CHARS) break
      end = boundary
    }
    // Do not cut a word or a sentence that may still contain its qualification.
    if (!end) throw new CreatureVoiceError('text_too_long')
    caption = caption.slice(0, end)
  }
  // A clean result may mention the errors it removed. Unresolved or mixed news
  // still wins over a success word, so failures are never celebrated.
  const difficulty = failure.test(caption
    .replace(/\b(?:no|zero) (?:errors?|failures?)\b/gi, '')
    .replace(/\b(?:errors?|failures?|problems?) (?:is|are|was|were|has been|have been) (?:fixed|resolved|gone)\b/gi, ''))
  const fallback: CreatureEmotion = difficulty ? 'sad' : 'curious'
  let emotion: CreatureEmotion = fallback
  if (options.emotion && Object.hasOwn(directions, options.emotion)) {
    emotion = options.emotion === 'neutral' ? fallback : options.emotion
  } else if (!difficulty && !/\?\s*$/.test(caption) && success.test(caption)) {
    emotion = /^(?:we did it|it worked)[!！]/i.test(caption) ? 'excited' : 'happy'
  }
  // Even an override cannot make a delivery failure sound playful or celebratory.
  if (difficulty && emotion !== 'angry') emotion = 'sad'
  if (emotion === 'angry' && (options.angerTarget !== 'situation' ||
      /\b(?:you|your|yours|u)\b/i.test(caption) ||
      !/\b(?:bug|glitch|delay|crash|build|connection|network|timeout|problem|error|hiccup)\b/i.test(caption))) emotion = fallback
  return Object.freeze({
    caption, speechText: directions[emotion] + ' ' + caption, emotion,
    ...(emotion === 'angry' ? { angerTarget: 'situation' as const } : {}),
    ...(caption !== speakable ? { isExcerpt: true as const } : {}),
  })
}

/** Local audition script only. Nothing generates audio merely by importing this module. */
export const CREATURE_VOICE_AUDITION = Object.freeze([
  { emotion: 'neutral', text: "I'm here. Take your time." },
  { emotion: 'curious', text: 'What would you like to explore next?' },
  { emotion: 'happy', text: 'Good news. All the checks passed.' },
  { emotion: 'sad', text: "I'm sorry that idea did not work out. We can try another way." },
  { emotion: 'angry', angerTarget: 'situation', text: 'That stubborn glitch is back. One step at a time.' },
  { emotion: 'excited', text: 'It worked! The little world is moving now.' },
] satisfies ReadonlyArray<{ emotion: CreatureEmotion; text: string; angerTarget?: 'situation' }>)

export type CreatureVoiceSocket = Pick<WebSocket, 'on' | 'off' | 'send' | 'close' | 'terminate' | 'readyState'>
export interface CreatureSocketOptions {
  headers: { 'xi-api-key': string }
  handshakeTimeout: number
  followRedirects: false
  maxPayload: number
}
export interface CreatureVoiceConfig {
  apiKey?: string
  voiceId?: string
  /** Turbo for live replies, v4 for an explicit quality audition. No silent model fallback. */
  model?: CreatureVoiceModel
  fetchImpl?: typeof fetch
  socketFactory?: (url: string, options: CreatureSocketOptions) => CreatureVoiceSocket
  /** May reduce the hard bounds for tests or a shorter local policy, never raise them. */
  timeoutMs?: number
  maxAudioBytes?: number
}
export interface CreatureVoiceProvider {
  readonly model: CreatureVoiceModel
  stream(plan: CreatureSpeechPlan | string, signal?: AbortSignal): AsyncGenerator<Buffer>
}

function waitFor<T>(work: Promise<T>, signal: AbortSignal): Promise<T> {
  if (signal.aborted) {
    void work.catch(() => {})
    return Promise.reject(new VoiceFault('aborted'))
  }
  return new Promise<T>((resolve, reject) => {
    const abort = () => { cleanup(); reject(new VoiceFault('aborted')) }
    const cleanup = () => signal.removeEventListener('abort', abort)
    signal.addEventListener('abort', abort, { once: true })
    work.then(value => { cleanup(); resolve(value) }, error => { cleanup(); reject(error) })
  })
}

async function* httpAudio(config: Required<Pick<CreatureVoiceConfig, 'apiKey' | 'voiceId'>>,
                         text: string, signal: AbortSignal, request: typeof fetch): AsyncGenerator<Buffer> {
  const attempt = request('https://api.elevenlabs.io/v1/text-to-speech/' + encodeURIComponent(config.voiceId) + '/stream?output_format=pcm_16000', {
    method: 'POST', redirect: 'error', signal,
    headers: { 'xi-api-key': config.apiKey, 'Content-Type': 'application/json', Accept: 'audio/pcm' },
    body: JSON.stringify({ text, model_id: 'eleven_v4', voice_settings: CREATURE_VOICE_SETTINGS }),
  })
  // An injected/nonconforming fetch might ignore abort and deliver its body later.
  void attempt.then(response => { if (signal.aborted) void response.body?.cancel().catch(() => {}) }).catch(() => {})
  const response = await waitFor(attempt, signal)
  let reader: ReadableStreamDefaultReader<Uint8Array> | undefined
  try {
    if (!response.ok) throw new VoiceFault('rejected')
    const format = response.headers.get('content-type')?.split(';')[0].trim().toLowerCase()
    if (format && !['audio/pcm', 'audio/x-pcm', 'application/octet-stream'].includes(format)) throw new VoiceFault('protocol')
    if (!response.body) throw new VoiceFault('protocol')
    reader = response.body.getReader()
    while (!signal.aborted) {
      const result = await waitFor(reader.read(), signal)
      if (result.done) return
      if (result.value.byteLength) yield Buffer.from(result.value.buffer, result.value.byteOffset, result.value.byteLength)
    }
    throw new VoiceFault('aborted')
  } finally {
    if (reader) {
      void reader.cancel().catch(() => {})
      reader.releaseLock()
    } else void response.body?.cancel().catch(() => {})
  }
}

async function* dialogueAudio(config: Required<Pick<CreatureVoiceConfig, 'apiKey' | 'voiceId'>>,
                             text: string, signal: AbortSignal, timeoutMs: number, maxBytes: number,
                             factory: NonNullable<CreatureVoiceConfig['socketFactory']>): AsyncGenerator<Buffer> {
  const socket = factory('wss://api.elevenlabs.io/v1/text-to-dialogue/stream-input?model_id=eleven_v4_turbo&output_format=pcm_16000', {
    headers: { 'xi-api-key': config.apiKey }, handshakeTimeout: timeoutMs,
    followRedirects: false, maxPayload: Math.ceil(maxBytes * 4 / 3) + 16_384,
  })
  const queue: Buffer[] = []
  let received = 0, finished = false, fault: VoiceFault | undefined, wake: (() => void) | undefined
  const notify = () => { wake?.(); wake = undefined }
  const fail = (code: CreatureVoiceErrorCode) => {
    if (finished || fault) return
    fault = new VoiceFault(code); queue.length = 0; notify()
  }
  const opened = () => {
    try {
      socket.send(JSON.stringify({ voices: [config.voiceId], voice_settings: CREATURE_VOICE_SETTINGS }))
      socket.send(JSON.stringify({ inputs: [{ text, voice_id: config.voiceId }] }))
      // Flushes short replies and requests a final acknowledgement for this one utterance.
      socket.send(JSON.stringify({ close_socket: true }))
    } catch { fail('unavailable') }
  }
  const message = (data: WebSocket.RawData, isBinary: boolean) => {
    if (finished || fault) return
    try {
      if (isBinary) throw new VoiceFault('protocol')
      const raw = Array.isArray(data) ? Buffer.concat(data) : Buffer.from(data as ArrayBuffer)
      if (raw.length > Math.ceil(maxBytes * 4 / 3) + 16_384) throw new VoiceFault('audio_limit')
      const frame: unknown = JSON.parse(raw.toString('utf8'))
      if (!frame || typeof frame !== 'object' || Array.isArray(frame)) throw new VoiceFault('protocol')
      const value = frame as Record<string, unknown>
      if (value.error || value.type === 'error') throw new VoiceFault('rejected')
      if (value.audio !== undefined && value.audio !== null && value.audio !== '') {
        if (typeof value.audio !== 'string' || value.audio.length % 4 ||
            !/^[A-Za-z0-9+/]*={0,2}$/.test(value.audio)) throw new VoiceFault('protocol')
        const chunk = Buffer.from(value.audio, 'base64')
        received += chunk.length
        if (received > maxBytes) throw new VoiceFault('audio_limit')
        if (chunk.length) queue.push(chunk)
      }
      if (value.is_final === true) finished = true
      notify()
    } catch (error) { fail(error instanceof VoiceFault ? error.code : 'protocol') }
  }
  const closed = () => { if (!finished) fail('interrupted') }
  const errored = () => fail('unavailable')
  const aborted = () => { fail('aborted'); socket.terminate() }
  socket.on('open', opened); socket.on('message', message); socket.on('close', closed); socket.on('error', errored)
  signal.addEventListener('abort', aborted, { once: true })
  try {
    if (signal.aborted) aborted()
    while (true) {
      if (fault) throw fault
      if (signal.aborted) throw new VoiceFault('aborted')
      const next = queue.shift()
      if (next) { yield next; continue }
      if (finished) return
      await new Promise<void>(resolve => { wake = resolve })
    }
  } finally {
    signal.removeEventListener('abort', aborted)
    socket.off('open', opened); socket.off('message', message); socket.off('close', closed); socket.off('error', errored)
    // Terminating a handshake can emit an asynchronous error after cleanup.
    socket.on('error', () => {})
    if (finished && socket.readyState === WebSocket.OPEN) socket.close(1000)
    else socket.terminate()
    queue.length = 0
  }
}

/** One request per iterator, no automatic retries, fixed provider origins, cancellable at every wait. */
export function createCreatureVoiceProvider(config: CreatureVoiceConfig): CreatureVoiceProvider {
  const apiKey = config.apiKey?.trim(), voiceId = config.voiceId?.trim()
  if (!apiKey || !voiceId) throw new CreatureVoiceError('not_configured')
  const model = config.model ?? 'eleven_v4_turbo'
  const timeoutMs = config.timeoutMs ?? CREATURE_VOICE_MAX_MS
  const maxBytes = config.maxAudioBytes ?? CREATURE_PCM_MAX_BYTES
  if (!/^[\x21-\x7e]{8,512}$/.test(apiKey) || !/^[A-Za-z0-9_-]{1,128}$/.test(voiceId) ||
      !['eleven_v4_turbo', 'eleven_v4'].includes(model) ||
      !Number.isInteger(timeoutMs) || timeoutMs < 1 || timeoutMs > CREATURE_VOICE_MAX_MS ||
      !Number.isInteger(maxBytes) || maxBytes < 2 || maxBytes > CREATURE_PCM_MAX_BYTES || maxBytes % 2) {
    throw new CreatureVoiceError('invalid_config')
  }
  const credentials = { apiKey, voiceId }
  const factory = config.socketFactory ?? ((url, options) => new WebSocket(url, options))
  const request = config.fetchImpl ?? fetch
  return {
    model,
    async *stream(input, externalSignal) {
      const plan = typeof input === 'string' ? directCreatureSpeech(input) : directCreatureSpeech(input.caption, input)
      const controller = new AbortController()
      let deadline = false, emitted = 0, received = 0, trailing: number | undefined
      const abort = () => controller.abort()
      externalSignal?.addEventListener('abort', abort, { once: true })
      if (externalSignal?.aborted) abort()
      const timer = setTimeout(() => { deadline = true; abort() }, timeoutMs)
      timer.unref?.()
      try {
        if (controller.signal.aborted) throw new VoiceFault('aborted')
        const source = model === 'eleven_v4'
          ? httpAudio(credentials, plan.speechText, controller.signal, request)
          : dialogueAudio(credentials, plan.speechText, controller.signal, timeoutMs, maxBytes, factory)
        for await (const raw of source) {
          if (controller.signal.aborted) throw new VoiceFault('aborted')
          received += raw.length
          if (received > maxBytes) throw new VoiceFault('audio_limit')
          let chunk = raw
          if (trailing !== undefined) { chunk = Buffer.concat([Buffer.from([trailing]), chunk]); trailing = undefined }
          if (chunk.length % 2) { trailing = chunk[chunk.length - 1]; chunk = chunk.subarray(0, -1) }
          for (let at = 0; at < chunk.length; at += CREATURE_PCM_CHUNK_BYTES) {
            if (controller.signal.aborted) throw new VoiceFault('aborted')
            const output = Buffer.from(chunk.subarray(at, at + CREATURE_PCM_CHUNK_BYTES))
            emitted += output.length
            yield output
          }
        }
        if (controller.signal.aborted) throw new VoiceFault('aborted')
        if (trailing !== undefined || !emitted) throw new VoiceFault('protocol')
      } catch (error) {
        throw new CreatureVoiceError(deadline ? 'deadline' : externalSignal?.aborted ? 'aborted' :
          error instanceof VoiceFault ? error.code : 'unavailable', emitted > 0)
      } finally {
        clearTimeout(timer)
        externalSignal?.removeEventListener('abort', abort)
        controller.abort()
      }
    },
  }
}
