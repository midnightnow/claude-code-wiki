/**
 * =============================================================================
 * SESSION MANAGER
 * =============================================================================
 *
 * Manages development sessions for the self-improving journal system.
 * Sessions group related work with clear goals and capture AI reasoning trails.
 */

import Database from 'better-sqlite3';
import { existsSync } from 'fs';
import { homedir } from 'os';
import { join } from 'path';
import Reflector from './reflector.js';

export interface DevSession {
  id: number;
  project_id: number;
  start_time: string;
  end_time?: string;
  goal: string;
  status: 'IN_PROGRESS' | 'COMPLETED' | 'ABANDONED';
  outcome_summary?: string;
  reflection_status: 'PENDING' | 'ANALYZED' | 'SKIPPED';
  winning_strategy?: string;
  time_to_fix_ms?: number;
  hypothesis_count?: number;
  successful_hypothesis_id?: number;
}

export interface JournalEntry {
  id?: number;
  project_id: number;
  session_id?: number;
  parent_id?: number;
  entry_type: JournalEntryType;
  timestamp?: string;
  summary: string;
  details?: string; // JSON blob
  git_commit_hash?: string;
  analysis_outcome?: 'SUCCESS' | 'FAILURE' | 'NEUTRAL';
  approach_tags?: string; // JSON array
}

export type JournalEntryType =
  | 'SESSION_START'
  | 'SESSION_END'
  | 'TEST_RUN'
  | 'ERROR_LOG'
  | 'FILE_CHANGE'
  | 'AI_TASK'
  | 'AI_HYPOTHESIS'
  | 'AI_TOOL_CALL'
  | 'AI_OBSERVATION'
  | 'NOTE'
  | 'COMMAND_RUN'
  | 'BUILD_EVENT';

export interface TestRun {
  id?: number;
  journal_entry_id: number;
  status: 'PASSED' | 'FAILED' | 'ERROR';
  duration_ms?: number;
  total_tests?: number;
  passed_tests?: number;
  failed_tests?: number;
  skipped_tests?: number;
  source_file?: string;
}

export interface TestResult {
  id?: number;
  test_run_id: number;
  test_name: string;
  test_file?: string;
  status: 'PASSED' | 'FAILED' | 'SKIPPED' | 'ERROR';
  duration_ms?: number;
  error_message?: string;
  error_signature?: string;
  stdout?: string;
  stderr?: string;
}

export class SessionManager {
  private db: Database.Database;
  private reflector: Reflector;
  private currentSessionId: number | null = null;

  constructor(db?: Database.Database) {
    if (db) {
      this.db = db;
    } else {
      const dataDir = process.env.XDG_DATA_HOME
        ? join(process.env.XDG_DATA_HOME, 'claude-wiki')
        : join(homedir(), '.local', 'share', 'claude-wiki');
      const dbPath = join(dataDir, 'wiki.db');

      if (!existsSync(dbPath)) {
        throw new Error(`Wiki database not found at ${dbPath}. Run 'wiki scan' first.`);
      }

      this.db = new Database(dbPath);
    }

    this.reflector = new Reflector(this.db);
  }

  // ===========================================================================
  // SESSION LIFECYCLE
  // ===========================================================================

  /**
   * Start a new development session
   */
  startSession(projectId: number, goal: string): DevSession {
    const stmt = this.db.prepare(`
      INSERT INTO dev_sessions (project_id, goal, status, reflection_status)
      VALUES (?, ?, 'IN_PROGRESS', 'PENDING')
    `);

    const result = stmt.run(projectId, goal);
    this.currentSessionId = result.lastInsertRowid as number;

    // Log session start
    this.addJournalEntry({
      project_id: projectId,
      session_id: this.currentSessionId,
      entry_type: 'SESSION_START',
      summary: `Started session: ${goal}`,
      details: JSON.stringify({ goal }),
    });

    return this.getSession(this.currentSessionId)!;
  }

  /**
   * End the current session
   * @param fixEntryId - Optional explicit tag of the journal entry that fixed the issue (improves learning accuracy)
   */
  endSession(
    sessionId: number,
    outcome: 'COMPLETED' | 'ABANDONED',
    summary?: string,
    fixEntryId?: number
  ): DevSession {
    const session = this.getSession(sessionId);
    if (!session) {
      throw new Error(`Session ${sessionId} not found`);
    }

    // Update session with explicit fix if provided
    if (fixEntryId) {
      this.db.prepare(`
        UPDATE dev_sessions
        SET end_time = STRFTIME('%Y-%m-%d %H:%M:%f', 'NOW'),
            status = ?,
            outcome_summary = ?,
            successful_hypothesis_id = ?
        WHERE id = ?
      `).run(outcome, summary || null, fixEntryId, sessionId);
    } else {
      this.db.prepare(`
        UPDATE dev_sessions
        SET end_time = STRFTIME('%Y-%m-%d %H:%M:%f', 'NOW'),
            status = ?,
            outcome_summary = ?
        WHERE id = ?
      `).run(outcome, summary || null, sessionId);
    }

    // Log session end
    this.addJournalEntry({
      project_id: session.project_id,
      session_id: sessionId,
      entry_type: 'SESSION_END',
      summary: `Session ${outcome.toLowerCase()}: ${summary || 'No summary'}`,
      details: JSON.stringify({ outcome, summary, fixEntryId }),
    });

    // Trigger reflection if completed
    if (outcome === 'COMPLETED') {
      console.log(`[SessionManager] Triggering reflection for session ${sessionId}...`);
      this.reflector.reflectOnSession(sessionId, fixEntryId);
    }

    if (this.currentSessionId === sessionId) {
      this.currentSessionId = null;
    }

    return this.getSession(sessionId)!;
  }

  /**
   * Get a session by ID
   */
  getSession(sessionId: number): DevSession | undefined {
    return this.db.prepare('SELECT * FROM dev_sessions WHERE id = ?').get(sessionId) as DevSession | undefined;
  }

  /**
   * Get the current active session for a project
   */
  getActiveSession(projectId: number): DevSession | undefined {
    return this.db.prepare(`
      SELECT * FROM dev_sessions
      WHERE project_id = ? AND status = 'IN_PROGRESS'
      ORDER BY start_time DESC
      LIMIT 1
    `).get(projectId) as DevSession | undefined;
  }

  /**
   * Get recent sessions
   */
  getRecentSessions(limit = 20): (DevSession & { project_name: string })[] {
    return this.db.prepare(`
      SELECT s.*, p.name as project_name
      FROM dev_sessions s
      JOIN projects p ON s.project_id = p.id
      ORDER BY s.start_time DESC
      LIMIT ?
    `).all(limit) as (DevSession & { project_name: string })[];
  }

  // ===========================================================================
  // JOURNAL ENTRIES
  // ===========================================================================

  /**
   * Add a journal entry
   */
  addJournalEntry(entry: JournalEntry): number {
    const stmt = this.db.prepare(`
      INSERT INTO dev_journal (
        project_id, session_id, parent_id, entry_type,
        summary, details, git_commit_hash, analysis_outcome, approach_tags
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    `);

    const result = stmt.run(
      entry.project_id,
      entry.session_id || null,
      entry.parent_id || null,
      entry.entry_type,
      entry.summary,
      entry.details || null,
      entry.git_commit_hash || null,
      entry.analysis_outcome || null,
      entry.approach_tags || null
    );

    return result.lastInsertRowid as number;
  }

  /**
   * Log an AI hypothesis with parent reference
   */
  logHypothesis(
    projectId: number,
    sessionId: number,
    parentId: number | undefined,
    hypothesis: string,
    approachTags: string[]
  ): number {
    return this.addJournalEntry({
      project_id: projectId,
      session_id: sessionId,
      parent_id: parentId,
      entry_type: 'AI_HYPOTHESIS',
      summary: hypothesis,
      approach_tags: JSON.stringify(approachTags),
    });
  }

  /**
   * Log an AI tool call
   */
  logToolCall(
    projectId: number,
    sessionId: number,
    parentId: number,
    tool: string,
    args: object,
    result?: string
  ): number {
    return this.addJournalEntry({
      project_id: projectId,
      session_id: sessionId,
      parent_id: parentId,
      entry_type: 'AI_TOOL_CALL',
      summary: `Tool: ${tool}`,
      details: JSON.stringify({ tool, args, result }),
    });
  }

  /**
   * Log an observation/result
   */
  logObservation(
    projectId: number,
    sessionId: number,
    parentId: number,
    observation: string,
    outcome?: 'SUCCESS' | 'FAILURE' | 'NEUTRAL'
  ): number {
    return this.addJournalEntry({
      project_id: projectId,
      session_id: sessionId,
      parent_id: parentId,
      entry_type: 'AI_OBSERVATION',
      summary: observation,
      analysis_outcome: outcome,
    });
  }

  /**
   * Get journal entries for a session
   */
  getSessionJournal(sessionId: number): JournalEntry[] {
    return this.db.prepare(`
      SELECT * FROM dev_journal
      WHERE session_id = ?
      ORDER BY timestamp ASC
    `).all(sessionId) as JournalEntry[];
  }

  /**
   * Get recent journal entries across all projects
   */
  getRecentJournal(limit = 50): (JournalEntry & { project_name: string })[] {
    return this.db.prepare(`
      SELECT j.*, p.name as project_name
      FROM dev_journal j
      JOIN projects p ON j.project_id = p.id
      ORDER BY j.timestamp DESC
      LIMIT ?
    `).all(limit) as (JournalEntry & { project_name: string })[];
  }

  // ===========================================================================
  // TEST TRACKING
  // ===========================================================================

  /**
   * Record a test run
   */
  recordTestRun(
    projectId: number,
    sessionId: number | undefined,
    run: Omit<TestRun, 'id' | 'journal_entry_id'>
  ): number {
    // Create journal entry first
    const entryId = this.addJournalEntry({
      project_id: projectId,
      session_id: sessionId,
      entry_type: 'TEST_RUN',
      summary: `Test run: ${run.status} (${run.passed_tests || 0}/${run.total_tests || 0} passed)`,
      details: JSON.stringify(run),
      analysis_outcome: run.status === 'PASSED' ? 'SUCCESS' : 'FAILURE',
    });

    // Create test run record
    const stmt = this.db.prepare(`
      INSERT INTO test_runs (
        journal_entry_id, status, duration_ms,
        total_tests, passed_tests, failed_tests, skipped_tests, source_file
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    `);

    const result = stmt.run(
      entryId,
      run.status,
      run.duration_ms || null,
      run.total_tests || null,
      run.passed_tests || null,
      run.failed_tests || null,
      run.skipped_tests || null,
      run.source_file || null
    );

    return result.lastInsertRowid as number;
  }

  /**
   * Record individual test results
   */
  recordTestResults(testRunId: number, results: Omit<TestResult, 'id' | 'test_run_id'>[]): void {
    const stmt = this.db.prepare(`
      INSERT INTO test_results (
        test_run_id, test_name, test_file, status,
        duration_ms, error_message, error_signature, stdout, stderr
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    `);

    for (const result of results) {
      stmt.run(
        testRunId,
        result.test_name,
        result.test_file || null,
        result.status,
        result.duration_ms || null,
        result.error_message || null,
        result.error_signature || null,
        result.stdout || null,
        result.stderr || null
      );
    }
  }

  /**
   * Get flaky tests from the view
   */
  getFlakyTests(limit = 20): {
    test_name: string;
    test_file: string;
    total_runs: number;
    passes: number;
    failures: number;
    flakiness_pct: number;
    last_run: string;
  }[] {
    return this.db.prepare(`
      SELECT * FROM flaky_tests LIMIT ?
    `).all(limit) as any[];
  }

  // ===========================================================================
  // PLAYBOOKS & PATTERNS
  // ===========================================================================

  /**
   * Find relevant playbooks for an error
   */
  findPlaybooks(errorSignature: string, limit = 5): {
    id: number;
    title: string;
    confidence_score: number;
    solution_steps: string;
  }[] {
    // First try exact match
    const exact = this.db.prepare(`
      SELECT id, title, confidence_score, solution_steps
      FROM troubleshooting_playbooks
      WHERE error_signature = ? AND status = 'ACTIVE'
      ORDER BY confidence_score DESC
      LIMIT ?
    `).all(errorSignature, limit) as any[];

    if (exact.length > 0) {
      return exact;
    }

    // Fall back to pattern matching via universal_patterns
    return this.db.prepare(`
      SELECT tp.id, tp.title, tp.confidence_score, tp.solution_steps
      FROM troubleshooting_playbooks tp
      JOIN universal_patterns up ON up.best_strategy IS NOT NULL
      WHERE up.signature LIKE ? AND tp.status = 'ACTIVE'
      ORDER BY tp.confidence_score DESC
      LIMIT ?
    `).all(`%${errorSignature.substring(0, 50)}%`, limit) as any[];
  }

  /**
   * Record playbook usage
   */
  recordPlaybookUsage(playbookId: number, sessionId: number | undefined, wasHelpful: boolean, feedback?: string): void {
    this.db.prepare(`
      INSERT INTO playbook_usage_log (playbook_id, session_id, was_helpful, feedback)
      VALUES (?, ?, ?, ?)
    `).run(playbookId, sessionId || null, wasHelpful ? 1 : 0, feedback || null);

    // Evolve playbook confidence
    this.reflector.evolvePlaybook(playbookId, wasHelpful, sessionId);
  }

  // ===========================================================================
  // STATS & INSIGHTS
  // ===========================================================================

  /**
   * Get journal statistics
   */
  getJournalStats(): {
    totalSessions: number;
    completedSessions: number;
    totalJournalEntries: number;
    totalTestRuns: number;
    passRate: number;
    topStrategies: { strategy: string; success_rate: number }[];
  } {
    const basic = this.db.prepare(`
      SELECT
        (SELECT COUNT(*) FROM dev_sessions) as totalSessions,
        (SELECT COUNT(*) FROM dev_sessions WHERE status = 'COMPLETED') as completedSessions,
        (SELECT COUNT(*) FROM dev_journal) as totalJournalEntries,
        (SELECT COUNT(*) FROM test_runs) as totalTestRuns,
        (SELECT ROUND(100.0 * COUNT(*) FILTER (WHERE status = 'PASSED') / NULLIF(COUNT(*), 0), 1)
         FROM test_runs) as passRate
    `).get() as any;

    const strategies = this.db.prepare(`
      SELECT * FROM top_strategies LIMIT 5
    `).all() as any[];

    return {
      ...basic,
      topStrategies: strategies.map((s: any) => ({
        strategy: s.strategy,
        success_rate: s.success_rate,
      })),
    };
  }

  /**
   * Get AI performance metrics
   */
  getAIPerformance(): {
    avgHypothesesPerSession: number;
    firstHypothesisSuccessRate: number;
    avgTimeToFix: number;
    topWinningApproaches: { approach: string; wins: number }[];
  } {
    const stats = this.db.prepare(`
      SELECT
        AVG(hypothesis_count) as avgHypotheses,
        ROUND(100.0 * SUM(CASE WHEN successful_hypothesis_index = 1 THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 1) as firstSuccessRate,
        AVG(time_to_fix_ms) as avgTimeToFix
      FROM ai_performance_log
      WHERE outcome = 'FIXED'
    `).get() as any;

    const approaches = this.db.prepare(`
      SELECT winning_approach_tag as approach, COUNT(*) as wins
      FROM ai_performance_log
      WHERE outcome = 'FIXED' AND winning_approach_tag IS NOT NULL
      GROUP BY winning_approach_tag
      ORDER BY wins DESC
      LIMIT 5
    `).all() as any[];

    return {
      avgHypothesesPerSession: stats?.avgHypotheses || 0,
      firstHypothesisSuccessRate: stats?.firstSuccessRate || 0,
      avgTimeToFix: stats?.avgTimeToFix || 0,
      topWinningApproaches: approaches,
    };
  }

  /**
   * Close the database connection
   */
  close(): void {
    this.db.close();
  }
}

export default SessionManager;
