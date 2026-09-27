/**
 * Pi: placeholder until this engine's discovery is written. It finds nothing.
 */

import type { ExternalProvider } from './types.js'

export interface PiOptions { agentDir: string }

export function piProvider(options: PiOptions): ExternalProvider {
  void options
  return { engine: 'pi', scan: async () => [] }
}
