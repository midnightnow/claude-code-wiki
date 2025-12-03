/**
 * Change Detection Engine
 *
 * Monitors filesystem and git for changes across all indexed projects
 */

import { watch, FSWatcher } from 'chokidar';
import { execSync, spawnSync } from 'child_process';
import { existsSync, statSync } from 'fs';
import { join, dirname, basename } from 'path';
import WikiDatabase, { Project, ChangeRecord } from './wiki-db.js';

export interface DetectedChange {
  project: Project;
  type: 'added' | 'modified' | 'deleted' | 'moved';
  path: string;
  timestamp: Date;
  isSignificant: boolean;
  category: 'code' | 'config' | 'docs' | 'deps' | 'other';
}

export class ChangeDetector {
  private db: WikiDatabase;
  private watchers: Map<string, FSWatcher> = new Map();
  private changeBuffer: DetectedChange[] = [];
  private onChangeCallback?: (changes: DetectedChange[]) => void;
  private flushInterval?: NodeJS.Timeout;

  // Files that indicate significant changes
  private static SIGNIFICANT_FILES = [
    'package.json',
    'tsconfig.json',
    'firebase.json',
    'requirements.txt',
    'go.mod',
    'Cargo.toml',
    '.env.example',
    'CLAUDE.md',
    'GEMINI_CONTEXT.md',
    'README.md',
  ];

  // Patterns to ignore
  private static IGNORE_PATTERNS = [
    '**/node_modules/**',
    '**/.git/**',
    '**/dist/**',
    '**/build/**',
    '**/.next/**',
    '**/__pycache__/**',
    '**/.venv/**',
    '**/coverage/**',
    '**/.cache/**',
    '**/playwright-report/**',
    '**/test-results/**',
  ];

  constructor(db: WikiDatabase) {
    this.db = db;
  }

  /**
   * Start watching all indexed projects
   */
  startWatching(onChange?: (changes: DetectedChange[]) => void): void {
    this.onChangeCallback = onChange;
    const projects = this.db.getAllProjects();

    console.log(`[Sentinel] Starting file watchers for ${projects.length} projects`);

    for (const project of projects) {
      if (!existsSync(project.path)) continue;

      const watcher = watch(project.path, {
        ignored: ChangeDetector.IGNORE_PATTERNS,
        persistent: true,
        ignoreInitial: true,
        awaitWriteFinish: {
          stabilityThreshold: 500,
          pollInterval: 100,
        },
      });

      watcher
        .on('add', (path) => this.handleChange(project, 'added', path))
        .on('change', (path) => this.handleChange(project, 'modified', path))
        .on('unlink', (path) => this.handleChange(project, 'deleted', path));

      this.watchers.set(project.path, watcher);
    }

    // Flush changes every 5 seconds
    this.flushInterval = setInterval(() => this.flushChanges(), 5000);
  }

  /**
   * Stop all watchers
   */
  stopWatching(): void {
    for (const [path, watcher] of this.watchers) {
      watcher.close();
    }
    this.watchers.clear();

    if (this.flushInterval) {
      clearInterval(this.flushInterval);
    }
  }

  /**
   * Handle a detected change
   */
  private handleChange(project: Project, type: 'added' | 'modified' | 'deleted', path: string): void {
    const filename = basename(path);
    const category = this.categorizeFile(path);
    const isSignificant = this.isSignificantChange(path, type);

    const change: DetectedChange = {
      project,
      type,
      path,
      timestamp: new Date(),
      isSignificant,
      category,
    };

    // Store in buffer
    this.changeBuffer.push(change);

    // Record in database
    this.db.recordChange({
      project_id: project.id,
      change_type: type,
      file_path: path,
      detected_at: new Date().toISOString(),
      processed: 0,
    });

    // Immediate callback for significant changes
    if (isSignificant && this.onChangeCallback) {
      this.onChangeCallback([change]);
    }
  }

  /**
   * Flush buffered changes to callback
   */
  private flushChanges(): void {
    if (this.changeBuffer.length === 0) return;

    const changes = [...this.changeBuffer];
    this.changeBuffer = [];

    if (this.onChangeCallback) {
      this.onChangeCallback(changes);
    }
  }

  /**
   * Categorize a file by type
   */
  private categorizeFile(path: string): 'code' | 'config' | 'docs' | 'deps' | 'other' {
    const filename = basename(path);
    const ext = path.split('.').pop()?.toLowerCase() || '';

    // Dependencies
    if (['package.json', 'package-lock.json', 'yarn.lock', 'requirements.txt', 'go.mod', 'Cargo.toml'].includes(filename)) {
      return 'deps';
    }

    // Config files
    if (filename.startsWith('.') || ['json', 'yaml', 'yml', 'toml', 'ini'].includes(ext)) {
      if (filename.includes('config') || filename.includes('rc') || ChangeDetector.SIGNIFICANT_FILES.includes(filename)) {
        return 'config';
      }
    }

    // Documentation
    if (ext === 'md' || path.includes('/docs/')) {
      return 'docs';
    }

    // Code
    if (['ts', 'tsx', 'js', 'jsx', 'py', 'go', 'rs', 'java', 'kt', 'swift'].includes(ext)) {
      return 'code';
    }

    return 'other';
  }

  /**
   * Determine if a change is significant
   */
  private isSignificantChange(path: string, type: string): boolean {
    const filename = basename(path);

    // Always significant files
    if (ChangeDetector.SIGNIFICANT_FILES.includes(filename)) {
      return true;
    }

    // New source files are significant
    if (type === 'added') {
      const ext = path.split('.').pop()?.toLowerCase() || '';
      if (['ts', 'tsx', 'py', 'go', 'rs'].includes(ext)) {
        return true;
      }
    }

    // Deleted source files are significant
    if (type === 'deleted') {
      return true;
    }

    return false;
  }

  /**
   * Scan for git changes across all projects
   */
  scanGitChanges(): DetectedChange[] {
    const changes: DetectedChange[] = [];
    const projects = this.db.getAllProjects();

    for (const project of projects) {
      if (!existsSync(join(project.path, '.git'))) continue;

      try {
        // Get uncommitted changes
        const status = execSync('git status --porcelain', {
          cwd: project.path,
          encoding: 'utf-8',
        }).trim();

        if (!status) continue;

        for (const line of status.split('\n')) {
          const statusCode = line.substring(0, 2).trim();
          const filePath = line.substring(3);

          let type: 'added' | 'modified' | 'deleted' = 'modified';
          if (statusCode === 'A' || statusCode === '??') type = 'added';
          else if (statusCode === 'D') type = 'deleted';

          const fullPath = join(project.path, filePath);
          const category = this.categorizeFile(fullPath);
          const isSignificant = this.isSignificantChange(fullPath, type);

          changes.push({
            project,
            type,
            path: fullPath,
            timestamp: new Date(),
            isSignificant,
            category,
          });

          // Record in database
          this.db.recordChange({
            project_id: project.id,
            change_type: type,
            file_path: fullPath,
            detected_at: new Date().toISOString(),
            processed: 0,
          });
        }
      } catch (error) {
        // Git command failed, skip project
      }
    }

    return changes;
  }

  /**
   * Get recent commits across all projects
   */
  getRecentCommits(days = 7): Array<{ project: Project; hash: string; message: string; date: string }> {
    const commits: Array<{ project: Project; hash: string; message: string; date: string }> = [];
    const projects = this.db.getAllProjects();

    for (const project of projects) {
      if (!existsSync(join(project.path, '.git'))) continue;

      try {
        const log = execSync(
          `git log --since="${days} days ago" --oneline --format="%H|%s|%ai"`,
          { cwd: project.path, encoding: 'utf-8' }
        ).trim();

        if (!log) continue;

        for (const line of log.split('\n')) {
          const [hash, message, date] = line.split('|');
          if (hash && message) {
            commits.push({ project, hash, message, date });
          }
        }
      } catch (error) {
        // Git command failed, skip
      }
    }

    return commits.sort((a, b) => new Date(b.date).getTime() - new Date(a.date).getTime());
  }

  /**
   * Detect stale projects (no commits in N days)
   */
  detectStaleProjects(days = 30): Project[] {
    const stale: Project[] = [];
    const projects = this.db.getAllProjects();

    for (const project of projects) {
      if (!existsSync(join(project.path, '.git'))) continue;

      try {
        const lastCommit = execSync(
          'git log -1 --format=%ai',
          { cwd: project.path, encoding: 'utf-8' }
        ).trim();

        if (lastCommit) {
          const lastDate = new Date(lastCommit);
          const daysAgo = (Date.now() - lastDate.getTime()) / (1000 * 60 * 60 * 24);
          if (daysAgo > days) {
            stale.push(project);
          }
        }
      } catch (error) {
        // Git command failed, skip
      }
    }

    return stale;
  }
}

export default ChangeDetector;
