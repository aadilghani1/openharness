# Voice samples on the Pro

Open **Menu → Voice**. Play replays the selected recording; it becomes Stop
while audio is starting or playing. Previous and Next choose a recording without
playing it. The − and + buttons change volume in ten-point steps, from mute to
100%, including during playback without restarting it. Volume starts at **80%**
and stays selected until reboot. It is separate from notification mute and the
desktop conversation voice configuration.

**Params** shows the voice ID, model, audio tag, stability, similarity, seed and
a listening note for that recording. The caption contains the spoken words.
Returning from Params keeps playback running. Leaving Voice, changing sample,
locking or sleeping stops it. Nothing in this menu sends a message to an agent
or starts the microphone. It works while the desktop is disconnected.

## Included recordings

| Number | Voice | Comparison |
| --- | --- | --- |
| 1 | Octo – Spark | The original excited speaker-test clip |
| 2 | Spark | Playful baseline |
| 3 | Jessica | Same words, tag and settings; different voice |
| 4 | Callum | Same words, tag and settings; different voice |
| 5–11 | Spark | Happy, excited, curious, sad, angry at a glitch, whisper, laugh |
| 12–13 | Spark | Baseline words/tag with stability 0 and 1 |
| 14–15 | Spark | Baseline words/tag with similarity 0.25 and 1 |
| 16 | Spark | Baseline words/tag/settings using v4 Turbo |

The ordinary baseline is stability **0.5**, similarity **0.75**. Clips 2–15 use
`eleven_v4`; clips 1 and 16 use `eleven_v4_turbo`. The v4 requests use English,
automatic text normalization and seed 1363. The Turbo requests use provider
defaults for those fields. A seed is best effort, not guaranteed reproducibility.
Replay uses the same saved bytes on every device, so it is useful for comparing
speakers and volume; it does not measure live model latency or variability.

Spark is our original designed voice. Jessica and Callum are provider voices;
none of these recordings clones a particular person. The exact request text,
settings, voice IDs, durations and hashes are recorded in [samples.json](samples.json).
The same words are used for voice/model/settings comparisons. Emotion examples
use matching dialogue, so they are examples rather than a controlled comparison
of a tag alone. Tags guide a performance and do not guarantee the intended emotion.

## Provider parameters

Checked against the live model catalog and official documentation on 2026-10-01:

- V4 and v4 Turbo support stability and similarity. Lower stability allows more
  varied delivery; higher similarity asks for closer adherence to the reference.
  The models do not expose speed, style or speaker-boost controls, and do not
  support SSML. [V4 guide](https://elevenlabs.io/docs/overview/capabilities/text-to-speech/eleven-v4)
- Audio tags in square brackets can direct emotion, delivery and nonverbal
  reactions. The examples deliberately show the tag separately from the caption.
  [Prompting guidance](https://elevenlabs.io/docs/overview/capabilities/text-to-speech/best-practices)
- The wider TTS API includes seed, language, text normalization, context and
  pronunciation dictionaries. These are not independent emotion controls and
  support is model/endpoint dependent. There is no silent model fallback.
  [TTS API](https://elevenlabs.io/docs/api-reference/text-to-speech/convert)
- V4 recordings use HTTPS streaming; Turbo uses the documented Text to Dialogue
  WebSocket and waits for the final audio marker.
  [Realtime guide](https://elevenlabs.io/docs/eleven-api/guides/how-to/websockets/realtime-tdd)

## Storage and playback

The 16 recordings contain 62.16 seconds of 16 kHz mono audio. `samples.pack` uses
**497,280 bytes** of flash: 4-bit IMA ADPCM, high nibble first, predictor/index
initially zero for each clip. This is lossy compression, not the original provider
PCM. Original PCM hashes and independent decoded hashes remain in the manifest.

The player decodes into a 2 KiB static scratch block and feeds the existing
64 KiB bounded speech ring. It adds no task, heap allocation, filesystem access
or network wait. A poll feeds at most 4 KiB every 20 ms. The codec worker applies
live volume at a block boundary. There is no full-clip decode on a touch handler.
All clips use the same 4× soft gain with a 0.63 ceiling, implemented by integer
table interpolation; there is no per-clip loudness normalization. Quiet delivery
therefore remains quieter. Start/volume responsiveness is covered by native
tests, not claimed as measured physical touch-to-sound latency.

Local auditions and desktop speech have separate session ownership. A desktop
disconnect cannot abort a local clip or receive its speech receipts. Incoming
conversation audio receives busy/rejected behavior while the local speaker is
occupied. Leaving the page releases it for normal conversation.

## Rebuild the pack

Normal firmware builds embed the checked-in pack and never contact ElevenLabs.
To explicitly purchase new recordings, use Node with the CLI dependencies
installed and an `ELEVENLABS_API_KEY` environment variable (or the existing local
macOS Keychain entry). Keep cached PCM outside the repository:

```sh
node devices/harness-device/prototype/pro-companion/tools/generate_voice_samples.mjs \
  --output=/absolute/path/to/voice-review \
  --original=/absolute/path/to/saved/octo-spark.pcm
```

The generator resumes cached recordings. Use a fresh output directory when
changing parameters. The original clip is reused, never silently regenerated.
No credentials are written into metadata, firmware or logs. Pack offline using
**Python 3.12**, whose standard-library `audioop` provides the independent encoder:

```sh
python3.12 devices/harness-device/prototype/pro-companion/tools/pack_voice_samples.py \
  --manifest=/absolute/path/to/voice-review/samples.json \
  --audio-dir=/absolute/path/to/voice-review/audio
```

Validation commands, from the repository root:

```sh
python3 devices/harness-device/firmware/test/test_pro_voice_samples.py
python3 devices/harness-device/firmware/test/test_audio_speech.py
python3 devices/harness-device/firmware/test/test_cable_speech.py
python3 devices/harness-device/firmware/test/test_pro_controls.py
python3 devices/harness-device/firmware/test/test_pro_touch_ui.py
```

The decoder is checked byte-for-byte against independently generated PCM hashes
for every recording. The player tests cover completion, bounded queueing, live
volume without restart, stop, busy/retry and missing speaker. UI tests use the
production touch handlers and render all 16 playback and parameter sheets.
