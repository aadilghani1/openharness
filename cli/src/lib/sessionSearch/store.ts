/**
 * The session search index: one SQLite database per machine, one row per turn, searched with FTS5.
 *
 * Keyword search (BM25) rather than embeddings, on purpose. What people type into a quick-open box is
 * one to three words and very often an exact token — a codename, a file, an issue number, a branch —
 * which BM25 matches exactly and an embedding blurs. It needs no model, answers in milliseconds, and
 * updates a turn at a time. See docs/research/2026-09-26-session-search.md.
 *
 * Every query word must appear in the SESSION, not necessarily in one turn: "mobile swipe" finds the
 * session titled Mobile whose swipe discussion came an hour later. A turn holding every word is still
 * the better match and ranks first.
 */

import { chmodSync, existsSync } from 'node:fs'

import { builtinSqlite } from '../sqliteRead.js'
import type { IndexedTurn } from './turns.js'

const SCHEMA_VERSION = '1'

/** The row that holds a session's name, title and folder: searchable beside its turns. */
export const HEADER_TURN = -1

interface Statement {
  all(...params: unknown[]): Record<string, unknown>[]
  get(...params: unknown[]): Record<string, unknown> | undefined
  run(...params: unknown[]): unknown
}
interface Database {
  prepare(sql: string): Statement
  exec(sql: string): void
  close(): void
}
type DatabaseConstructor = new (path: string, options?: Record<string, unknown>) => Database

export interface IndexedSession {
  sessionId: string
  agentId: string
  engine: string
  path: string
  /** The session's name, title and folders, as the header row holds them. */
  header: string
  /** File size and mtime when last read, to tell whether it changed since. */
  size: number
  mtime: number
  /** Where the next pass starts: the opening of the last turn, which may still be growing. */
  resumeOffset: number
  resumeTurn: number
  lastAt: number | null
  turns: number
}

export interface SearchHit {
  sessionId: string
  agentId: string
  engine: string
  /** The turn the snippet comes from, or -1 for the session's name and folder. */
  turn: number
  /** When that turn happened (epoch ms), when known. */
  at: number | null
  /** The session's latest turn (epoch ms), when known. */
  lastAt: number | null
  /** Which part of the turn matched best. */
  field: 'name' | 'ask' | 'answer' | 'tools'
  /** Text around the match, with each matched word between `\u0002` and `\u0003`. */
  snippet: string
  /** Every word in one turn, or spread across the session. */
  together: boolean
  /** 0–1, higher is better: relevance blended with recency; comparable across machines. */
  score: number
}

// BM25 column weights: header (name/title/folder), what was asked, the answer, tool calls.
const WEIGHTS = [6, 4, 1.5, 1] as const
const FIELDS = ['name', 'ask', 'answer', 'tools'] as const
export const MARK_OPEN = '\u0002'
export const MARK_CLOSE = '\u0003'
/** How much recency counts against relevance, and how fast it fades. */
const RECENCY_WEIGHT = 0.3
const RECENCY_HALF_LIFE_DAYS = 10
/** Rows considered per query before grouping by session: bounds the work of a very common word. */
const CANDIDATE_ROWS = 3_000

/** Query words as FTS5 phrases. Each word matches as a prefix, so the list updates while typing. */
export function queryTerms(query: string): string[] {
  const words = query.toLowerCase().normalize('NFKC').split(/\s+/).filter(Boolean)
  const terms: string[] = []
  for (const word of words) {
    // The index splits on everything that is not a letter or digit, so "swarm_search.dart" and
    // "OH-14" become phrases of their parts, in order.
    const parts = word.split(/[^\p{L}\p{N}]+/u).filter(Boolean)
    if (!parts.length) continue
    // One letter matches too much of everything to mean anything on its own.
    if (parts.length === 1 && [...parts[0]].length < 2) continue
    terms.push(`"${parts.join(' ')}"*`)
  }
  return [...new Set(terms)]
}

export class SessionSearchStore {
  private readonly db: Database
  private readonly statements = new Map<string, Statement>()

  private constructor(db: Database) {
    this.db = db
  }

  /** The index at `path`, created if missing; null on a Node without `node:sqlite`. */
  static open(path: string): SessionSearchStore | null {
    const Constructor = builtinSqlite() as unknown as DatabaseConstructor | null
    if (!Constructor) return null
    const fresh = path !== ':memory:' && !existsSync(path)
    const db = new Constructor(path)
    if (path !== ':memory:') {
      db.exec('PRAGMA journal_mode = WAL')
      db.exec('PRAGMA synchronous = NORMAL')
    }
    db.exec('PRAGMA busy_timeout = 1000')
    const store = new SessionSearchStore(db)
    store.migrate()
    if (fresh) {
      // What people said to their agents: this user's eyes only, like the transcripts themselves.
      for (const suffix of ['', '-wal', '-shm']) {
        try { chmodSync(`${path}${suffix}`, 0o600) } catch { /* not created yet */ }
      }
    }
    return store
  }

  private migrate(): void {
    this.db.exec('CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)')
    const version = this.db.prepare("SELECT value FROM meta WHERE key = 'schema'").get()?.value
    if (version === SCHEMA_VERSION) return
    this.db.exec(`
      DROP TABLE IF EXISTS turns_fts;
      DROP TABLE IF EXISTS turns;
      DROP TABLE IF EXISTS sessions;
      CREATE TABLE sessions (
        session_id TEXT PRIMARY KEY,
        agent_id TEXT NOT NULL,
        engine TEXT NOT NULL,
        path TEXT NOT NULL,
        header TEXT NOT NULL,
        size INTEGER NOT NULL,
        mtime INTEGER NOT NULL,
        resume_offset INTEGER NOT NULL,
        resume_turn INTEGER NOT NULL,
        last_at INTEGER,
        turns INTEGER NOT NULL
      );
      CREATE TABLE turns (
        id INTEGER PRIMARY KEY,
        session_id TEXT NOT NULL,
        turn INTEGER NOT NULL,
        at INTEGER,
        name TEXT NOT NULL DEFAULT '',
        ask TEXT NOT NULL DEFAULT '',
        answer TEXT NOT NULL DEFAULT '',
        tools TEXT NOT NULL DEFAULT ''
      );
      CREATE UNIQUE INDEX turns_by_session ON turns (session_id, turn);
      CREATE VIRTUAL TABLE turns_fts USING fts5 (
        name, ask, answer, tools,
        content = 'turns', content_rowid = 'id',
        tokenize = 'unicode61 remove_diacritics 2',
        prefix = '2 3 4'
      );
      CREATE TRIGGER turns_insert AFTER INSERT ON turns BEGIN
        INSERT INTO turns_fts (rowid, name, ask, answer, tools)
        VALUES (new.id, new.name, new.ask, new.answer, new.tools);
      END;
      CREATE TRIGGER turns_delete AFTER DELETE ON turns BEGIN
        INSERT INTO turns_fts (turns_fts, rowid, name, ask, answer, tools)
        VALUES ('delete', old.id, old.name, old.ask, old.answer, old.tools);
      END;
    `)
    this.db.prepare("INSERT OR REPLACE INTO meta (key, value) VALUES ('schema', ?)").run(SCHEMA_VERSION)
  }

  private statement(sql: string): Statement {
    let statement = this.statements.get(sql)
    if (!statement) {
      statement = this.db.prepare(sql)
      this.statements.set(sql, statement)
    }
    return statement
  }

  private transaction<T>(work: () => T): T {
    this.db.exec('BEGIN IMMEDIATE')
    try {
      const result = work()
      this.db.exec('COMMIT')
      return result
    } catch (error) {
      this.db.exec('ROLLBACK')
      throw error
    }
  }

  session(sessionId: string): IndexedSession | undefined {
    const row = this.statement('SELECT * FROM sessions WHERE session_id = ?').get(sessionId)
    return row ? toSession(row) : undefined
  }

  sessionIds(): string[] {
    return this.statement('SELECT session_id FROM sessions').all().map((row) => row.session_id as string)
  }

  /**
   * Replaces the session's turns from `fromTurn` on with `turns` and records where the next pass
   * starts, in one transaction: a reader never sees a half-written session.
   */
  writeSession(session: IndexedSession, fromTurn: number, turns: readonly IndexedTurn[]): void {
    this.transaction(() => {
      this.statement('DELETE FROM turns WHERE session_id = ? AND (turn >= ? OR turn = ?)').run(session.sessionId, fromTurn, HEADER_TURN)
      const insert = this.statement('INSERT INTO turns (session_id, turn, at, name, ask, answer, tools) VALUES (?, ?, ?, ?, ?, ?, ?)')
      insert.run(session.sessionId, HEADER_TURN, session.lastAt, session.header, '', '', '')
      for (const turn of turns) insert.run(session.sessionId, turn.turn, turn.at, '', turn.ask, turn.answer, turn.tools)
      const count = this.statement('SELECT count(*) AS n FROM turns WHERE session_id = ? AND turn >= 0').get(session.sessionId)?.n as number
      this.statement(`INSERT OR REPLACE INTO sessions
        (session_id, agent_id, engine, path, header, size, mtime, resume_offset, resume_turn, last_at, turns)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`).run(
        session.sessionId, session.agentId, session.engine, session.path, session.header, session.size,
        session.mtime, session.resumeOffset, session.resumeTurn, session.lastAt, count,
      )
    })
  }

  removeSession(sessionId: string): void {
    this.transaction(() => {
      this.statement('DELETE FROM turns WHERE session_id = ?').run(sessionId)
      this.statement('DELETE FROM sessions WHERE session_id = ?').run(sessionId)
    })
  }

  counts(): { sessions: number; turns: number } {
    const sessions = this.statement('SELECT count(*) AS n FROM sessions').get()?.n as number
    const turns = this.statement('SELECT count(*) AS n FROM turns WHERE turn >= 0').get()?.n as number
    return { sessions, turns }
  }

  /** The best sessions for `query`, best first. `now` is for tests. */
  search(query: string, options: { limit?: number; now?: number } = {}): SearchHit[] {
    const terms = queryTerms(query)
    if (!terms.length) return []
    const limit = Math.max(1, Math.min(options.limit ?? 30, 100))
    const now = options.now ?? Date.now()

    // 1. Sessions with one turn holding every word.
    const best = new Map<string, { id: number; turn: number; at: number | null; rank: number; together: boolean }>()
    const rows = this.statement(`
      SELECT t.id AS id, t.session_id AS sid, t.turn AS turn, t.at AS at,
             bm25(turns_fts, ${WEIGHTS.join(', ')}) AS rank
      FROM turns_fts JOIN turns t ON t.id = turns_fts.rowid
      WHERE turns_fts MATCH ? ORDER BY rank LIMIT ${CANDIDATE_ROWS}`).all(terms.join(' AND '))
    for (const row of rows) {
      const sid = row.sid as string
      if (!best.has(sid)) best.set(sid, { id: row.id as number, turn: row.turn as number, at: row.at as number | null, rank: row.rank as number, together: true })
    }

    // 2. Sessions holding every word, but in different turns. Each word's sessions, intersected.
    if (terms.length > 1 && best.size < limit) {
      const perTerm = terms.map((term) => new Set(this.statement(`
        SELECT DISTINCT t.session_id AS sid FROM turns_fts JOIN turns t ON t.id = turns_fts.rowid
        WHERE turns_fts MATCH ?`).all(term).map((row) => row.sid as string)))
      let rarestIndex = 0
      for (let index = 1; index < perTerm.length; index++) {
        if (perTerm[index].size < perTerm[rarestIndex].size) rarestIndex = index
      }
      const rarest = terms[rarestIndex]
      const spread = [...perTerm[rarestIndex]].filter((sid) => !best.has(sid) && perTerm.every((set) => set.has(sid)))
      // Each such session's best turn for the words: its rank, discounted for being spread, and its
      // snippet — from what was said rather than the name, which the row already shows.
      const anyTerm = terms.join(' OR ')
      const bestTurn = this.statement(`
        SELECT t.id AS id, t.turn AS turn, t.at AS at, bm25(turns_fts, ${WEIGHTS.join(', ')}) AS rank
        FROM turns_fts JOIN turns t ON t.id = turns_fts.rowid
        WHERE turns_fts MATCH ? AND t.session_id = ? AND t.turn >= CAST(? AS INTEGER) ORDER BY rank LIMIT 1`)
      for (const sid of spread) {
        const row = bestTurn.get(anyTerm, sid, 0) ?? bestTurn.get(rarest, sid, HEADER_TURN)
        if (row) best.set(sid, { id: row.id as number, turn: row.turn as number, at: row.at as number | null, rank: (row.rank as number) / 2, together: false })
      }
    }
    if (!best.size) return []

    // 3. Relevance (bm25 is negative; lower is better) relative to the best match, blended with how
    // recently the session was worked on — "the one from last week" usually means the recent one.
    const sessions = new Map<string, IndexedSession>()
    for (const sid of best.keys()) {
      const session = this.session(sid)
      if (session) sessions.set(sid, session)
    }
    const top = Math.min(...[...best.values()].map((match) => match.rank))
    const ranked = [...best.entries()]
      .filter(([sid]) => sessions.has(sid))
      .map(([sid, match]) => {
        const session = sessions.get(sid)!
        const relevance = top < 0 ? match.rank / top : 1
        const lastAt = session.lastAt ?? match.at
        const ageDays = lastAt ? Math.max(0, now - lastAt) / 86_400_000 : 365
        const recency = Math.pow(0.5, ageDays / RECENCY_HALF_LIFE_DAYS)
        const score = (1 - RECENCY_WEIGHT) * relevance + RECENCY_WEIGHT * recency
        return { sid, match, session, score }
      })
      .sort((a, b) => Number(b.match.together) - Number(a.match.together) || b.score - a.score)
      .slice(0, limit)

    // 4. Snippets for the hits only: which field matched, and the words around it. node:sqlite binds a
    // JS number as REAL, and FTS5 quietly ignores a REAL rowid constraint beside MATCH — every row
    // came back — hence the CAST.
    const snippetQuery = terms.join(' OR ')
    return ranked.map(({ sid, match, session, score }) => {
      const row = this.statement(`
        SELECT ${FIELDS.map((_, column) => `snippet(turns_fts, ${column}, '${MARK_OPEN}', '${MARK_CLOSE}', '…', 12) AS s${column}`).join(', ')}
        FROM turns_fts WHERE turns_fts MATCH ? AND rowid = CAST(? AS INTEGER)`).get(snippetQuery, match.id)
      // What the person asked says the most about a session, then its name, then the answer.
      const order = [1, 0, 2, 3]
      const column = order.find((index) => String(row?.[`s${index}`] ?? '').includes(MARK_OPEN)) ?? 1
      return {
        sessionId: sid,
        agentId: session.agentId,
        engine: session.engine,
        turn: match.turn,
        at: match.at,
        lastAt: session.lastAt,
        field: FIELDS[column],
        snippet: String(row?.[`s${column}`] ?? ''),
        together: match.together,
        score: Math.round(score * 1000) / 1000,
      }
    })
  }

  close(): void {
    this.statements.clear()
    this.db.close()
  }
}

function toSession(row: Record<string, unknown>): IndexedSession {
  return {
    sessionId: row.session_id as string,
    agentId: row.agent_id as string,
    engine: row.engine as string,
    path: row.path as string,
    header: row.header as string,
    size: row.size as number,
    mtime: row.mtime as number,
    resumeOffset: row.resume_offset as number,
    resumeTurn: row.resume_turn as number,
    lastAt: (row.last_at as number | null) ?? null,
    turns: row.turns as number,
  }
}
