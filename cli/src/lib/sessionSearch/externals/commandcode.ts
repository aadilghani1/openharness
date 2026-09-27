/**
 * Command Code: placeholder until this engine's discovery is written. It finds nothing.
 */

import type { ExternalProvider } from './types.js'

export interface CommandcodeOptions { home: string }

export function commandcodeProvider(options: CommandcodeOptions): ExternalProvider {
  void options
  return { engine: 'commandcode', scan: async () => [] }
}
