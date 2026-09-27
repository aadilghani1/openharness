/**
 * Grok: placeholder until this engine's discovery is written. It finds nothing.
 */

import type { ExternalProvider } from './types.js'

export interface GrokOptions { home: string }

export function grokProvider(options: GrokOptions): ExternalProvider {
  void options
  return { engine: 'grok', scan: async () => [] }
}
