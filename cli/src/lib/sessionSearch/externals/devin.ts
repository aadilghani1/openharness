/**
 * Devin: placeholder until this engine's discovery is written. It finds nothing.
 */

import type { ExternalProvider } from './types.js'

export interface DevinOptions { home: string }

export function devinProvider(options: DevinOptions): ExternalProvider {
  void options
  return { engine: 'devin', scan: async () => [] }
}
