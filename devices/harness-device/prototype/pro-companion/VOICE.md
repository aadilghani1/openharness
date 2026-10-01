# A voice for the Field companion

For quick speaker comparisons, **Menu → Voice** now provides 16 saved recordings
with emotion/parameter notes, Play/Stop and live volume controls starting at 80%.
It works without the desktop or provider connection. See
[the on-device sample library](voice-samples/README.md). Its volume and voice
selection affect auditions only; the conversational path below remains separate.

Octo has a bright, playful, curious voice with clear emotion in everyday replies.
The user rejected the first restrained voice as boring and explicitly requested
emotional delivery. Routine speech now uses playful curiosity; good news has
warm delight and difficulty has gentle reassurance. No flat neutral delivery,
forced laughter, baby voice or announcer cadence is intended.

The host module is [creatureVoice.ts](../../../../cli/src/cable/creatureVoice.ts),
with [local transport tests](../../../../cli/src/cable/creatureVoice.spec.ts).
There is no hard-coded voice ID. The current local configuration selects the
original designed **Octo - Spark** voice: a youthful androgynous adult, rounded
medium-high register, expressive pitch movement and nimble conversational timing.
It replaces Octo - Little Company, which is retained as an audition artifact.
No existing person's voice was cloned. A 7.04-second excited sample was sent
through the physical Pro speaker; final voice preference belongs to the listener.

## Provider choice and documented transports

Research checked against primary ElevenLabs documentation on 2026-09-29:

- **Eleven v4 Turbo** (`eleven_v4_turbo`) is the conversation default. ElevenLabs
  describes approximately 100 ms median model inference, excluding the rest of
  the network and playback path. This is a provider claim, not a measurement on
  the Pro. [Models](https://elevenlabs.io/docs/overview/models)
- Turbo uses the documented **Text to Dialogue WebSocket**. One connection
  registers one voice, sends the complete short utterance, then requests
  `close_socket` to flush it. The iterator waits for `is_final`, not merely a
  turn-boundary marker. This also works for replies too short to meet the
  server's usual text buffer threshold.
  [Realtime dialogue guide](https://elevenlabs.io/docs/eleven-api/guides/how-to/websockets/realtime-tdd)
- **Eleven v4** (`eleven_v4`) is an explicit quality/audition option, using HTTPS
  `POST /v1/text-to-speech/:voice_id/stream?output_format=pcm_16000`.
  The current playground guide explicitly supports this model on Stream
  speech. The provider does not silently substitute models.
  [Product guide](https://elevenlabs.io/docs/eleven-creative/playground/text-to-speech),
  [Stream speech API](https://elevenlabs.io/docs/api-reference/text-to-speech/stream)

The older WebSocket API reference still contains v3-only wording; the current
realtime guide explicitly demonstrates `eleven_v4_turbo` and its one-voice
registration. The code follows that newer guide, while using the reference's
message fields. Both transports succeeded with the actual trial account and
selected voice on 2026-09-29; transport fixtures alone do not establish this.
[WebSocket reference](https://elevenlabs.io/docs/api-reference/text-to-dialogue/ttd-websocket)

Both modes request mono signed 16-bit PCM at 16 kHz. The starting settings are
`stability: 0.5` and `similarity_boost: 0.75`. These are a stable audition
baseline, not a guarantee of identical delivery. V4 exposes Stability and
Similarity; this module sends no Style, Speed, SSML, speaker-boost or deprecated
latency setting.
[V4 guide](https://elevenlabs.io/docs/overview/capabilities/text-to-speech/eleven-v4)

## Direction without changing the message

`directCreatureSpeech(text, options)` returns `{caption, speechText, emotion}`.
Markdown decoration, code, URLs, HTML and externally supplied performance
directives are removed first. Captions contain no performance tags. Spoken
words match the caption; the director only prepends its own delivery instruction.
It does not make another model request or invent conversational filler.

The short reply budget is **220 characters**. For longer input, only complete
leading sentences are selected, and `isExcerpt: true` marks the result. An
overlong first sentence is refused instead of losing a trailing qualification.
Full output belongs in the desktop or reader, not an endlessly talking creature.

| Emotion | Direction | Default use |
| --- | --- | --- |
| Neutral (compatibility input only) | Mapped to expressive curiosity or reassurance | Never emitted as a neutral performance |
| Curious | Curious, playful | Ordinary conversation and questions |
| Happy | Happy, warm | Successful outcomes and good news |
| Sad | Gentle, reassuring | Difficulty or an explicit sympathetic reply |
| Angry | Mildly frustrated, controlled | Explicit situation-only override; never inferred |
| Excited | Excited, delighted | A clear celebratory result or explicit override |

Anger requires a named situation such as a bug or glitch and rejects
listener-directed wording. Unresolved or mixed failure language takes precedence
over success words. A legacy neutral override still receives expressive delivery.
Caption wording is preserved; emotion does not add invented dialogue.
The English heuristic is deterministic; explicit host direction is available.

Tags are auditory direction, not instructions to add words or effects. Their
precise performance still needs audition with the selected voice. The provider
rebuilds directed speech from a plan's plain caption, so a caller-supplied
`speechText` cannot smuggle new tags.
[Prompting guidance](https://elevenlabs.io/docs/overview/capabilities/text-to-speech/best-practices)

## Local audition manifest

`CREATURE_VOICE_AUDITION` exports these original lines and explicit emotions.
Importing it does not generate or purchase audio.

| Emotion | Line |
| --- | --- |
| Neutral input → Curious delivery | I'm here. Take your time. |
| Curious | What would you like to explore next? |
| Happy | Good news. All the checks passed. |
| Sad | I'm sorry that idea did not work out. We can try another way. |
| Angry, at the situation | That stubborn glitch is back. One step at a time. |
| Excited | It worked! The little world is moving now. |

Compare a few suitable source voices using the same lines, settings and speaker
volume. Listen on the Pro as well as a computer: intelligibility at low volume,
clear consonants, consistent loudness, a believable quiet reply, and controlled
excitement matter more than one impressive demo. Prefer a warm midrange with
enough contrast for the small speaker; avoid breathy, boomy or piercing voices.
These are audition criteria, not findings from an unauditioned voice.

The earlier voice API trial generated all six Turbo lines and a V4 neutral comparison.
All seven returned valid 16 kHz PCM, with no clipped digital samples. Turbo's
first neutral request took 4,052 ms to its first PCM chunk; the following curious,
happy, sad and angry requests took 287–407 ms, and excited took 1,098 ms. V4's
neutral comparison took 1,494 ms. These are individual network observations,
not percentile guarantees or speaker latency. Zero digital clipping does not
establish the physical speaker's distortion or clarity.

The final **Octo - Spark** live trial generated a happy reply using the actual
configured provider and playback controller. All **161,280 bytes / 5.04 seconds**
were received and consumed by the Pro with error zero. The first provider audio
arrived 839 ms after the diagnostic started (including serial ownership handoff),
and the whole trial took 6,180 ms. This one observation is not a latency guarantee
or confirmation of the listener's acoustic preference.

## Local configuration and playback

`~/.harness/creature-voice.json` selects `enabled`, `voiceId` and `model`; this
file contains no API key. On this Mac the test key is in Keychain under service
`harness.creature-voice.elevenlabs`, account `elevenlabs-d-test`. The provider
can also use `ELEVENLABS_API_KEY` and `ELEVENLABS_VOICE_ID` from the host process.
Credentials never enter firmware, captions or device logs.

The Pro advertises `speech: pcm16-v1`. A fresh, successful device voice submission
arms one reply for its selected pane. A subsequent new working event and fresh
summary are required. Recovered activity, old notifications, ordinary desktop
turns and other panes do not start speech. New capture, touch, a changed pane or
machine, sleep, lock and disconnect interrupt playback. The spoken caption is
plain text and the previous summary returns afterward.

Speech uses 90 percent codec volume independently of muted notification sounds,
as selected after the on-device comparison on 2026-09-29.
Host PCM receives fourfold soft gain with a 0.63 full-scale ceiling, matching the
louder physical sample. It preserves the byte count and sample rate and adds no
prebuffering. The ceiling leaves headroom for the measured +3.5 dB codec gain.
This bounds digital levels; acoustic distortion still needs listening.

The first PCM frame starts the speaker immediately. The host waits for the
actual `playing` acknowledgement before sending more, then waits for the exact
byte receipt after each frame, while also respecting absolute ring credit. At most one 2 KiB PCM
frame is in flight. The firmware sends byte receipts and playback transitions
immediately; progress-only updates remain throttled to 25 Hz. On the physical P4,
sending an initial
burst during codec startup lost the second frame; a controlled comparison with
the same 225,280-byte sample failed without the readiness gate and completed with
it. A later live-provider trial reproduced the loss after a network stall, showing
that startup gating alone was insufficient. Per-frame receipts now protect every
network burst. Readiness, receipt and credit waits are each bounded to four
seconds and are interruptible; no fixed sleep or automatic replay is used.

The device uses a preallocated 64 KiB PSRAM ring and bounded 20 ms
I2S writes; it does not decode MP3 or synthesize speech. Mouth motion follows
the playback level, with subtle shared emotion expressions. The host bounds
transport writes to four seconds and the complete attempt to 45 seconds;
cancellation does not wait for a stalled write or provider lookup.

The local bridge selects this new session only for trial Pro
`E8:F6:0A:E7:64:61`. Round dials retain the installed session implementation.
Its per-Pro USB lease allows an explicit sample or flash without taking serial
ownership from another reader; the ordinary app session resumes afterward.

## Integration contract and limits

`createCreatureVoiceProvider({apiKey, voiceId, model})` returns a provider whose
`stream(plan, abortSignal)` is an async generator of PCM `Buffer` chunks.
Keys and voice IDs remain on the host. HTTPS/WSS origins are fixed; redirects
are disabled, and the credential is sent only in the provider request header.
No module path writes credentials, logs text, or prints provider error bodies.

Each utterance is bounded by **30 seconds of wall time** and **960,000 audio
bytes**. A smaller bound may be injected, never a larger one. Chunks are even
length and at most 4,096 bytes, including when network packets split a PCM
sample. An odd final byte, unexpected encoded format, missing final message,
oversize result or empty audio is an error. Limits do not become a false
successful completion.

Abort covers connection setup and a stalled response body. Consumer return
closes the source; callers that need to interrupt a pending `next()` must abort
its signal. The integration should abort on a new voice capture, loss of the
chosen recipient or disconnect, and keep playback separate from recording.
The module performs **no retries**. `CreatureVoiceError` reports a stable
`code` and `audioStarted` flag; it never includes raw provider exceptions,
request text, caller abort reasons or secrets. A partially audible reply must
not restart itself.

The bounded provider does not implement an autonomous conversation loop,
continuous microphone capture, offline synthesis, or a device-held API key.
Playback integration and physical acoustic testing remain separate from its
transport tests.

## Check locally

With the repository's normal CLI dependencies already present:

```sh
cd cli
npm test -- src/cable/creatureVoice.spec.ts --maxWorkers=1
npm run typecheck
```

The tests inject fetch and WebSocket implementations. They make no network
requests, use no real credentials and exercise packet boundaries, limits,
deadlines, cancellation, early return, malformed/error frames, safe diagnostics,
caption sanitization, complete-sentence selection and emotion policy.
