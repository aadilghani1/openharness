import { expect, it } from 'vitest'
import { MemorySessionRoster } from './hostSessions.js'

const session = { agentId: 'agent', engine: 'claude', sessionId: 'native', cwd: '/projects/code',
  transcriptPath: '/native/session.jsonl', registeredAt: 100 }
const no = () => false
it('admits coding processes and bundled coding DSHs while excluding other domains, subagents and home', () => {
  const roster = new MemorySessionRoster('/home/person')
  expect(roster.refresh([session], no, no)).toHaveLength(1)
  for (const change of [{ dsh: 'autonomous/roundtable' }, { dsh: 'autonomous/pair' }, { engine: 'terminal' },
    { cwd: '/home/person' }, { cwd: '/' }, { sessionId: '' }, { transcriptPath: null }]) {
    expect(roster.refresh([{ ...session, ...change }], no, no)).toEqual([])
  }
  expect(roster.refresh([{ ...session, dsh: 'autonomous/web-studio' }], no, no)).toHaveLength(1)
  expect(roster.refresh([session], no, () => true)).toEqual([])
})

it('retains a recently exited process long enough to capture its final native reply, without archive discovery', () => {
  let now = 1_000
  const roster = new MemorySessionRoster('/home/person', () => now)
  roster.refresh([session], () => true, no)
  now += 10_000
  expect(roster.refresh([], no, no)).toMatchObject([{ sessionId: 'native', busy: false }])
  now += 120_001
  expect(roster.refresh([], no, no)).toEqual([])
})

it('preserves the host-observed fork boundary and replaces a rotated session instead of reusing its binding', () => {
  const roster = new MemorySessionRoster('/home/person')
  expect(roster.refresh([{ ...session, forkedFrom: { agentId: 'parent' } }], no, no)[0].liveFrom).toBe(100)
  expect(roster.refresh([{ ...session, sessionId: 'new_native' }], no, no)).toMatchObject([{ sessionId: 'new_native' }])
  expect(roster.refresh([session], no, no)[0].liveFrom).toBeUndefined()
})

it('uses personal scope only for the current verified collection conversation, not an archived companion', () => {
  const roster = new MemorySessionRoster('/home/person')
  const companion = { ...session, dsh: 'autonomous/pair' }
  expect(roster.refresh([companion], no, no)).toEqual([])
  expect(roster.refresh([companion], no, no, 'agent')).toMatchObject([{ scope: 'profile' }])
  expect(roster.refresh([], no, no, 'another_agent')).toEqual([])
})
