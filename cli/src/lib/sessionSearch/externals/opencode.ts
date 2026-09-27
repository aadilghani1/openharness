/**
 * OpenCode and Kilo: placeholder until this engine's discovery is written. It finds nothing.
 */

import type { ExternalProvider } from './types.js'

export interface OpencodeOptions { engine: 'opencode' | 'kilo'; dbPath: string }

export function opencodeProvider(options: OpencodeOptions): ExternalProvider {
  void options
  return { engine: options.engine, scan: async () => [] }
}
