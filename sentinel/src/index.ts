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
 */

import { Command } from 'commander';
import WikiDatabase from './wiki-db.js';
import ChangeDetector from './detector.js';
import Analyzer from './analyzer.js';
import Proposer from './proposer.js';

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

program.parse();
