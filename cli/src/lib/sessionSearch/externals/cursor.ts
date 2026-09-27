/**
 * Cursor: placeholder until this engine's discovery is written. It finds nothing.
 */

import type { ExternalProvider } from './types.js'

export interface CursorOptions { configDir: string; dataDir: string }

export function cursorProvider(options: CursorOptions): ExternalProvider {
  void options
  return { engine: 'cursor', scan: async () => [] }
}
