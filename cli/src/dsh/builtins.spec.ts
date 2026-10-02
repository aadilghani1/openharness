import { afterEach, beforeEach, expect, it, vi } from 'vitest'
import { existsSync, mkdtempSync, readFileSync, rmSync, statSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { env } from '../config/env.js'
import { ensureBundledDevices, ensureBundledModelManager, DEVICES_HARNESS_ID, MODEL_MANAGER_ID } from './builtins.js'
import { dshListRows } from './wire.js'
import { installedDsh, invalidateInstalledDsh, upsertInstalledRecord } from './installed.js'
import { lockDsh } from './lock.js'

let root: string
let original: string
it('ships Devices as an unlisted DSH with the shared daemon commands and reusable workspace', () => {
  const files = Object.fromEntries(['harness.json', 'AGENTS.md', 'template/devices.json'].map(path => [path,
    { content: readFileSync(new URL(`../../../store/agents/devices/${path}`, import.meta.url), 'utf8'), executable: false }]))
  expect(ensureBundledDevices(files)).toBe(true)
  const installed = installedDsh(DEVICES_HARNESS_ID)!
  expect(installed.manifest.workspace?.marker).toBe('devices.json')
  expect(installed.manifest.agent?.env?.DSH_PERMISSION_MODE).toBe('ask')
  expect(dshListRows([installed], [])).toEqual([])
  expect(files['AGENTS.md']!.content).toContain('harness hardware list --json')
  expect(ensureBundledDevices(files)).toBe(true)
  expect(installedDsh(DEVICES_HARNESS_ID)?.dir).toBe(installed.dir)
})
beforeEach(() => {
  root = mkdtempSync(join(tmpdir(), 'model-manager-bundle-'))
  original = env.DSH_DIR
  env.DSH_DIR = root
  invalidateInstalledDsh()
})
afterEach(() => {
  vi.unstubAllGlobals()
  env.DSH_DIR = original
  invalidateInstalledDsh()
  rmSync(root, { recursive: true, force: true })
})

it('uses the embedded release bundle and returns unavailable in unbundled development', () => {
  expect(ensureBundledModelManager()).toBe(false)
  expect(ensureBundledModelManager({})).toBe(false)
  vi.stubGlobal('__MODEL_MANAGER_BUNDLE__', JSON.stringify(bundle()))
  expect(ensureBundledModelManager()).toBe(true)
  expect(installedDsh(MODEL_MANAGER_ID)?.manifest.name).toBe('Model Manager')
})

it('joins a later attempt after another installer releases the package lock', () => {
  const release = lockDsh(MODEL_MANAGER_ID)!
  expect(ensureBundledModelManager(bundle())).toBe(false)
  expect(installedDsh(MODEL_MANAGER_ID)).toBeUndefined()
  release()
  expect(ensureBundledModelManager(bundle())).toBe(true)
})

it('reuses an already materialized package when restoring an older bundled revision', () => {
  ensureBundledModelManager(bundle('one'))
  const first = installedDsh(MODEL_MANAGER_ID)!
  ensureBundledModelManager(bundle('two'))
  expect(ensureBundledModelManager(bundle('one'))).toBe(true)
  expect(installedDsh(MODEL_MANAGER_ID)?.dir).toBe(first.dir)
})

it.each(['not json', JSON.stringify({ spec: 1, id: 'other/package', name: 'Wrong', engine: 'codex' })])('rejects an invalid embedded manifest and releases its lock', content => {
  expect(() => ensureBundledModelManager({ ...bundle(), 'harness.json': { content, executable: false } })).toThrow('Invalid bundled Model Manager')
  expect(installedDsh(MODEL_MANAGER_ID)).toBeUndefined()
  expect(ensureBundledModelManager(bundle())).toBe(true)
})
const bundle = (instructions = 'Help with local models') => ({
  'harness.json': { content: JSON.stringify({ spec: 1, id: MODEL_MANAGER_ID, name: 'Model Manager', engine: 'codex' }), executable: false },
  'AGENTS.md': { content: instructions, executable: false },
  'toolchain/fleet': { content: '#!/bin/sh\nexit 0\n', executable: true },
})

it('installs offline, preserves executable files, and reuses the installed version', () => {
  expect(ensureBundledModelManager(bundle())).toBe(true)
  const first = installedDsh(MODEL_MANAGER_ID)!
  expect(first.manifest.name).toBe('Model Manager')
  expect(statSync(join(first.dir, 'toolchain/fleet')).mode & 0o777).toBe(0o700)
  expect(ensureBundledModelManager(bundle())).toBe(true)
  expect(installedDsh(MODEL_MANAGER_ID)?.dir).toBe(first.dir)
})

it('updates the bundled version without deleting resources a running manager uses', () => {
  ensureBundledModelManager(bundle('version one'))
  const first = installedDsh(MODEL_MANAGER_ID)!
  ensureBundledModelManager(bundle('version two'))
  const second = installedDsh(MODEL_MANAGER_ID)!
  expect(second.dir).not.toBe(first.dir)
  expect(readFileSync(join(second.dir, 'AGENTS.md'), 'utf8')).toBe('version two')
  expect(existsSync(join(first.dir, 'AGENTS.md'))).toBe(true)
})

it('keeps a developer linked package and refuses invalid bundled paths', () => {
  expect(() => ensureBundledModelManager({ ...bundle(), '../escape': { content: 'no', executable: false } })).toThrow('Invalid built-in package path')
  expect(installedDsh(MODEL_MANAGER_ID)).toBeUndefined()
  ensureBundledModelManager(bundle())
  const first = installedDsh(MODEL_MANAGER_ID)!
  upsertInstalledRecord({ ...first, linked: true, source: '/my/checkout' })
  expect(ensureBundledModelManager(bundle('release update'))).toBe(true)
  expect(installedDsh(MODEL_MANAGER_ID)?.source).toBe('/my/checkout')
  expect(readFileSync(join(first.dir, 'AGENTS.md'), 'utf8')).toBe('Help with local models')
})
