import { describe, expect, it, vi } from 'vitest'
import { CodexNormalizer } from '../engines/codex/normalizer.js'
import { CodexTurnRecovery, codexStoppedGoal, type CodexTurnSnapshot } from './codexTurnRecovery.js'

// The live footer from the interrupted cmd p session on M2. Its rollout ended
// with token_count and thread_settings_applied, never task_complete/turn_aborted.
const screen = [
  '■ Conversation interrupted - use /feedback if something went wrong',
  '  ↳ Recap: Previous work is saved.', '',
  '\x1b[1m\x1b[38;5;215m›\x1b[0m \x1b[2mAsk Codex to do anything\x1b[0m', '',
  '  \x1b[38;5;223mGPT-6-Astra max\x1b[39m · ~/work \x1b[38;5;5mGoal stalled (/goal resume)\x1b[39m',
  '  \x1b[1m?\x1b[0m for shortcuts                       ⚠ 1 warning · f2 to view',
].join('\n')
const record = (type: string) => JSON.stringify({ type: 'event_msg', payload: { type, message: 'Continue the work' } })
function openNormalizer() {
  const normalizer = new CodexNormalizer('live')
  normalizer.ingest(record('task_started'))
  normalizer.ingest(record('user_message'))
  return normalizer
}
function setup() {
  let now = 0
  const normalizer = openNormalizer()
  let snapshot: CodexTurnSnapshot | undefined = { normalizer, runtimeKey: 'agent:tmux:%31:pid:18662' }
  const capture = vi.fn(async (): Promise<string | null> => screen)
  const drain = vi.fn(async () => {})
  const recovered = vi.fn()
  const recovery = new CodexTurnRecovery({ snapshot: () => snapshot, capture, drain, recovered, now: () => now })
  return { normalizer, capture, drain, recovered, recovery,
    replace: (value?: CodexTurnSnapshot) => { snapshot = value },
    tick: async (ms = 5_000) => { now += ms; await recovery.check('session') },
  }
}

describe('Codex stopped-goal footer', () => {
  it('recognizes the live interrupted goal and its paused equivalent', () => {
    expect(codexStoppedGoal(screen)).toBe(true)
    expect(codexStoppedGoal(screen.replace('stalled', 'paused'))).toBe(true)
  })
  it.each([
    null, '', screen.replace('Goal stalled (/goal resume)', 'Goal active'),
    screen.replace('Goal stalled (/goal resume)', ''),
    screen.replace('\x1b[2mAsk Codex to do anything\x1b[0m', 'please continue'),
    screen + '\nSelect Model and Effort',
    screen.replace('■ Conversation interrupted', '• Working (1h · esc to interrupt)\n■ Conversation interrupted'),
    'Goal stalled (/goal resume)\n› \x1b[2mAsk Codex to do anything\x1b[0m\n? for shortcuts',
    screen.replace('?\x1b[0m for shortcuts', '?\x1b[0m something else'),
  ])('does not treat active, unknown, historical or draft UI as stopped', value => {
    expect(codexStoppedGoal(value)).toBe(false)
  })
})

describe('Codex turn recovery', () => {
  it('repairs the missing end only after quietness and two separated live confirmations', async () => {
    const t = setup()
    await t.tick(0)
    await t.tick(29_999)
    expect(t.capture).not.toHaveBeenCalled()
    await t.tick(1)
    expect(t.normalizer.turnOpen).toBe(true)
    await t.tick(4_999)
    expect(t.capture).toHaveBeenCalledTimes(1)
    await t.tick(1)
    expect(t.normalizer.turnOpen).toBe(false)
    expect(t.recovered).toHaveBeenCalledOnce()
    await t.tick()
    expect(t.recovered).toHaveBeenCalledOnce()
    // A real next submission resumes normal status, without editing the rollout.
    expect(t.normalizer.ingest(record('user_message'))[0].type).toBe('turn_started')
    expect(t.normalizer.turnOpen).toBe(true)
  })
  it('never expires a quiet working turn based on elapsed time', async () => {
    const t = setup()
    t.capture.mockResolvedValue(screen.replace('Goal stalled (/goal resume)', 'Goal active'))
    await t.tick(0)
    await t.tick(86_400_000)
    await t.tick(86_400_000)
    expect(t.normalizer.turnOpen).toBe(true)
    expect(t.recovered).not.toHaveBeenCalled()
  })
  it('resets confirmation after an unavailable capture or failed read', async () => {
    const t = setup()
    await t.tick(0); await t.tick(30_000)
    t.capture.mockRejectedValueOnce(new Error('offline'))
    await t.tick(); await t.tick()
    expect(t.recovered).not.toHaveBeenCalled()
    t.capture.mockResolvedValueOnce(null)
    await t.tick(); await t.tick()
    expect(t.recovered).not.toHaveBeenCalled()
    await t.tick()
    expect(t.recovered).toHaveBeenCalledOnce()
  })
  it.each(['transcript', 'closed', 'replaced', 'terminal', 'removed', 'forgotten'])(
    'discards a delayed capture when the session is %s', async change => {
      const t = setup()
      await t.tick(0); await t.tick(30_000)
      let finish!: (screen: string) => void
      t.capture.mockImplementationOnce(() => new Promise(resolve => { finish = resolve }))
      const pending = t.tick()
      await Promise.resolve(); await Promise.resolve()
      if (change === 'transcript') t.normalizer.ingest(record('token_count'))
      if (change === 'closed') t.normalizer.closeTurn()
      if (change === 'replaced') t.replace({ normalizer: openNormalizer(), runtimeKey: 'agent:tmux:%31:pid:18662' })
      if (change === 'terminal') t.replace({ normalizer: t.normalizer, runtimeKey: 'other' })
      if (change === 'removed') t.replace()
      if (change === 'forgotten') t.recovery.forget('session')
      finish(screen)
      await pending
      expect(t.recovered).not.toHaveBeenCalled()
    },
  )
  it('drains a newly written completion before considering the footer', async () => {
    const t = setup()
    await t.tick(0)
    t.drain.mockImplementationOnce(async () => { t.normalizer.ingest(record('task_complete')) })
    await t.tick(30_000)
    expect(t.capture).not.toHaveBeenCalled()
    expect(t.recovered).not.toHaveBeenCalled()
  })
  it('does not run overlapping terminal captures', async () => {
    const t = setup()
    let finish!: (screen: string) => void
    t.capture.mockImplementationOnce(() => new Promise(resolve => { finish = resolve }))
    await t.tick(0)
    const pending = t.tick(30_000)
    await Promise.resolve(); await Promise.resolve()
    await t.tick(10_000)
    expect(t.capture).toHaveBeenCalledOnce()
    finish(screen); await pending
    expect(t.recovered).not.toHaveBeenCalled()
  })
})
