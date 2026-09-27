/**
 * Muse: placeholder until this engine's discovery is written. It finds nothing.
 */

import type { ExternalProvider } from './types.js'

export interface MuseOptions { home: string }

export function museProvider(options: MuseOptions): ExternalProvider {
  void options
  return { engine: 'muse', scan: async () => [] }
}
