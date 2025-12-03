#!/usr/bin/env node
/**
 * Wiki Sentinel - Continuous Codebase Intelligence Agent
 *
 * Commands:
 *   sentinel watch    - Start continuous file watching
 *   sentinel scan     - Scan for git changes across all projects
 *   sentinel analyze  - Analyze ecosystem health
 *   sentinel report   - Generate full markdown report
 *   sentinel summary  - Show quick summary
 *   sentinel propose  - Generate proposals from pending changes
 *   sentinel accept <id> - Accept a proposal
 *   sentinel reject <id> - Reject a proposal
 *   sentinel complete <id> - Mark proposal as completed
 *
 * Session Commands (Self-Improving Journal):
 *   sentinel session start <project> <goal>  - Start a dev session
 *   sentinel session end <id> [summary]      - End a session
 *   sentinel session list                    - List recent sessions
 *   sentinel journal                         - Show recent journal entries
 *   sentinel tests watch                     - Start watching for test results
 *   sentinel tests process <file>            - Process a test result file
 *   sentinel stats                           - Show journal statistics
 */

import { Command } from 'commander';
import WikiDatabase from './wiki-db.js';
import ChangeDetector from './detector.js';
import Analyzer from './analyzer.js';
import Proposer from './proposer.js';
import SessionManager from './session-manager.js';
import TestWatcher from './test-watcher.js';
import Reflector from './reflector.js';

const program = new Command();

program
  .name('sentinel')
  .description('Wiki Sentinel - Continuous Codebase Intelligence Agent')
  .version('1.0.0');

program
  .command('watch')
  .description('Start continuous file watching')
  .action(async () => {
    const db = new WikiDatabase();
    const detector = new ChangeDetector(db);
    const analyzer = new Analyzer(db);
    const proposer = new Proposer(db);

    console.log('[Sentinel] Starting continuous monitoring...');
    console.log('[Sentinel] Press Ctrl+C to stop\n');

    detector.startWatching((changes) => {
      console.log(`[Sentinel] Detected ${changes.length} change(s)`);

      // Filter to significant changes
      const significant = changes.filter(c => c.isSignificant);
      if (significant.length > 0) {
        console.log(`[Sentinel] ${significant.length} significant change(s) detected`);

        // Analyze and generate proposals
        const results = analyzer.analyzeChanges(significant);
        if (results.length > 0) {
          const proposals = proposer.generateProposals(results);
          console.log(`[Sentinel] Generated ${proposals.length} proposal(s)`);
        }
      }
    });

    // Keep process running
    process.on('SIGINT', () => {
      console.log('\n[Sentinel] Shutting down...');
      detector.stopWatching();
      db.close();
      process.exit(0);
    });
  });

program
  .command('scan')
  .description('Scan for git changes across all projects')
  .action(() => {
    const db = new WikiDatabase();
    const detector = new ChangeDetector(db);

    console.log('[Sentinel] Scanning git changes...\n');

    const changes = detector.scanGitChanges();
    console.log(`Found ${changes.length} uncommitted change(s)\n`);

    // Group by project
    const byProject = new Map<string, typeof changes>();
    for (const change of changes) {
      const projectName = change.project.name;
      const existing = byProject.get(projectName) || [];
      existing.push(change);
      byProject.set(projectName, existing);
    }

    for (const [projectName, projectChanges] of byProject) {
      console.log(`\n${projectName}:`);
      for (const change of projectChanges.slice(0, 5)) {
        const icon = change.type === 'added' ? '+' : change.type === 'deleted' ? '-' : '~';
        const sig = change.isSignificant ? ' *' : '';
        console.log(`  ${icon} ${change.path.replace(change.project.path + '/', '')}${sig}`);
      }
      if (projectChanges.length > 5) {
        console.log(`  ... and ${projectChanges.length - 5} more`);
      }
    }

    db.close();
  });

program
  .command('analyze')
  .description('Analyze ecosystem health')
  .action(() => {
    const db = new WikiDatabase();
    const analyzer = new Analyzer(db);
    const proposer = new Proposer(db);

    console.log('[Sentinel] Analyzing ecosystem health...\n');

    const results = analyzer.analyzeEcosystem();
    console.log(`Found ${results.length} project(s) needing attention\n`);

    // Generate proposals
    const proposals = proposer.generateProposals(results);
    console.log(`Generated ${proposals.length} proposal(s)\n`);

    // Show summary
    const stats = analyzer.getSummaryStats();
    console.log('Ecosystem Summary:');
    console.log(`  Total Projects: ${stats.totalProjects}`);
    console.log(`  Healthy: ${stats.healthyProjects}`);
    console.log(`  Blocked: ${stats.blockedProjects}`);
    console.log(`  Potential MRR: $${stats.potentialMRR.toLocaleString()}`);

    db.close();
  });

program
  .command('report')
  .description('Generate full markdown report')
  .option('-o, --output <file>', 'Output file path')
  .action((options) => {
    const db = new WikiDatabase();
    const proposer = new Proposer(db);

    const report = proposer.generateReport();

    if (options.output) {
      const { writeFileSync } = require('fs');
      writeFileSync(options.output, report);
      console.log(`Report written to: ${options.output}`);
    } else {
      console.log(report);
    }

    db.close();
  });

program
  .command('summary')
  .description('Show quick summary')
  .action(() => {
    const db = new WikiDatabase();
    const proposer = new Proposer(db);

    console.log(proposer.generateSummary());

    db.close();
  });

program
  .command('propose')
  .description('Generate proposals from pending changes')
  .action(() => {
    const db = new WikiDatabase();
    const detector = new ChangeDetector(db);
    const analyzer = new Analyzer(db);
    const proposer = new Proposer(db);

    // Scan for changes
    console.log('[Sentinel] Scanning for changes...');
    const changes = detector.scanGitChanges();

    // Also get unprocessed from database
    const unprocessed = db.getUnprocessedChanges();

    if (changes.length === 0 && unprocessed.length === 0) {
      console.log('[Sentinel] No changes to process');
      db.close();
      return;
    }

    // Analyze ecosystem
    console.log('[Sentinel] Analyzing...');
    const ecosystemResults = analyzer.analyzeEcosystem();

    // Generate proposals
    const proposals = proposer.generateProposals(ecosystemResults);
    console.log(`\n[Sentinel] Generated ${proposals.length} proposal(s)\n`);

    // Show proposals
    const pending = proposer.getPendingProposals();
    for (const proposal of pending.slice(0, 10)) {
      console.log(`[${proposal.id}] ${proposal.priority}`);
      console.log(`    ${proposal.title}`);
      console.log(`    Project: ${proposal.project} | Revenue: ${proposal.revenue_impact}\n`);
    }

    db.close();
  });

program
  .command('accept <id>')
  .description('Accept a proposal')
  .action((id) => {
    const db = new WikiDatabase();
    const proposer = new Proposer(db);

    proposer.acceptProposal(parseInt(id));
    console.log(`Proposal ${id} accepted`);

    db.close();
  });

program
  .command('reject <id>')
  .description('Reject a proposal')
  .action((id) => {
    const db = new WikiDatabase();
    const proposer = new Proposer(db);

    proposer.rejectProposal(parseInt(id));
    console.log(`Proposal ${id} rejected`);

    db.close();
  });

program
  .command('complete <id>')
  .description('Mark proposal as completed')
  .action((id) => {
    const db = new WikiDatabase();
    const proposer = new Proposer(db);

    proposer.completeProposal(parseInt(id));
    console.log(`Proposal ${id} marked as completed`);

    db.close();
  });

program
  .command('commits')
  .description('Show recent commits across all projects')
  .option('-d, --days <number>', 'Number of days to look back', '7')
  .action((options) => {
    const db = new WikiDatabase();
    const detector = new ChangeDetector(db);

    const commits = detector.getRecentCommits(parseInt(options.days));
    console.log(`\nRecent commits (last ${options.days} days):\n`);

    let currentProject = '';
    for (const commit of commits.slice(0, 50)) {
      if (commit.project.name !== currentProject) {
        currentProject = commit.project.name;
        console.log(`\n${currentProject}:`);
      }
      const date = new Date(commit.date).toLocaleDateString();
      console.log(`  ${date} - ${commit.message.substring(0, 60)}`);
    }

    db.close();
  });

program
  .command('stale')
  .description('Find stale projects with no recent activity')
  .option('-d, --days <number>', 'Days of inactivity', '30')
  .action((options) => {
    const db = new WikiDatabase();
    const detector = new ChangeDetector(db);

    const stale = detector.detectStaleProjects(parseInt(options.days));
    console.log(`\nStale projects (no commits in ${options.days} days):\n`);

    for (const project of stale) {
      console.log(`  - ${project.name} (${project.type})`);
    }

    if (stale.length === 0) {
      console.log('  No stale projects found!');
    }

    db.close();
  });

// =============================================================================
// SESSION COMMANDS (Self-Improving Journal)
// =============================================================================

const sessionCmd = program.command('session').description('Manage development sessions');

sessionCmd
  .command('start <project> <goal>')
  .description('Start a new development session')
  .action((project, goal) => {
    const db = new WikiDatabase();
    const sessionManager = new SessionManager();

    // Find project
    const proj = db.getProject(project);
    if (!proj) {
      console.error(`[Sentinel] Project not found: ${project}`);
      console.log('Available projects:');
      db.getAllProjects().slice(0, 10).forEach(p => console.log(`  - ${p.name}`));
      db.close();
      process.exit(1);
    }

    // Check for existing active session
    const existing = sessionManager.getActiveSession(proj.id);
    if (existing) {
      console.warn(`[Sentinel] Warning: Active session already exists for ${proj.name}`);
      console.log(`  Session ID: ${existing.id}`);
      console.log(`  Goal: ${existing.goal}`);
      console.log(`  Started: ${existing.start_time}`);
      console.log('\nEnd it first with: sentinel session end ' + existing.id);
      db.close();
      return;
    }

    const session = sessionManager.startSession(proj.id, goal);
    console.log(`[Sentinel] Session started!`);
    console.log(`  ID: ${session.id}`);
    console.log(`  Project: ${proj.name}`);
    console.log(`  Goal: ${goal}`);
    console.log(`\nEnd session with: sentinel session end ${session.id} "outcome summary"`);

    sessionManager.close();
    db.close();
  });

sessionCmd
  .command('end <id>')
  .description('End a development session')
  .option('-s, --summary <text>', 'Outcome summary')
  .option('-a, --abandoned', 'Mark as abandoned instead of completed')
  .option('-f, --fix <entryId>', 'Explicitly tag the journal entry that fixed the issue (improves learning accuracy)')
  .action((id, options) => {
    const sessionManager = new SessionManager();

    const outcome = options.abandoned ? 'ABANDONED' : 'COMPLETED';
    const fixEntryId = options.fix ? parseInt(options.fix) : undefined;

    const session = sessionManager.endSession(parseInt(id), outcome, options.summary, fixEntryId);

    console.log(`[Sentinel] Session ${id} ended`);
    console.log(`  Status: ${session.status}`);
    if (fixEntryId) {
      console.log(`  Fix Entry: #${fixEntryId} (explicit tag - high confidence)`);
    }
    if (session.winning_strategy) {
      console.log(`  Winning Strategy: ${session.winning_strategy}`);
    }
    if (session.time_to_fix_ms) {
      console.log(`  Time to fix: ${(session.time_to_fix_ms / 1000).toFixed(1)}s`);
    }

    sessionManager.close();
  });

sessionCmd
  .command('list')
  .description('List recent development sessions')
  .option('-n, --limit <number>', 'Number of sessions to show', '10')
  .action((options) => {
    const sessionManager = new SessionManager();

    const sessions = sessionManager.getRecentSessions(parseInt(options.limit));
    console.log('\nRecent Development Sessions:\n');

    for (const session of sessions) {
      const status = session.status === 'IN_PROGRESS' ? '🔄' :
                     session.status === 'COMPLETED' ? '✅' : '❌';
      console.log(`${status} [${session.id}] ${session.project_name}`);
      console.log(`     Goal: ${session.goal}`);
      console.log(`     Started: ${session.start_time}`);
      if (session.winning_strategy) {
        console.log(`     Strategy: ${session.winning_strategy}`);
      }
      console.log('');
    }

    sessionManager.close();
  });

sessionCmd
  .command('show <id>')
  .description('Show detailed session information')
  .action((id) => {
    const sessionManager = new SessionManager();

    const session = sessionManager.getSession(parseInt(id));
    if (!session) {
      console.error(`Session ${id} not found`);
      sessionManager.close();
      process.exit(1);
    }

    console.log('\nSession Details:\n');
    console.log(`  ID: ${session.id}`);
    console.log(`  Goal: ${session.goal}`);
    console.log(`  Status: ${session.status}`);
    console.log(`  Started: ${session.start_time}`);
    if (session.end_time) {
      console.log(`  Ended: ${session.end_time}`);
    }
    if (session.outcome_summary) {
      console.log(`  Summary: ${session.outcome_summary}`);
    }
    if (session.winning_strategy) {
      console.log(`  Winning Strategy: ${session.winning_strategy}`);
    }

    // Show journal entries
    const entries = sessionManager.getSessionJournal(parseInt(id));
    if (entries.length > 0) {
      console.log(`\nJournal Entries (${entries.length}):\n`);
      for (const entry of entries.slice(-20)) {
        const icon = getEntryIcon(entry.entry_type);
        const outcome = entry.analysis_outcome ?
          ` [${entry.analysis_outcome}]` : '';
        console.log(`  ${icon} ${entry.timestamp?.substring(11, 19) || ''} ${entry.entry_type}${outcome}`);
        console.log(`     ${entry.summary.substring(0, 80)}`);
      }
    }

    sessionManager.close();
  });

// =============================================================================
// JOURNAL COMMANDS
// =============================================================================

program
  .command('journal')
  .description('Show recent journal entries')
  .option('-n, --limit <number>', 'Number of entries to show', '30')
  .option('-t, --type <type>', 'Filter by entry type')
  .action((options) => {
    const sessionManager = new SessionManager();

    const entries = sessionManager.getRecentJournal(parseInt(options.limit));
    console.log('\nRecent Journal Entries:\n');

    let filteredEntries = entries;
    if (options.type) {
      filteredEntries = entries.filter(e =>
        e.entry_type.toLowerCase().includes(options.type.toLowerCase())
      );
    }

    for (const entry of filteredEntries) {
      const icon = getEntryIcon(entry.entry_type);
      const outcome = entry.analysis_outcome ?
        ` [${entry.analysis_outcome}]` : '';
      console.log(`${icon} ${entry.timestamp?.substring(0, 19)} | ${entry.project_name}`);
      console.log(`   ${entry.entry_type}${outcome}: ${entry.summary.substring(0, 70)}`);
      console.log('');
    }

    sessionManager.close();
  });

// =============================================================================
// TEST COMMANDS
// =============================================================================

const testsCmd = program.command('tests').description('Manage test watching and results');

testsCmd
  .command('watch')
  .description('Start watching for test results')
  .option('-p, --project <name>', 'Watch specific project only')
  .action((options) => {
    const db = new WikiDatabase();
    const sessionManager = new SessionManager();
    const testWatcher = new TestWatcher(sessionManager, db);

    let paths: string[] | undefined;
    if (options.project) {
      const proj = db.getProject(options.project);
      if (!proj) {
        console.error(`Project not found: ${options.project}`);
        db.close();
        process.exit(1);
      }
      paths = [proj.path];
    }

    console.log('[Sentinel] Starting test watcher...');
    console.log('[Sentinel] Press Ctrl+C to stop\n');

    testWatcher.startWatching(paths);

    process.on('SIGINT', () => {
      console.log('\n[Sentinel] Stopping test watcher...');
      testWatcher.stopWatching();
      sessionManager.close();
      db.close();
      process.exit(0);
    });
  });

testsCmd
  .command('process <file>')
  .description('Process a test result file')
  .action(async (file) => {
    const db = new WikiDatabase();
    const sessionManager = new SessionManager();
    const testWatcher = new TestWatcher(sessionManager, db);

    try {
      const result = await testWatcher.processTestFile(file);
      if (result) {
        console.log('\nTest Results Processed:');
        console.log(`  Framework: ${result.framework}`);
        console.log(`  Status: ${result.status}`);
        console.log(`  Total: ${result.total_tests}`);
        console.log(`  Passed: ${result.passed_tests}`);
        console.log(`  Failed: ${result.failed_tests}`);
        console.log(`  Skipped: ${result.skipped_tests}`);
      } else {
        console.log('Could not parse test file');
      }
    } catch (error) {
      console.error('Error:', (error as Error).message);
    }

    sessionManager.close();
    db.close();
  });

testsCmd
  .command('flaky')
  .description('Show flaky tests')
  .option('-n, --limit <number>', 'Number of tests to show', '20')
  .action((options) => {
    const sessionManager = new SessionManager();

    const flaky = sessionManager.getFlakyTests(parseInt(options.limit));
    console.log('\nFlaky Tests (pass sometimes, fail sometimes):\n');

    if (flaky.length === 0) {
      console.log('  No flaky tests detected yet.');
      console.log('  Run more tests to build up history.');
    } else {
      for (const test of flaky) {
        console.log(`📊 ${test.test_name}`);
        console.log(`   File: ${test.test_file || 'unknown'}`);
        console.log(`   Runs: ${test.total_runs} | Pass: ${test.passes} | Fail: ${test.failures}`);
        console.log(`   Flakiness: ${test.flakiness_pct}%`);
        console.log('');
      }
    }

    sessionManager.close();
  });

// =============================================================================
// STATS COMMAND
// =============================================================================

program
  .command('stats')
  .description('Show journal and AI performance statistics')
  .action(() => {
    const sessionManager = new SessionManager();

    const journalStats = sessionManager.getJournalStats();
    const aiStats = sessionManager.getAIPerformance();

    console.log('\n═══════════════════════════════════════════');
    console.log('  SELF-IMPROVING JOURNAL STATISTICS');
    console.log('═══════════════════════════════════════════\n');

    console.log('📓 Journal Overview:');
    console.log(`   Sessions: ${journalStats.totalSessions} (${journalStats.completedSessions} completed)`);
    console.log(`   Journal Entries: ${journalStats.totalJournalEntries}`);
    console.log(`   Test Runs: ${journalStats.totalTestRuns}`);
    console.log(`   Pass Rate: ${journalStats.passRate || 0}%`);

    if (journalStats.topStrategies.length > 0) {
      console.log('\n🎯 Top Debugging Strategies:');
      for (const s of journalStats.topStrategies) {
        console.log(`   ${s.strategy}: ${s.success_rate}% success`);
      }
    }

    console.log('\n🤖 AI Performance:');
    console.log(`   Avg hypotheses per session: ${aiStats.avgHypothesesPerSession.toFixed(1)}`);
    console.log(`   First hypothesis success: ${aiStats.firstHypothesisSuccessRate}%`);
    if (aiStats.avgTimeToFix > 0) {
      console.log(`   Avg time to fix: ${(aiStats.avgTimeToFix / 1000).toFixed(1)}s`);
    }

    if (aiStats.topWinningApproaches.length > 0) {
      console.log('\n🏆 Winning Approaches:');
      for (const a of aiStats.topWinningApproaches) {
        console.log(`   ${a.approach}: ${a.wins} wins`);
      }
    }

    console.log('');
    sessionManager.close();
  });

// =============================================================================
// REFLECT COMMAND
// =============================================================================

program
  .command('reflect')
  .description('Run reflection on recent sessions')
  .option('-s, --session <id>', 'Reflect on specific session')
  .option('-a, --all', 'Reflect on all pending sessions')
  .action((options) => {
    const wikiDb = new WikiDatabase();
    const reflector = new Reflector(wikiDb.db);

    if (options.session) {
      console.log(`[Sentinel] Reflecting on session ${options.session}...`);
      reflector.reflectOnSession(parseInt(options.session));
      console.log('[Sentinel] Reflection complete');
    } else if (options.all) {
      console.log('[Sentinel] Reflecting on all pending sessions...');
      reflector.reflectOnPendingSessions();
      console.log('[Sentinel] Reflection complete');
    } else {
      console.log('[Sentinel] Running maintenance cycle...');
      reflector.runMaintenanceCycle();
      console.log('[Sentinel] Maintenance complete');
    }

    wikiDb.close();
  });

// =============================================================================
// PLAYBOOKS COMMAND
// =============================================================================

program
  .command('playbooks')
  .description('List troubleshooting playbooks')
  .option('-e, --error <signature>', 'Find playbooks for error signature')
  .option('-n, --limit <number>', 'Number of playbooks to show', '10')
  .action((options) => {
    const sessionManager = new SessionManager();

    if (options.error) {
      const playbooks = sessionManager.findPlaybooks(options.error);
      console.log(`\nPlaybooks matching "${options.error.substring(0, 50)}...":\n`);

      if (playbooks.length === 0) {
        console.log('  No matching playbooks found.');
        console.log('  This error pattern will be learned as you fix it.');
      } else {
        for (const pb of playbooks) {
          console.log(`📘 [${pb.id}] ${pb.title}`);
          console.log(`   Confidence: ${(pb.confidence_score * 100).toFixed(0)}%`);
          console.log('');
        }
      }
    } else {
      const wikiDb = new WikiDatabase();
      const playbooks = wikiDb.db.prepare(`
        SELECT * FROM trusted_playbooks LIMIT ?
      `).all(parseInt(options.limit)) as any[];

      console.log('\nTrusted Playbooks (>70% confidence):\n');

      if (playbooks.length === 0) {
        console.log('  No playbooks yet. They evolve from successful debugging sessions.');
      } else {
        for (const pb of playbooks) {
          const confidence = (pb.confidence_score * 100).toFixed(0);
          console.log(`📘 [${pb.id}] ${pb.title}`);
          console.log(`   Scope: ${pb.scope} | Confidence: ${confidence}%`);
          console.log(`   Success: ${pb.success_count} | Failure: ${pb.failure_count}`);
          console.log('');
        }
      }

      wikiDb.close();
    }

    sessionManager.close();
  });

// =============================================================================
// BRIEFING COMMAND
// =============================================================================

program
  .command('briefing')
  .description('Generate AI-optimized briefing with institutional memory')
  .option('-p, --project <name>', 'Project to focus on')
  .option('-e, --error <text>', 'Current error context')
  .action((options) => {
    const wikiDb = new WikiDatabase();

    console.log('\n═══════════════════════════════════════════');
    console.log('  🧠 INTELLIGENT BRIEFING');
    console.log('═══════════════════════════════════════════\n');

    // Get project context if specified
    let projectId: number | null = null;
    let projectName = 'All Projects';
    if (options.project) {
      const proj = wikiDb.getProject(options.project);
      if (proj) {
        projectId = proj.id;
        projectName = proj.name;
      }
    }

    console.log(`📁 Context: ${projectName}\n`);

    // 1. Show active session (if any)
    const activeSession = wikiDb.db.prepare(`
      SELECT s.*, p.name as project_name
      FROM dev_sessions s
      JOIN projects p ON s.project_id = p.id
      WHERE s.status = 'IN_PROGRESS'
      ORDER BY s.start_time DESC
      LIMIT 1
    `).get() as any;

    if (activeSession) {
      console.log('🔄 Active Session:');
      console.log(`   ID: ${activeSession.id}`);
      console.log(`   Project: ${activeSession.project_name}`);
      console.log(`   Goal: ${activeSession.goal}`);
      console.log(`   Started: ${activeSession.start_time}\n`);
    }

    // 2. Show what works in this codebase
    const strategies = wikiDb.db.prepare(`
      SELECT
        json_each.value as strategy,
        COUNT(*) as uses,
        SUM(CASE WHEN j.analysis_outcome = 'SUCCESS' THEN 1 ELSE 0 END) as successes
      FROM dev_journal j, json_each(j.approach_tags)
      ${projectId ? 'WHERE j.project_id = ?' : ''}
      GROUP BY json_each.value
      HAVING uses > 0
      ORDER BY successes DESC, uses DESC
      LIMIT 5
    `).all(projectId ? [projectId] : []) as any[];

    if (strategies.length > 0) {
      console.log('📊 What Works in This Codebase:');
      for (const s of strategies) {
        const rate = s.uses > 0 ? Math.round((s.successes / s.uses) * 100) : 0;
        console.log(`   ${s.strategy}: ${rate}% effective (${s.uses} uses)`);
      }
      console.log('');
    }

    // 3. Show recent errors and their resolutions
    const recentErrors = wikiDb.db.prepare(`
      SELECT
        j.summary as error,
        s.winning_strategy,
        s.outcome_summary
      FROM dev_journal j
      JOIN dev_sessions s ON j.session_id = s.id
      WHERE j.entry_type = 'ERROR_LOG'
        AND s.status = 'COMPLETED'
        AND s.winning_strategy IS NOT NULL
        ${projectId ? 'AND j.project_id = ?' : ''}
      ORDER BY j.timestamp DESC
      LIMIT 5
    `).all(projectId ? [projectId] : []) as any[];

    if (recentErrors.length > 0) {
      console.log('🔧 Recent Fixes (Pattern Library):');
      for (const e of recentErrors) {
        console.log(`   Error: ${e.error.substring(0, 50)}...`);
        console.log(`   → Fixed with: ${e.winning_strategy}`);
        console.log('');
      }
    }

    // 4. If error text provided, find matching patterns
    if (options.error) {
      console.log(`🔍 Searching for: "${options.error.substring(0, 40)}..."\n`);

      const sessionManager = new SessionManager();
      const playbooks = sessionManager.findPlaybooks(options.error, 3);

      if (playbooks.length > 0) {
        console.log('📘 Matching Playbooks:');
        for (const pb of playbooks) {
          console.log(`   [${pb.id}] ${pb.title}`);
          console.log(`   Confidence: ${(pb.confidence_score * 100).toFixed(0)}%`);
          if (pb.solution_steps) {
            console.log(`   Steps: ${pb.solution_steps.substring(0, 100)}...`);
          }
          console.log('');
        }
      } else {
        // Search journal for similar errors
        const similar = wikiDb.db.prepare(`
          SELECT j.summary, s.winning_strategy, s.outcome_summary
          FROM dev_journal j
          LEFT JOIN dev_sessions s ON j.session_id = s.id
          WHERE j.entry_type = 'ERROR_LOG'
            AND j.summary LIKE ?
            AND s.winning_strategy IS NOT NULL
          ORDER BY j.timestamp DESC
          LIMIT 3
        `).all([`%${options.error.substring(0, 30)}%`]) as any[];

        if (similar.length > 0) {
          console.log('💡 Similar Errors Fixed Before:');
          for (const e of similar) {
            console.log(`   ${e.summary.substring(0, 60)}...`);
            console.log(`   → Strategy: ${e.winning_strategy}`);
            console.log('');
          }
        } else {
          console.log('ℹ️  No matching patterns yet. Fix this error and the system will learn!');
          console.log('');
        }
      }
      sessionManager.close();
    }

    // 5. Show universal patterns (cross-project learnings)
    const patterns = wikiDb.db.prepare(`
      SELECT signature, best_strategy, success_count, total_occurrences,
             json_array_length(projects_seen) as project_count
      FROM universal_patterns
      WHERE success_count >= 1
      ORDER BY success_count DESC, total_occurrences DESC
      LIMIT 5
    `).all() as any[];

    if (patterns.length > 0) {
      console.log('🌐 Universal Patterns (Cross-Project Learning):');
      for (const p of patterns) {
        const rate = Math.round((p.success_count / p.total_occurrences) * 100);
        console.log(`   ${p.signature.substring(0, 40)}...`);
        console.log(`   → Best: ${p.best_strategy} (${rate}% success across ${p.project_count} projects)`);
        console.log('');
      }
    }

    // 6. Quick tips based on time of day / session count
    const sessionCount = wikiDb.db.prepare('SELECT COUNT(*) as c FROM dev_sessions WHERE status = \'COMPLETED\'').get() as any;
    console.log('───────────────────────────────────────────');
    console.log('💡 Workflow Tip:');
    if (sessionCount.c < 5) {
      console.log('   You\'re just getting started! Keep using:');
      console.log('   wiki session start/end to train the system.');
    } else if (sessionCount.c < 20) {
      console.log('   Patterns are forming. Use wiki playbooks to');
      console.log('   see what strategies are proving effective.');
    } else {
      console.log('   The system has good data. Trust wiki briefing');
      console.log('   suggestions - they\'re based on your history.');
    }
    console.log('');

    wikiDb.close();
  });

// =============================================================================
// PATTERNS COMMAND
// =============================================================================

program
  .command('patterns')
  .description('Show learned universal patterns')
  .option('-n, --limit <number>', 'Number of patterns to show', '20')
  .action((options) => {
    const wikiDb = new WikiDatabase();

    console.log('\n═══════════════════════════════════════════');
    console.log('  🌐 UNIVERSAL PATTERNS');
    console.log('═══════════════════════════════════════════\n');

    const patterns = wikiDb.db.prepare(`
      SELECT *
      FROM universal_patterns
      ORDER BY success_count DESC, total_occurrences DESC
      LIMIT ?
    `).all([parseInt(options.limit)]) as any[];

    if (patterns.length === 0) {
      console.log('  No patterns learned yet.');
      console.log('  Complete debugging sessions to build up knowledge.');
      console.log('');
      console.log('  Workflow:');
      console.log('  1. wiki session start "project" "Fix bug X"');
      console.log('  2. Log errors and hypotheses');
      console.log('  3. wiki session end "What worked"');
      console.log('');
    } else {
      for (const p of patterns) {
        const rate = Math.round((p.success_count / p.total_occurrences) * 100);
        const projects = JSON.parse(p.projects_seen || '[]');
        const stratStats = JSON.parse(p.strategy_stats || '{}');

        console.log(`🔹 ${p.signature.substring(0, 60)}...`);
        console.log(`   Best Strategy: ${p.best_strategy}`);
        console.log(`   Success Rate: ${rate}% (${p.success_count}/${p.total_occurrences})`);
        console.log(`   Seen in ${projects.length} project(s)`);
        console.log(`   Avg Fix Time: ${(p.avg_time_to_fix_ms / 1000).toFixed(1)}s`);
        console.log(`   All Strategies: ${Object.keys(stratStats).join(', ')}`);
        console.log(`   Last Seen: ${p.last_seen}`);
        console.log('');
      }
    }

    wikiDb.close();
  });

// =============================================================================
// HELPER FUNCTIONS
// =============================================================================

function getEntryIcon(entryType: string): string {
  const icons: Record<string, string> = {
    'SESSION_START': '🚀',
    'SESSION_END': '🏁',
    'TEST_RUN': '🧪',
    'ERROR_LOG': '❌',
    'FILE_CHANGE': '📝',
    'AI_TASK': '🤖',
    'AI_HYPOTHESIS': '💡',
    'AI_TOOL_CALL': '🔧',
    'AI_OBSERVATION': '👁️',
    'NOTE': '📌',
    'COMMAND_RUN': '⚡',
    'BUILD_EVENT': '🏗️',
  };
  return icons[entryType] || '•';
}

program.parse();
