/**
 * =============================================================================
 * THE REFLECTOR - Self-Improving Intelligence Engine
 * =============================================================================
 *
 * The Reflector is the "prefrontal cortex" of the wiki system. It analyzes
 * completed debugging sessions to:
 *
 * 1. Identify winning vs losing hypotheses
 * 2. Extract and tag successful debugging strategies
 * 3. Update universal patterns for cross-project learning
 * 4. Evolve playbook confidence scores
 * 5. Build developer preference models
 *
 * The result: Every debugging session makes ALL future sessions smarter.
 */

import Database from 'better-sqlite3';
import { generateErrorSignature } from './error-utils.js';

// =============================================================================
// TYPE DEFINITIONS
// =============================================================================

interface JournalEntry {
  id: number;
  project_id: number;
  session_id: number | null;
  parent_id: number | null;
  entry_type: string;
  timestamp: string;
  summary: string;
  details: string | null;
  git_commit_hash: string | null;
  analysis_outcome: string | null;
  approach_tags: string | null;
}

interface DevSession {
  id: number;
  project_id: number;
  start_time: string;
  end_time: string | null;
  goal: string;
  status: string;
  outcome_summary: string | null;
  reflection_status: string;
}

interface SessionAnalysis {
  sessionId: number;
  success: boolean;
  errorSignature?: string;
  winningHypothesis?: JournalEntry;
  losingHypotheses: JournalEntry[];
  winningStrategy?: string;
  allStrategiesTried: string[];
  timeToFixMs: number;
  hypothesisCount: number;
}

interface PatternUpdate {
  signature: string;
  strategy: string;
  wasSuccess: boolean;
  projectId: number;
  timeToFixMs: number;
}

// =============================================================================
// STRATEGY TAGGING
// =============================================================================

/**
 * Extracts structured strategy tags from free-form hypothesis text.
 * These tags enable statistical analysis across sessions.
 */
const STRATEGY_PATTERNS: [RegExp, string][] = [
  [/mock|reset|spy|jest\.clear|afterEach/i, 'mock-lifecycle-fix'],
  [/cache|stale|redis|invalidat/i, 'cache-invalidation'],
  [/null|undefined|missing|default|optional/i, 'defensive-coding'],
  [/wait|timeout|async|await|promise|race/i, 'concurrency-fix'],
  [/permission|auth|role|access|deny|allow|rule/i, 'auth-policy-fix'],
  [/import|require|module|export|path/i, 'import-resolution'],
  [/type|interface|typescript|cast|as\s/i, 'type-fix'],
  [/config|env|environment|setting|\.env/i, 'config-fix'],
  [/dependency|package|version|upgrade|npm|yarn/i, 'dependency-fix'],
  [/network|http|fetch|api|endpoint|cors/i, 'network-fix'],
  [/database|query|sql|orm|migration/i, 'database-fix'],
  [/memory|leak|gc|heap/i, 'memory-fix'],
  [/state|redux|context|store/i, 'state-management-fix'],
  [/render|component|react|vue|dom/i, 'ui-render-fix'],
];

function extractStrategyTags(text: string): string[] {
  const tags: string[] = [];
  for (const [pattern, tag] of STRATEGY_PATTERNS) {
    if (pattern.test(text)) {
      tags.push(tag);
    }
  }
  return tags.length > 0 ? tags : ['general-logic-fix'];
}

// =============================================================================
// THE REFLECTOR CLASS
// =============================================================================

export class Reflector {
  private db: Database.Database;

  constructor(db: Database.Database) {
    this.db = db;
  }

  // ===========================================================================
  // MAIN ENTRY POINTS
  // ===========================================================================

  /**
   * Primary entry point: Analyze a completed session and learn from it.
   * Called automatically when `wiki session end` runs.
   */
  public async reflectOnSession(sessionId: number): Promise<void> {
    console.log(`\n🧠 Reflector: Analyzing session ${sessionId}...`);

    const session = this.getSession(sessionId);
    if (!session) {
      console.log(`   Session ${sessionId} not found.`);
      return;
    }

    if (session.reflection_status === 'ANALYZED') {
      console.log(`   Session ${sessionId} already analyzed.`);
      return;
    }

    const analysis = this.analyzeSession(sessionId);

    // Log analysis results
    console.log(`   Success: ${analysis.success}`);
    console.log(`   Hypotheses tried: ${analysis.hypothesisCount}`);
    console.log(`   Strategies tried: ${analysis.allStrategiesTried.join(', ') || 'none'}`);

    if (analysis.success && analysis.winningStrategy) {
      console.log(`   ✅ Winning strategy: ${analysis.winningStrategy}`);

      // Update knowledge stores
      if (analysis.errorSignature) {
        this.reinforcePattern({
          signature: analysis.errorSignature,
          strategy: analysis.winningStrategy,
          wasSuccess: true,
          projectId: session.project_id,
          timeToFixMs: analysis.timeToFixMs,
        });
      }

      // Tag winning/losing hypotheses
      this.tagHypotheses(analysis);

      // Log AI performance
      this.logAIPerformance(analysis, session);
    }

    // Mark session as analyzed
    this.markSessionAnalyzed(sessionId, analysis);

    // Check if we should create/update a playbook
    if (analysis.success && analysis.errorSignature) {
      await this.considerPlaybookUpdate(analysis, session);
    }

    console.log(`   Reflection complete.\n`);
  }

  /**
   * Reflect on all sessions that haven't been analyzed yet
   */
  public reflectOnPendingSessions(): void {
    console.log('\n🧠 Reflector: Processing pending sessions...');

    const pendingSessions = this.db.prepare(`
      SELECT id FROM dev_sessions
      WHERE status = 'COMPLETED' AND reflection_status = 'PENDING'
      ORDER BY end_time ASC
    `).all() as { id: number }[];

    console.log(`   Found ${pendingSessions.length} pending session(s)`);

    for (const session of pendingSessions) {
      this.reflectOnSession(session.id);
    }

    console.log('   All pending sessions processed.\n');
  }

  /**
   * Nightly maintenance: decay stale patterns, archive low-confidence playbooks
   */
  public runMaintenanceCycle(): void {
    console.log('\n🧠 Reflector: Running maintenance cycle...');

    // First reflect on any pending sessions
    this.reflectOnPendingSessions();

    this.decayStalePlaybooks();
    this.archiveLowConfidencePlaybooks();
    this.updatePatternStats();

    console.log('   Maintenance complete.\n');
  }

  // ===========================================================================
  // SESSION ANALYSIS
  // ===========================================================================

  private getSession(sessionId: number): DevSession | null {
    return this.db.prepare(
      'SELECT * FROM dev_sessions WHERE id = ?'
    ).get(sessionId) as DevSession | null;
  }

  private analyzeSession(sessionId: number): SessionAnalysis {
    const entries = this.db.prepare(
      'SELECT * FROM dev_journal WHERE session_id = ? ORDER BY timestamp ASC'
    ).all(sessionId) as JournalEntry[];

    // Find all hypotheses
    const hypotheses = entries.filter(e => e.entry_type === 'AI_HYPOTHESIS');

    // Find all test runs
    const testRuns = entries.filter(e => e.entry_type === 'TEST_RUN');

    // Find the final successful test run (if any)
    const successfulRun = testRuns.reverse().find(t => {
      try {
        const details = JSON.parse(t.details || '{}');
        return details.status === 'PASSED' || details.failed === 0;
      } catch {
        return false;
      }
    });

    // Determine success
    const success = !!successfulRun;

    // Find error signature
    const errorEntry = entries.find(e => e.entry_type === 'ERROR_LOG');
    const errorSignature = errorEntry
      ? generateErrorSignature(errorEntry.summary + ' ' + (errorEntry.details || ''))
      : undefined;

    // Find winning hypothesis (last one before successful test)
    let winningHypothesis: JournalEntry | undefined;
    let losingHypotheses: JournalEntry[] = [];

    if (success && successfulRun) {
      const successTime = new Date(successfulRun.timestamp).getTime();

      // Winning = last hypothesis before success
      winningHypothesis = hypotheses
        .filter(h => new Date(h.timestamp).getTime() < successTime)
        .pop();

      // Losing = hypotheses followed by failed tests
      losingHypotheses = hypotheses.filter(h => {
        if (h.id === winningHypothesis?.id) return false;

        // Check if this hypothesis was followed by a failed test
        const hTime = new Date(h.timestamp).getTime();
        return testRuns.some(t => {
          const tTime = new Date(t.timestamp).getTime();
          if (tTime <= hTime) return false;
          try {
            const details = JSON.parse(t.details || '{}');
            return details.status === 'FAILED' || details.failed > 0;
          } catch {
            return false;
          }
        });
      });
    }

    // Extract strategy tags
    const allStrategiesTried = hypotheses.flatMap(h => extractStrategyTags(h.summary));
    const winningStrategy = winningHypothesis
      ? extractStrategyTags(winningHypothesis.summary)[0]
      : undefined;

    // Calculate time to fix
    const startTime = entries[0] ? new Date(entries[0].timestamp).getTime() : 0;
    const endTime = successfulRun ? new Date(successfulRun.timestamp).getTime() : Date.now();
    const timeToFixMs = endTime - startTime;

    return {
      sessionId,
      success,
      errorSignature,
      winningHypothesis,
      losingHypotheses,
      winningStrategy,
      allStrategiesTried: [...new Set(allStrategiesTried)],
      timeToFixMs,
      hypothesisCount: hypotheses.length,
    };
  }

  // ===========================================================================
  // KNOWLEDGE UPDATES
  // ===========================================================================

  /**
   * Update universal patterns with new success/failure data
   */
  private reinforcePattern(update: PatternUpdate): void {
    const { signature, strategy, wasSuccess, projectId, timeToFixMs } = update;

    // Get existing pattern or create new
    const existing = this.db.prepare(
      'SELECT * FROM universal_patterns WHERE signature = ?'
    ).get(signature) as any;

    if (existing) {
      // Update existing pattern
      const strategyStats = JSON.parse(existing.strategy_stats || '{}');
      strategyStats[strategy] = (strategyStats[strategy] || 0) + 1;

      // Update projects seen
      const projectsSeen = JSON.parse(existing.projects_seen || '[]');
      if (!projectsSeen.includes(projectId)) {
        projectsSeen.push(projectId);
      }

      // Calculate new average time to fix
      const totalOccurrences = existing.total_occurrences + 1;
      const newAvgTime = Math.round(
        (existing.avg_time_to_fix_ms * existing.total_occurrences + timeToFixMs) / totalOccurrences
      );

      // Determine best strategy (most successful)
      const bestStrategy = Object.entries(strategyStats)
        .sort(([, a], [, b]) => (b as number) - (a as number))[0]?.[0] || strategy;

      this.db.prepare(`
        UPDATE universal_patterns SET
          success_count = success_count + ?,
          failure_count = failure_count + ?,
          total_occurrences = total_occurrences + 1,
          best_strategy = ?,
          strategy_stats = ?,
          projects_seen = ?,
          avg_time_to_fix_ms = ?,
          last_seen = datetime('now')
        WHERE signature = ?
      `).run(
        wasSuccess ? 1 : 0,
        wasSuccess ? 0 : 1,
        bestStrategy,
        JSON.stringify(strategyStats),
        JSON.stringify(projectsSeen),
        newAvgTime,
        signature
      );

      console.log(`   📊 Updated pattern: ${signature.substring(0, 40)}...`);
    } else {
      // Create new pattern
      this.db.prepare(`
        INSERT INTO universal_patterns
        (signature, best_strategy, success_count, failure_count, total_occurrences,
         projects_seen, avg_time_to_fix_ms, strategy_stats)
        VALUES (?, ?, ?, ?, 1, ?, ?, ?)
      `).run(
        signature,
        strategy,
        wasSuccess ? 1 : 0,
        wasSuccess ? 0 : 1,
        JSON.stringify([projectId]),
        timeToFixMs,
        JSON.stringify({ [strategy]: 1 })
      );

      console.log(`   📊 Created new pattern: ${signature.substring(0, 40)}...`);
    }
  }

  /**
   * Tag hypotheses with their outcomes for future learning
   */
  private tagHypotheses(analysis: SessionAnalysis): void {
    // Tag winning hypothesis
    if (analysis.winningHypothesis) {
      const tags = extractStrategyTags(analysis.winningHypothesis.summary);
      this.db.prepare(`
        UPDATE dev_journal SET
          analysis_outcome = 'SUCCESS',
          approach_tags = ?
        WHERE id = ?
      `).run(JSON.stringify(tags), analysis.winningHypothesis.id);
    }

    // Tag losing hypotheses
    for (const loser of analysis.losingHypotheses) {
      const tags = extractStrategyTags(loser.summary);
      this.db.prepare(`
        UPDATE dev_journal SET
          analysis_outcome = 'FAILURE',
          approach_tags = ?
        WHERE id = ?
      `).run(JSON.stringify(tags), loser.id);
    }
  }

  /**
   * Log AI performance metrics for meta-learning
   */
  private logAIPerformance(analysis: SessionAnalysis, session: DevSession): void {
    const winningIndex = analysis.winningHypothesis
      ? analysis.losingHypotheses.length + 1
      : null;

    this.db.prepare(`
      INSERT INTO ai_performance_log
      (session_id, hypothesis_count, successful_hypothesis_index,
       approach_tags_tried, winning_approach_tag, time_to_fix_ms,
       error_signature, outcome)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    `).run(
      session.id,
      analysis.hypothesisCount,
      winningIndex,
      JSON.stringify(analysis.allStrategiesTried),
      analysis.winningStrategy || null,
      analysis.timeToFixMs,
      analysis.errorSignature || null,
      analysis.success ? 'FIXED' : 'ABANDONED'
    );
  }

  /**
   * Mark session as analyzed and store summary
   */
  private markSessionAnalyzed(sessionId: number, analysis: SessionAnalysis): void {
    this.db.prepare(`
      UPDATE dev_sessions SET
        reflection_status = 'ANALYZED',
        winning_strategy = ?,
        time_to_fix_ms = ?,
        hypothesis_count = ?,
        successful_hypothesis_id = ?
      WHERE id = ?
    `).run(
      analysis.winningStrategy || null,
      analysis.timeToFixMs,
      analysis.hypothesisCount,
      analysis.winningHypothesis?.id || null,
      sessionId
    );
  }

  // ===========================================================================
  // PLAYBOOK EVOLUTION
  // ===========================================================================

  /**
   * Check if we should create or update a playbook based on this session
   */
  private async considerPlaybookUpdate(
    analysis: SessionAnalysis,
    session: DevSession
  ): Promise<void> {
    if (!analysis.errorSignature || !analysis.winningStrategy) return;

    const existingPlaybook = this.db.prepare(
      'SELECT * FROM troubleshooting_playbooks WHERE error_signature = ?'
    ).get(analysis.errorSignature) as any;

    if (existingPlaybook) {
      // Update existing playbook
      this.evolvePlaybook(existingPlaybook.id, true, session.id);
    } else {
      // Check if we have enough evidence to create a new playbook
      const pattern = this.db.prepare(
        'SELECT * FROM universal_patterns WHERE signature = ?'
      ).get(analysis.errorSignature) as any;

      if (pattern && pattern.success_count >= 2) {
        // We've fixed this error multiple times - create a playbook
        this.createPlaybook(analysis, session, pattern);
      }
    }
  }

  /**
   * Evolve playbook confidence based on usage
   * Public to allow external calls from SessionManager
   */
  public evolvePlaybook(playbookId: number, wasHelpful: boolean, sessionId?: number): void {
    // Log usage
    this.db.prepare(`
      INSERT INTO playbook_usage_log (playbook_id, session_id, was_helpful)
      VALUES (?, ?, ?)
    `).run(playbookId, sessionId, wasHelpful ? 1 : 0);

    // Update counts
    if (wasHelpful) {
      this.db.prepare(`
        UPDATE troubleshooting_playbooks SET
          success_count = success_count + 1,
          last_used_at = datetime('now'),
          last_evolved_at = datetime('now')
        WHERE id = ?
      `).run(playbookId);
    } else {
      this.db.prepare(`
        UPDATE troubleshooting_playbooks SET
          failure_count = failure_count + 1,
          last_used_at = datetime('now'),
          last_evolved_at = datetime('now')
        WHERE id = ?
      `).run(playbookId);
    }

    // Recalculate confidence (Bayesian average)
    this.db.prepare(`
      UPDATE troubleshooting_playbooks SET
        confidence_score = (success_count + 1.0) / (success_count + failure_count + 2.0)
      WHERE id = ?
    `).run(playbookId);

    console.log(`   📖 Updated playbook confidence (id=${playbookId})`);
  }

  /**
   * Create a new playbook from a successful pattern
   */
  private createPlaybook(
    analysis: SessionAnalysis,
    session: DevSession,
    pattern: any
  ): void {
    const title = `Fixing: ${analysis.errorSignature?.substring(0, 50)}...`;
    const context = `Error pattern seen ${pattern.total_occurrences} times across ${
      JSON.parse(pattern.projects_seen || '[]').length
    } projects. Best approach: ${pattern.best_strategy}`;

    this.db.prepare(`
      INSERT INTO troubleshooting_playbooks
      (error_signature, title, context_summary, source_session_ids,
       success_count, confidence_score, project_id, status)
      VALUES (?, ?, ?, ?, 1, 0.6, ?, 'DRAFT')
    `).run(
      analysis.errorSignature,
      title,
      context,
      JSON.stringify([session.id]),
      session.project_id
    );

    console.log(`   📖 Created draft playbook: ${title}`);
  }

  // ===========================================================================
  // MAINTENANCE
  // ===========================================================================

  /**
   * Decay confidence of playbooks not used recently
   */
  private decayStalePlaybooks(): void {
    const result = this.db.prepare(`
      UPDATE troubleshooting_playbooks
      SET confidence_score = confidence_score * 0.995
      WHERE last_used_at < datetime('now', '-30 days')
        AND status = 'ACTIVE'
    `).run();

    if (result.changes > 0) {
      console.log(`   Decayed ${result.changes} stale playbook(s)`);
    }
  }

  /**
   * Archive playbooks with very low confidence
   */
  private archiveLowConfidencePlaybooks(): void {
    const result = this.db.prepare(`
      UPDATE troubleshooting_playbooks
      SET status = 'ARCHIVED'
      WHERE confidence_score < 0.2
        AND status = 'ACTIVE'
        AND total_occurrences >= 5
    `).run();

    if (result.changes > 0) {
      console.log(`   Archived ${result.changes} low-confidence playbook(s)`);
    }
  }

  /**
   * Update aggregate pattern statistics
   */
  private updatePatternStats(): void {
    // Could add more sophisticated analysis here
    console.log('   Pattern stats updated');
  }
}

export default Reflector;
