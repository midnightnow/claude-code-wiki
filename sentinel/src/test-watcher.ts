/**
 * =============================================================================
 * TEST WATCHER
 * =============================================================================
 *
 * Automatically captures test results from various test frameworks.
 * Parses junit.xml, jest-results.json, pytest reports, etc.
 *
 * Zero-friction integration - just watches for test output files.
 */

import { watch, FSWatcher } from 'chokidar';
import { readFileSync, existsSync } from 'fs';
import { join, basename, dirname } from 'path';
import { parseString } from 'xml2js';
import SessionManager from './session-manager.js';
import { generateErrorSignature, parseTestError } from './error-utils.js';
import WikiDatabase from './wiki-db.js';

interface TestFrameworkResult {
  framework: string;
  status: 'PASSED' | 'FAILED' | 'ERROR';
  duration_ms?: number;
  total_tests: number;
  passed_tests: number;
  failed_tests: number;
  skipped_tests: number;
  tests: {
    name: string;
    file?: string;
    status: 'PASSED' | 'FAILED' | 'SKIPPED' | 'ERROR';
    duration_ms?: number;
    error_message?: string;
    error_signature?: string;
    stdout?: string;
    stderr?: string;
  }[];
}

export class TestWatcher {
  private watcher: FSWatcher | null = null;
  private sessionManager: SessionManager;
  private wikiDb: WikiDatabase;
  private watchPaths: string[] = [];

  // Common test output file patterns
  private static readonly TEST_FILE_PATTERNS = [
    '**/junit.xml',
    '**/junit-*.xml',
    '**/test-results.xml',
    '**/jest-results.json',
    '**/jest-output.json',
    '**/.jest-results/*.json',
    '**/coverage/junit.xml',
    '**/pytest-report.xml',
    '**/pytest-results.xml',
    '**/test-output/*.xml',
    '**/reports/tests/*.xml',
    '**/build/test-results/**/*.xml',
    '**/target/surefire-reports/*.xml',
  ];

  constructor(sessionManager?: SessionManager, wikiDb?: WikiDatabase) {
    this.wikiDb = wikiDb || new WikiDatabase();
    this.sessionManager = sessionManager || new SessionManager();
  }

  /**
   * Start watching for test results in specified directories
   */
  startWatching(projectPaths?: string[]): void {
    if (this.watcher) {
      console.log('[TestWatcher] Already watching');
      return;
    }

    // Get paths to watch from projects or defaults
    if (projectPaths) {
      this.watchPaths = projectPaths;
    } else {
      // Watch all indexed projects
      const projects = this.wikiDb.getAllProjects();
      this.watchPaths = projects.map(p => p.path);
    }

    console.log(`[TestWatcher] Watching ${this.watchPaths.length} project(s) for test results...`);

    // Build glob patterns for all projects
    const patterns = this.watchPaths.flatMap(projectPath =>
      TestWatcher.TEST_FILE_PATTERNS.map(pattern => join(projectPath, pattern))
    );

    this.watcher = watch(patterns, {
      persistent: true,
      ignoreInitial: true,
      awaitWriteFinish: {
        stabilityThreshold: 500,
        pollInterval: 100,
      },
    });

    this.watcher.on('add', (path) => this.handleTestFile(path));
    this.watcher.on('change', (path) => this.handleTestFile(path));

    this.watcher.on('error', (error) => {
      console.error('[TestWatcher] Error:', error.message);
    });
  }

  /**
   * Stop watching
   */
  stopWatching(): void {
    if (this.watcher) {
      this.watcher.close();
      this.watcher = null;
      console.log('[TestWatcher] Stopped watching');
    }
  }

  /**
   * Handle a detected test result file
   */
  private async handleTestFile(filePath: string): Promise<void> {
    console.log(`[TestWatcher] Detected test output: ${basename(filePath)}`);

    try {
      const result = await this.parseTestFile(filePath);
      if (result) {
        await this.recordTestResult(filePath, result);
      }
    } catch (error) {
      console.error(`[TestWatcher] Error parsing ${filePath}:`, (error as Error).message);
    }
  }

  /**
   * Parse test file based on format
   */
  private async parseTestFile(filePath: string): Promise<TestFrameworkResult | null> {
    const content = readFileSync(filePath, 'utf-8');
    const filename = basename(filePath).toLowerCase();

    if (filename.endsWith('.json')) {
      return this.parseJestJson(content, filePath);
    } else if (filename.endsWith('.xml')) {
      return this.parseJunitXml(content, filePath);
    }

    return null;
  }

  /**
   * Parse Jest JSON output
   */
  private parseJestJson(content: string, filePath: string): TestFrameworkResult | null {
    try {
      const data = JSON.parse(content);

      // Handle Jest's standard output format
      if (data.testResults || data.numTotalTests !== undefined) {
        const tests: TestFrameworkResult['tests'] = [];

        // Standard Jest format
        if (data.testResults) {
          for (const suite of data.testResults) {
            for (const test of suite.assertionResults || []) {
              const errorMsg = test.failureMessages?.join('\n') || undefined;
              tests.push({
                name: test.fullName || test.title,
                file: suite.name,
                status: this.mapJestStatus(test.status),
                duration_ms: test.duration,
                error_message: errorMsg,
                error_signature: errorMsg ? generateErrorSignature(errorMsg) : undefined,
              });
            }
          }
        }

        return {
          framework: 'jest',
          status: data.success ? 'PASSED' : 'FAILED',
          duration_ms: data.testResults?.[0]?.endTime
            ? data.testResults[0].endTime - data.testResults[0].startTime
            : undefined,
          total_tests: data.numTotalTests || tests.length,
          passed_tests: data.numPassedTests || tests.filter(t => t.status === 'PASSED').length,
          failed_tests: data.numFailedTests || tests.filter(t => t.status === 'FAILED').length,
          skipped_tests: data.numPendingTests || tests.filter(t => t.status === 'SKIPPED').length,
          tests,
        };
      }
    } catch (e) {
      console.error('[TestWatcher] Failed to parse Jest JSON:', (e as Error).message);
    }

    return null;
  }

  /**
   * Parse JUnit XML output (used by many frameworks)
   */
  private async parseJunitXml(content: string, filePath: string): Promise<TestFrameworkResult | null> {
    return new Promise((resolve) => {
      parseString(content, { explicitArray: false }, (err, result) => {
        if (err) {
          console.error('[TestWatcher] Failed to parse JUnit XML:', err.message);
          resolve(null);
          return;
        }

        try {
          const testsuites = result.testsuites || result.testsuite;
          if (!testsuites) {
            resolve(null);
            return;
          }

          // Handle single testsuite or multiple
          const suites = Array.isArray(testsuites.testsuite)
            ? testsuites.testsuite
            : testsuites.testsuite
            ? [testsuites.testsuite]
            : [testsuites];

          const tests: TestFrameworkResult['tests'] = [];
          let totalPassed = 0;
          let totalFailed = 0;
          let totalSkipped = 0;
          let totalTime = 0;

          for (const suite of suites) {
            const testcases = Array.isArray(suite.testcase)
              ? suite.testcase
              : suite.testcase
              ? [suite.testcase]
              : [];

            for (const tc of testcases) {
              const failure = tc.failure || tc.error;
              const skipped = tc.skipped !== undefined;

              let status: 'PASSED' | 'FAILED' | 'SKIPPED' | 'ERROR' = 'PASSED';
              let errorMsg: string | undefined;

              if (failure) {
                status = tc.error ? 'ERROR' : 'FAILED';
                errorMsg = typeof failure === 'string'
                  ? failure
                  : failure._ || failure.$.message || 'Unknown error';
                totalFailed++;
              } else if (skipped) {
                status = 'SKIPPED';
                totalSkipped++;
              } else {
                totalPassed++;
              }

              const duration = tc.$.time ? parseFloat(tc.$.time) * 1000 : undefined;
              if (duration) totalTime += duration;

              tests.push({
                name: tc.$.name || 'Unknown test',
                file: tc.$.classname || suite.$.name,
                status,
                duration_ms: duration,
                error_message: errorMsg,
                error_signature: errorMsg ? generateErrorSignature(errorMsg) : undefined,
                stdout: tc['system-out']?._,
                stderr: tc['system-err']?._,
              });
            }
          }

          const totalTests = totalPassed + totalFailed + totalSkipped;

          resolve({
            framework: 'junit',
            status: totalFailed > 0 ? 'FAILED' : 'PASSED',
            duration_ms: totalTime || undefined,
            total_tests: totalTests,
            passed_tests: totalPassed,
            failed_tests: totalFailed,
            skipped_tests: totalSkipped,
            tests,
          });
        } catch (e) {
          console.error('[TestWatcher] Error processing JUnit XML:', (e as Error).message);
          resolve(null);
        }
      });
    });
  }

  /**
   * Record test result to the journal
   */
  private async recordTestResult(filePath: string, result: TestFrameworkResult): Promise<void> {
    // Find the project for this file
    const projectPath = this.findProjectPath(filePath);
    if (!projectPath) {
      console.warn(`[TestWatcher] Could not find project for: ${filePath}`);
      return;
    }

    const project = this.wikiDb.getProjectByPath(projectPath);
    if (!project) {
      console.warn(`[TestWatcher] Project not indexed: ${projectPath}`);
      return;
    }

    // Check for active session
    const activeSession = this.sessionManager.getActiveSession(project.id);

    console.log(`[TestWatcher] Recording ${result.framework} results for ${project.name}:`);
    console.log(`  Status: ${result.status}`);
    console.log(`  Tests: ${result.passed_tests}/${result.total_tests} passed`);
    if (result.failed_tests > 0) {
      console.log(`  Failed: ${result.failed_tests}`);
    }

    // Record the test run
    const testRunId = this.sessionManager.recordTestRun(
      project.id,
      activeSession?.id,
      {
        status: result.status,
        duration_ms: result.duration_ms,
        total_tests: result.total_tests,
        passed_tests: result.passed_tests,
        failed_tests: result.failed_tests,
        skipped_tests: result.skipped_tests,
        source_file: filePath,
      }
    );

    // Record individual test results
    this.sessionManager.recordTestResults(
      testRunId,
      result.tests.map(t => ({
        test_name: t.name,
        test_file: t.file,
        status: t.status,
        duration_ms: t.duration_ms,
        error_message: t.error_message,
        error_signature: t.error_signature,
        stdout: t.stdout,
        stderr: t.stderr,
      }))
    );

    // If there are failures, log them for playbook matching
    const failures = result.tests.filter(t => t.status === 'FAILED' || t.status === 'ERROR');
    for (const failure of failures) {
      if (failure.error_signature) {
        const playbooks = this.sessionManager.findPlaybooks(failure.error_signature);
        if (playbooks.length > 0) {
          console.log(`[TestWatcher] Found ${playbooks.length} playbook(s) for: ${failure.name}`);
          console.log(`  Top match: "${playbooks[0].title}" (${playbooks[0].confidence_score * 100}% confidence)`);
        }
      }
    }
  }

  /**
   * Find the project path for a file
   */
  private findProjectPath(filePath: string): string | null {
    for (const projectPath of this.watchPaths) {
      if (filePath.startsWith(projectPath)) {
        return projectPath;
      }
    }

    // Try to find by walking up directories
    let dir = dirname(filePath);
    while (dir !== '/' && dir !== '.') {
      if (existsSync(join(dir, 'package.json')) ||
          existsSync(join(dir, 'pyproject.toml')) ||
          existsSync(join(dir, '.git'))) {
        return dir;
      }
      dir = dirname(dir);
    }

    return null;
  }

  /**
   * Map Jest status to standard status
   */
  private mapJestStatus(status: string): 'PASSED' | 'FAILED' | 'SKIPPED' | 'ERROR' {
    switch (status.toLowerCase()) {
      case 'passed':
        return 'PASSED';
      case 'failed':
        return 'FAILED';
      case 'pending':
      case 'skipped':
      case 'todo':
        return 'SKIPPED';
      default:
        return 'ERROR';
    }
  }

  /**
   * Manually process a test file
   */
  async processTestFile(filePath: string): Promise<TestFrameworkResult | null> {
    if (!existsSync(filePath)) {
      throw new Error(`File not found: ${filePath}`);
    }

    const result = await this.parseTestFile(filePath);
    if (result) {
      await this.recordTestResult(filePath, result);
    }
    return result;
  }
}

export default TestWatcher;
