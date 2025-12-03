/**
 * Intelligence Analyzer
 *
 * Analyzes changes and codebase state to identify opportunities,
 * blockers, and actionable improvements
 */

import { readFileSync, existsSync } from 'fs';
import { join, basename } from 'path';
import { parse as parseYaml } from 'yaml';
import WikiDatabase, { Project } from './wiki-db.js';
import { DetectedChange } from './detector.js';

export interface EcosystemProject {
  name: string;
  path: string;
  status: string;
  revenue_potential: string;
  priority: string;
  blockers?: string[];
  next_actions?: string[];
  metrics?: Record<string, any>;
}

export interface AnalysisResult {
  project: Project;
  priority: 'critical' | 'high' | 'medium' | 'low';
  category: string;
  findings: string[];
  recommendations: string[];
  revenue_impact?: number;
  context?: Record<string, any>;
}

export class Analyzer {
  private db: WikiDatabase;
  private ecosystemData?: Record<string, EcosystemProject>;
  private wikiDir: string;

  // Revenue potential mapping
  private static REVENUE_MAP: Record<string, number> = {
    '$10K/month': 10000,
    '$5K/month': 5000,
    '$3K/month': 3000,
    '$1K/month': 1000,
    '$500/month': 500,
    'TBD': 0,
  };

  constructor(db: WikiDatabase) {
    this.db = db;
    this.wikiDir = join(process.env.HOME || '', 'claude-code-wiki');
    this.loadEcosystemData();
  }

  /**
   * Load ecosystem.yaml for project prioritization
   */
  private loadEcosystemData(): void {
    const ecosystemPath = join(this.wikiDir, 'docs', 'ecosystem.yaml');
    if (!existsSync(ecosystemPath)) return;

    try {
      const content = readFileSync(ecosystemPath, 'utf-8');
      const data = parseYaml(content);

      this.ecosystemData = {};

      // Extract projects from ecosystem sections
      if (data.revenue_projects) {
        for (const proj of data.revenue_projects) {
          if (proj.name && proj.path) {
            this.ecosystemData[proj.path] = {
              name: proj.name,
              path: proj.path,
              status: proj.status || 'unknown',
              revenue_potential: proj.revenue_potential || 'TBD',
              priority: proj.priority || 'medium',
              blockers: proj.blockers || [],
              next_actions: proj.next_actions || [],
              metrics: proj.metrics || {},
            };
          }
        }
      }

      // Also check beachhead_projects
      if (data.beachhead_projects) {
        for (const proj of data.beachhead_projects) {
          if (proj.name && proj.path) {
            this.ecosystemData[proj.path] = {
              name: proj.name,
              path: proj.path,
              status: proj.status || 'unknown',
              revenue_potential: proj.revenue_potential || 'TBD',
              priority: proj.priority || 'high',
              blockers: proj.blockers || [],
              next_actions: proj.next_actions || [],
              metrics: proj.metrics || {},
            };
          }
        }
      }
    } catch (error) {
      console.error('[Analyzer] Failed to load ecosystem.yaml:', error);
    }
  }

  /**
   * Get revenue impact score for a project
   */
  getRevenueImpact(project: Project): number {
    const ecoProject = this.ecosystemData?.[project.path];
    if (!ecoProject) return 0;

    return Analyzer.REVENUE_MAP[ecoProject.revenue_potential] || 0;
  }

  /**
   * Analyze a batch of changes
   */
  analyzeChanges(changes: DetectedChange[]): AnalysisResult[] {
    const results: AnalysisResult[] = [];

    // Group changes by project
    const byProject = new Map<number, DetectedChange[]>();
    for (const change of changes) {
      const existing = byProject.get(change.project.id) || [];
      existing.push(change);
      byProject.set(change.project.id, existing);
    }

    // Analyze each project's changes
    for (const [projectId, projectChanges] of byProject) {
      const project = projectChanges[0].project;
      const result = this.analyzeProjectChanges(project, projectChanges);
      if (result) results.push(result);
    }

    // Sort by priority and revenue impact
    return results.sort((a, b) => {
      const priorityOrder = { critical: 0, high: 1, medium: 2, low: 3 };
      const priorityDiff = priorityOrder[a.priority] - priorityOrder[b.priority];
      if (priorityDiff !== 0) return priorityDiff;
      return (b.revenue_impact || 0) - (a.revenue_impact || 0);
    });
  }

  /**
   * Analyze changes for a single project
   */
  private analyzeProjectChanges(project: Project, changes: DetectedChange[]): AnalysisResult | null {
    const findings: string[] = [];
    const recommendations: string[] = [];
    let priority: 'critical' | 'high' | 'medium' | 'low' = 'low';
    let category = 'general';

    // Check for config changes
    const configChanges = changes.filter(c => c.category === 'config');
    if (configChanges.length > 0) {
      priority = 'high';
      category = 'configuration';
      findings.push(`${configChanges.length} config file(s) changed`);

      for (const change of configChanges) {
        const filename = basename(change.path);
        if (filename === 'package.json') {
          recommendations.push('Review dependency changes and run npm install');
        }
        if (filename === 'firebase.json') {
          recommendations.push('Verify Firebase deployment configuration');
        }
        if (filename === 'tsconfig.json') {
          recommendations.push('Rebuild TypeScript project to verify configuration');
        }
      }
    }

    // Check for dependency changes
    const depChanges = changes.filter(c => c.category === 'deps');
    if (depChanges.length > 0) {
      priority = 'high';
      category = 'dependencies';
      findings.push('Dependencies modified');
      recommendations.push('Run security audit: npm audit');
      recommendations.push('Update lock file: npm install');
    }

    // Check for code deletions (potential breaking changes)
    const deletions = changes.filter(c => c.type === 'deleted' && c.category === 'code');
    if (deletions.length > 3) {
      priority = 'critical';
      category = 'refactoring';
      findings.push(`${deletions.length} source files deleted - major refactoring detected`);
      recommendations.push('Update imports and references');
      recommendations.push('Run full test suite');
      recommendations.push('Update wiki documentation');
    }

    // Check for new files
    const additions = changes.filter(c => c.type === 'added' && c.category === 'code');
    if (additions.length > 5) {
      findings.push(`${additions.length} new source files added`);
      recommendations.push('Generate or update GEMINI_CONTEXT.md');
    }

    // Check ecosystem data for context
    const ecoProject = this.ecosystemData?.[project.path];
    if (ecoProject) {
      // If this is a revenue project, elevate priority
      if (ecoProject.priority === 'critical' || ecoProject.priority === 'high') {
        if (priority === 'low') priority = 'medium';
        if (priority === 'medium') priority = 'high';
      }

      // Add existing blockers as context
      if (ecoProject.blockers && ecoProject.blockers.length > 0) {
        findings.push(`Existing blockers: ${ecoProject.blockers.join(', ')}`);
      }
    }

    // Skip if no meaningful findings
    if (findings.length === 0) return null;

    return {
      project,
      priority,
      category,
      findings,
      recommendations,
      revenue_impact: this.getRevenueImpact(project),
    };
  }

  /**
   * Analyze overall ecosystem health
   */
  analyzeEcosystem(): AnalysisResult[] {
    const results: AnalysisResult[] = [];
    const projects = this.db.getAllProjects();

    for (const project of projects) {
      const findings: string[] = [];
      const recommendations: string[] = [];

      // Check for missing context
      if (!project.has_context) {
        findings.push('Missing AI context file (GEMINI_CONTEXT.md)');
        recommendations.push('Run: wiki generate-context ' + project.name);
      }

      // Check for stale index
      const lastIndexed = new Date(project.last_indexed_at);
      const daysAgo = (Date.now() - lastIndexed.getTime()) / (1000 * 60 * 60 * 24);
      if (daysAgo > 7) {
        findings.push(`Index is ${Math.floor(daysAgo)} days old`);
        recommendations.push('Run: wiki scan');
      }

      // Check ecosystem status
      const ecoProject = this.ecosystemData?.[project.path];
      if (ecoProject) {
        if (ecoProject.status === 'blocked') {
          findings.push(`Status: BLOCKED - ${ecoProject.blockers?.join(', ')}`);
        }
        if (ecoProject.next_actions && ecoProject.next_actions.length > 0) {
          recommendations.push(...ecoProject.next_actions);
        }
      }

      if (findings.length > 0) {
        results.push({
          project,
          priority: this.determinePriority(project, findings),
          category: 'health',
          findings,
          recommendations,
          revenue_impact: this.getRevenueImpact(project),
        });
      }
    }

    return results.sort((a, b) => (b.revenue_impact || 0) - (a.revenue_impact || 0));
  }

  /**
   * Determine priority based on project and findings
   */
  private determinePriority(project: Project, findings: string[]): 'critical' | 'high' | 'medium' | 'low' {
    const ecoProject = this.ecosystemData?.[project.path];

    // Critical: revenue project with blockers
    if (ecoProject && ecoProject.status === 'blocked' && this.getRevenueImpact(project) > 5000) {
      return 'critical';
    }

    // High: revenue project with issues
    if (this.getRevenueImpact(project) > 3000) {
      return 'high';
    }

    // Medium: any project with significant issues
    if (findings.length >= 3) {
      return 'medium';
    }

    return 'low';
  }

  /**
   * Generate summary statistics
   */
  getSummaryStats(): {
    totalProjects: number;
    healthyProjects: number;
    blockedProjects: number;
    potentialMRR: number;
    projectsByStatus: Record<string, number>;
  } {
    const projects = this.db.getAllProjects();
    let totalMRR = 0;
    const byStatus: Record<string, number> = {};
    let healthy = 0;
    let blocked = 0;

    for (const project of projects) {
      const ecoProject = this.ecosystemData?.[project.path];
      if (ecoProject) {
        totalMRR += this.getRevenueImpact(project);
        byStatus[ecoProject.status] = (byStatus[ecoProject.status] || 0) + 1;

        if (ecoProject.status === 'blocked') blocked++;
        if (ecoProject.status === 'deployed' || ecoProject.status === 'operational') healthy++;
      }
    }

    return {
      totalProjects: projects.length,
      healthyProjects: healthy,
      blockedProjects: blocked,
      potentialMRR: totalMRR,
      projectsByStatus: byStatus,
    };
  }
}

export default Analyzer;
