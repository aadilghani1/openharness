// Explicit local speaker check using the same transport/controller as replies.
// Reuses generated PCM by default; --live explicitly uses the configured provider.
// Neither mode submits a user turn. Both require the exact connected trial Pro.
import { readFile, writeFile, unlink } from 'node:fs/promises'
import { execFile } from 'node:child_process'
import { promisify } from 'node:util'
import { CableSpeech } from '../../../../../cli/src/cable/cableSpeech.js'
import { configuredCreatureVoice } from '../../../../../cli/src/cable/creatureVoiceConfig.js'
import { CableDecoder, CableType, encodeCableFrame } from '../../../../../cli/src/cable/cableFrame.js'
import { SerialLink, findDialPorts } from '../../../../../cli/src/cable/serial.js'

const base = '/private/tmp/pro-concepts-20260929'
const serial = 'E8:F6:0A:E7:64:61'
const lease = '/Users/autonomous/.harness/flasher/pro-companion-e8-f6-0a-e7-64-61.lease'
const run = promisify(execFile)
const pause = (ms: number) => new Promise(resolve => setTimeout(resolve, ms))
const ports = (await findDialPorts()).filter(p => p.serialNumber?.toUpperCase() === serial)
if (ports.length !== 1) throw new Error('Exact Pro unavailable')
const log = await readFile('/Users/autonomous/.harness/logs/usb-E8-F6-0A-E7-64-61/dial-20260929.log', 'utf8')
const rosterStart = log.lastIndexOf('cable_client: agents:')
const recentRoster = log.slice(Math.max(0, rosterStart))
const agent = process.argv.find(a => a.startsWith('--agent='))?.slice(8) ??
  [...recentRoster.matchAll(/cable_client: summary ([a-zA-Z0-9-]{8,})/g)].at(-1)?.[1]
if (!agent || !/^[a-zA-Z0-9-]{8,47}$/.test(agent) || !log.includes(agent))
  throw new Error('No real desktop pane is known')
const audition = JSON.parse(await readFile(base + '/voice-auditions/lively/audition.json', 'utf8'))
const pcm = await readFile(base + '/voice-auditions/lively/octo-spark.pcm')
if (pcm.length !== audition.bytes) throw new Error('Unexpected sample')
const live = process.argv.includes('--live')
const caption = live ? "Good news! My new voice is ready. Let's make something fun together." : audition.caption
let audioBytes = live ? 0 : pcm.length
let firstAudioMs = 0
await writeFile(lease, JSON.stringify({ serial, until: Date.now() + 60_000 }), { flag: 'wx', mode: 0o600 })
let port: SerialLink | undefined
let timer: ReturnType<typeof setInterval> | undefined
let controller: CableSpeech | undefined
const states: Record<string, unknown>[] = []
const logs: string[] = []
const tx: Record<string, unknown>[] = []
const decoder = new CableDecoder()
const started = Date.now()
try {
  for (let n = 0; ; n++) {
    const busy = await run('lsof', ['-t', ports[0].path]).then(r => !!r.stdout.trim(), e => e.code === 1 ? false : Promise.reject(e))
    if (!busy) break
    if (n >= 50) throw new Error('Bridge did not release Pro')
    await pause(200)
  }
  const json = async (message: Record<string, unknown>) => {
    if (!port) return false
    tx.push({ ms: Date.now() - started, ...message })
    await port.write(encodeCableFrame(CableType.Json, Buffer.from(JSON.stringify(message))))
    return true
  }
  controller = new CableSpeech({ json, pcm: async payload => {
    if (!port) return false
    tx.push({ ms: Date.now() - started, t: 'pcm', id: payload.readUInt32LE(0), offset: payload.readUInt32LE(4), bytes: payload.length - 8 })
    await port.write(encodeCableFrame(CableType.Speech, payload)); return true
  } }, async () => {
    if (!live) return { async *stream() {
      for (let at = 0; at < pcm.length; at += 4096) yield pcm.subarray(at, at + 4096)
    } }
    const voice = await configuredCreatureVoice()
    if (!voice) throw new Error('Voice configuration unavailable')
    return { async *stream(plan, signal) {
      for await (const part of voice.stream(plan, signal)) {
        if (!firstAudioMs) firstAudioMs = Date.now() - started
        audioBytes += part.length
        yield part
      }
    } }
  })
  port = await SerialLink.open(ports[0].path, data => decoder.feed(data, frame => {
    if (frame.type === CableType.Log) { logs.push(Buffer.from(frame.payload).toString()); return }
    if (frame.type !== CableType.Json) return
    const message = JSON.parse(Buffer.from(frame.payload).toString())
    if (message.t === 'speech.state') { states.push(message); controller!.state(message) }
  }), () => {})
  timer = setInterval(() => void json({ t: 'ping' }), 2000)
  await json({ t: 'ping' })
  await json({ t: 'focus', agentId: agent })
  controller.capability(true); controller.arm(agent); controller.processing(agent)
  await controller.summary(agent, caption, caption, agent, false)
  await pause(100)
  const done = states.find(s => audioBytes > 0 && s.received === audioBytes && s.consumed === audioBytes && s.active === false && s.playing === false && s.error === 0)
  const report = { verified: !!done, serial, agent, volume: tx.find(m => m.t === 'speech.begin')?.volume, readiness_gate: true, pcm_bytes: audioBytes, live_provider: live, caption, first_audio_ms: firstAudioMs,
    elapsed_ms: Date.now() - started, last_state: states.at(-1), states, logs, tx,
    corrupt_frames: decoder.corruptFrames }
  await writeFile(base + (live ? '/companion-speaker-live-trial.json' : '/companion-speaker-controller-trial.json'), JSON.stringify(report, null, 2))
  console.log(JSON.stringify({ ...report, states: states.length, logs: logs.length, tx: tx.length }))
  if (!done) throw new Error('Production speech controller did not complete the sample')
} finally {
  clearInterval(timer); controller?.disconnect()
  await port?.close('sample complete')
  await unlink(lease)
}
