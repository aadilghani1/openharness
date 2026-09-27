/**
 * Hermes: placeholder until this engine's discovery is written. It finds nothing.
 */

import type { ExternalProvider } from './types.js'

export interface HermesOptions { root: string }

export function hermesProvider(options: HermesOptions): ExternalProvider {
  void options
  return { engine: 'hermes', scan: async () => [] }
}
