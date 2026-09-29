import { execFile } from 'node:child_process'
import { readFile } from 'node:fs/promises'
import { homedir } from 'node:os'
import { join } from 'node:path'
import { promisify } from 'node:util'
import { createCreatureVoiceProvider } from './creatureVoice.js'
import type { SpeechProvider } from './cableSpeech.js'
const exec = promisify(execFile)

/** Configuration is local to the computer. Neither key nor voice-provider
 * metadata is sent to the firmware or included in device logs. */
export async function configuredCreatureVoice(): Promise<SpeechProvider | null> {
  try {
    let config: { voiceId?: string; enabled?: boolean; model?: string } = {}
    try { config = JSON.parse(await readFile(join(homedir(), '.harness', 'creature-voice.json'), 'utf8')) } catch {}
    if (config.enabled === false) return null
    const voiceId = process.env.ELEVENLABS_VOICE_ID || config.voiceId
    if (!voiceId || !/^[a-zA-Z0-9_-]{1,128}$/.test(voiceId)) return null
    let apiKey = process.env.ELEVENLABS_API_KEY?.trim()
    if (!apiKey && process.platform === 'darwin') {
      const result = await exec('/usr/bin/security', ['find-generic-password', '-s', 'harness.creature-voice.elevenlabs',
        '-a', 'elevenlabs-d-test', '-w'], { timeout: 2000, maxBuffer: 4096 })
      apiKey = result.stdout.trim()
    }
    if (!apiKey) return null
    return createCreatureVoiceProvider({ apiKey, voiceId,
      model: config.model === 'eleven_v4' ? 'eleven_v4' : 'eleven_v4_turbo' })
  } catch { return null }
}
