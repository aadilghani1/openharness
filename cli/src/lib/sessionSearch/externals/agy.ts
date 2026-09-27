/**
 * Antigravity: placeholder until this engine's discovery is written. It finds nothing.
 */

import type { ExternalProvider } from './types.js'

export interface AgyOptions { home: string }

export function agyProvider(options: AgyOptions): ExternalProvider {
  void options
  return { engine: 'agy', scan: async () => [] }
}
