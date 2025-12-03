/**
 * Wiki Database Interface
 *
 * SQLite integration with existing wiki.db
 */

import Database from 'better-sqlite3';
import { existsSync } from 'fs';
import { homedir } from 'os';
import { join } from 'path';

export interface Project {
  id: number;
  name: string;
  path: string;
  type: string;
  has_context: number;
  file_count: number;
  primary_language: string;
  last_indexed_at: string;
}

export interface WikiFile {
  id: number;
  project_id: number;
  path: string;
  filename: string;
  extension: string;
  size: number;
  is_config: number;
}

export interface ChangeRecord {
  id?: number;
  project_id: number;
  change_type: 'added' | 'modified' | 'deleted' | 'moved';
  file_path: string;
  detected_at: string;
  processed: number;
  proposal_id?: number;
}

export interface Proposal {
  id?: number;
  project_id: number;
  priority: 'critical' | 'high' | 'medium' | 'low';
  category: string;
  title: string;
  description: string;
  action_items: string; // JSON array
  created_at: string;
  status: 'pending' | 'accepted' | 'rejected' | 'completed';
  revenue_impact?: number;
}

export class WikiDatabase {
  public readonly db: Database.Database;  // Exposed for Reflector access
  private wikiDir: string;
  private dataDir: string;

  constructor() {
    this.wikiDir = join(homedir(), 'claude-code-wiki');
    // Wiki stores data in XDG_DATA_HOME (~/.local/share/claude-wiki)
    this.dataDir = process.env.XDG_DATA_HOME
      ? join(process.env.XDG_DATA_HOME, 'claude-wiki')
      : join(homedir(), '.local', 'share', 'claude-wiki');
    const dbPath = join(this.dataDir, 'wiki.db');

    if (!existsSync(dbPath)) {
      throw new Error(`Wiki database not found at ${dbPath}. Run 'wiki scan' first.`);
    }

    this.db = new Database(dbPath);
    this.ensureSentinelTables();
  }

  /**
   * Create sentinel-specific tables if they don't exist
   */
  private ensureSentinelTables(): void {
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS change_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        project_id INTEGER REFERENCES projects(id),
        change_type TEXT NOT NULL,
        file_path TEXT NOT NULL,
        detected_at TEXT DEFAULT (datetime('now')),
        processed INTEGER DEFAULT 0,
        proposal_id INTEGER,
        UNIQUE(project_id, file_path, change_type, detected_at)
      );

      CREATE TABLE IF NOT EXISTS proposals (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        project_id INTEGER REFERENCES projects(id),
        priority TEXT NOT NULL,
        category TEXT NOT NULL,
        title TEXT NOT NULL,
        description TEXT NOT NULL,
        action_items TEXT NOT NULL,
        created_at TEXT DEFAULT (datetime('now')),
        status TEXT DEFAULT 'pending',
        revenue_impact REAL
      );

      CREATE TABLE IF NOT EXISTS sentinel_state (
        key TEXT PRIMARY KEY,
        value TEXT,
        updated_at TEXT DEFAULT (datetime('now'))
      );

      CREATE INDEX IF NOT EXISTS idx_changes_unprocessed ON change_records(processed) WHERE processed = 0;
      CREATE INDEX IF NOT EXISTS idx_proposals_pending ON proposals(status) WHERE status = 'pending';
    `);
  }

  /**
   * Get all indexed projects
   */
  getAllProjects(): Project[] {
    return this.db.prepare('SELECT * FROM projects ORDER BY file_count DESC').all() as Project[];
  }

  /**
   * Get project by name
   */
  getProject(name: string): Project | undefined {
    return this.db.prepare('SELECT * FROM projects WHERE name LIKE ?').get(`%${name}%`) as Project | undefined;
  }

  /**
   * Get project by path
   */
  getProjectByPath(path: string): Project | undefined {
    return this.db.prepare('SELECT * FROM projects WHERE path = ?').get(path) as Project | undefined;
  }

  /**
   * Get files for a project
   */
  getProjectFiles(projectId: number): WikiFile[] {
    return this.db.prepare('SELECT * FROM files WHERE project_id = ?').all(projectId) as WikiFile[];
  }

  /**
   * Record a detected change
   */
  recordChange(change: Omit<ChangeRecord, 'id'>): number {
    const stmt = this.db.prepare(`
      INSERT OR IGNORE INTO change_records (project_id, change_type, file_path, detected_at, processed)
      VALUES (?, ?, ?, ?, ?)
    `);
    const result = stmt.run(
      change.project_id,
      change.change_type,
      change.file_path,
      change.detected_at || new Date().toISOString(),
      change.processed || 0
    );
    return result.lastInsertRowid as number;
  }

  /**
   * Get unprocessed changes
   */
  getUnprocessedChanges(limit = 100): ChangeRecord[] {
    return this.db.prepare(`
      SELECT * FROM change_records
      WHERE processed = 0
      ORDER BY detected_at DESC
      LIMIT ?
    `).all(limit) as ChangeRecord[];
  }

  /**
   * Mark changes as processed
   */
  markChangesProcessed(changeIds: number[], proposalId?: number): void {
    const stmt = this.db.prepare(`
      UPDATE change_records
      SET processed = 1, proposal_id = ?
      WHERE id = ?
    `);
    for (const id of changeIds) {
      stmt.run(proposalId || null, id);
    }
  }

  /**
   * Create a proposal
   */
  createProposal(proposal: Omit<Proposal, 'id'>): number {
    const stmt = this.db.prepare(`
      INSERT INTO proposals (project_id, priority, category, title, description, action_items, status, revenue_impact)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    `);
    const result = stmt.run(
      proposal.project_id,
      proposal.priority,
      proposal.category,
      proposal.title,
      proposal.description,
      proposal.action_items,
      proposal.status || 'pending',
      proposal.revenue_impact || null
    );
    return result.lastInsertRowid as number;
  }

  /**
   * Get pending proposals
   */
  getPendingProposals(limit = 20): (Proposal & { project_name: string })[] {
    return this.db.prepare(`
      SELECT p.*, pr.name as project_name
      FROM proposals p
      JOIN projects pr ON p.project_id = pr.id
      WHERE p.status = 'pending'
      ORDER BY
        CASE p.priority
          WHEN 'critical' THEN 1
          WHEN 'high' THEN 2
          WHEN 'medium' THEN 3
          ELSE 4
        END,
        p.created_at DESC
      LIMIT ?
    `).all(limit) as (Proposal & { project_name: string })[];
  }

  /**
   * Update proposal status
   */
  updateProposalStatus(id: number, status: Proposal['status']): void {
    this.db.prepare('UPDATE proposals SET status = ? WHERE id = ?').run(status, id);
  }

  /**
   * Get/set sentinel state
   */
  getState(key: string): string | null {
    const row = this.db.prepare('SELECT value FROM sentinel_state WHERE key = ?').get(key) as { value: string } | undefined;
    return row?.value || null;
  }

  setState(key: string, value: string): void {
    this.db.prepare(`
      INSERT OR REPLACE INTO sentinel_state (key, value, updated_at)
      VALUES (?, ?, datetime('now'))
    `).run(key, value);
  }

  /**
   * Get projects needing attention (no context, many files, or stale index)
   */
  getProjectsNeedingAttention(): Project[] {
    return this.db.prepare(`
      SELECT * FROM projects
      WHERE has_context = 0
         OR file_count > 100
         OR datetime(last_indexed_at) < datetime('now', '-7 days')
      ORDER BY file_count DESC
      LIMIT 20
    `).all() as Project[];
  }

  /**
   * Get statistics
   */
  getStats(): {
    totalProjects: number;
    projectsWithContext: number;
    totalFiles: number;
    pendingChanges: number;
    pendingProposals: number;
  } {
    const stats = this.db.prepare(`
      SELECT
        (SELECT COUNT(*) FROM projects) as totalProjects,
        (SELECT COUNT(*) FROM projects WHERE has_context = 1) as projectsWithContext,
        (SELECT COALESCE(SUM(file_count), 0) FROM projects) as totalFiles,
        (SELECT COUNT(*) FROM change_records WHERE processed = 0) as pendingChanges,
        (SELECT COUNT(*) FROM proposals WHERE status = 'pending') as pendingProposals
    `).get() as any;
    return stats;
  }

  close(): void {
    this.db.close();
  }
}

export default WikiDatabase;
