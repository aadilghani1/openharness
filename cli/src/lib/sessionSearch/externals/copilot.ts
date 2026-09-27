/**
 * Copilot: placeholder until this engine's discovery is written. It finds nothing.
 */

import type { ExternalProvider } from './types.js'

export interface CopilotOptions { home: string }

export function copilotProvider(options: CopilotOptions): ExternalProvider {
  void options
  return { engine: 'copilot', scan: async () => [] }
}
