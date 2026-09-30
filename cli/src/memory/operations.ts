/** Internal worker contract. External transports must bind user/session authority before using it. */
import type { CodingMemoryStore } from './store.js'
import type { MemoryQueue } from './queue.js'

export type MemoryOperations = Pick<CodingMemoryStore,
  'controls' | 'setControls' | 'registerProject' | 'projectForLocator' | 'linkProjectLocator' | 'setProjectIncluded'
  | 'ingest' | 'source' | 'propose' | 'revise' | 'correctFromUser' | 'read' | 'history' | 'support' | 'list' | 'recall' | 'putTopic' | 'topic' | 'forget'>
  & Pick<MemoryQueue, 'capture' | 'checkpoint' | 'claim' | 'finish' | 'defer' | 'cursor' | 'status'>
export type Operation = keyof MemoryOperations
export type Arguments<K extends Operation> = Parameters<MemoryOperations[K]>
export type Result<K extends Operation> = ReturnType<MemoryOperations[K]>
export type MemoryPort = { request<K extends Operation>(operation: K, args: Arguments<K>, timeoutMs?: number): Promise<Result<K>> }

export const STORE_OPERATIONS = ['controls', 'setControls', 'registerProject', 'projectForLocator', 'linkProjectLocator', 'setProjectIncluded',
  'ingest', 'source', 'propose', 'revise', 'correctFromUser', 'read', 'history', 'support', 'list', 'recall', 'putTopic', 'topic', 'forget'] as const
export const QUEUE_OPERATIONS = ['capture', 'checkpoint', 'claim', 'finish', 'defer', 'cursor', 'status'] as const
