/**
 * Proposal Generator
 *
 * Generates actionable proposals from analysis results
 * and formats them for human review
 */

import WikiDatabase, { Proposal, Project } from './wiki-db.js';
import { AnalysisResult } from './analyzer.js';

export interface FormattedProposal {
  id: number;
  project: string;
  priority: string;
  category: string;
  title: string;
  description: string;
  actions: string[];
  revenue_impact: string;
  created: string;
}

export class Proposer {
  private db: WikiDatabase;

  constructor(db: WikiDatabase) {
    this.db = db;
  }

  /**
   * Generate proposals from analysis results
   */
  generateProposals(results: AnalysisResult[]): Proposal[] {
    const proposals: Proposal[] = [];

    for (const result of results) {
      // Skip if no recommendations
      if (result.recommendations.length === 0) continue;

      const proposal: Proposal = {
        project_id: result.project.id,
        priority: result.priority,
        category: result.category,
        title: this.generateTitle(result),
        description: this.generateDescription(result),
        action_items: JSON.stringify(result.recommendations),
        created_at: new Date().toISOString(),
        status: 'pending',
        revenue_impact: result.revenue_impact,
      };

      // Store in database
      const id = this.db.createProposal(proposal);
      proposals.push({ ...proposal, id });
    }

    return proposals;
  }

  /**
   * Generate a descriptive title
   */
  private generateTitle(result: AnalysisResult): string {
    const { project, category, findings } = result;

    switch (category) {
      case 'configuration':
        return `Configuration changes in ${project.name}`;
      case 'dependencies':
        return `Dependency updates needed for ${project.name}`;
      case 'refactoring':
        return `Major refactoring detected in ${project.name}`;
      case 'health':
        return `Health check: ${project.name}`;
      default:
        return `Updates for ${project.name}`;
    }
  }

  /**
   * Generate detailed description
   */
  private generateDescription(result: AnalysisResult): string {
    const lines: string[] = [];

    // Add findings
    lines.push('## Findings\n');
    for (const finding of result.findings) {
      lines.push(`- ${finding}`);
    }

    // Add revenue context if available
    if (result.revenue_impact && result.revenue_impact > 0) {
      lines.push(`\n## Revenue Impact\n`);
      lines.push(`Potential: $${result.revenue_impact.toLocaleString()}/month`);
    }

    return lines.join('\n');
  }

  /**
   * Get pending proposals formatted for display
   */
  getPendingProposals(): FormattedProposal[] {
    const raw = this.db.getPendingProposals();

    return raw.map(p => ({
      id: p.id!,
      project: p.project_name,
      priority: this.formatPriority(p.priority),
      category: p.category,
      title: p.title,
      description: p.description,
      actions: JSON.parse(p.action_items),
      revenue_impact: p.revenue_impact ? `$${p.revenue_impact.toLocaleString()}/mo` : 'N/A',
      created: new Date(p.created_at).toLocaleDateString(),
    }));
  }

  /**
   * Format priority with emoji
   */
  private formatPriority(priority: string): string {
    switch (priority) {
      case 'critical': return '🔴 Critical';
      case 'high': return '🟠 High';
      case 'medium': return '🟡 Medium';
      case 'low': return '🟢 Low';
      default: return priority;
    }
  }

  /**
   * Accept a proposal (mark for implementation)
   */
  acceptProposal(id: number): void {
    this.db.updateProposalStatus(id, 'accepted');
  }

  /**
   * Reject a proposal
   */
  rejectProposal(id: number): void {
    this.db.updateProposalStatus(id, 'rejected');
  }

  /**
   * Mark proposal as completed
   */
  completeProposal(id: number): void {
    this.db.updateProposalStatus(id, 'completed');
  }

  /**
   * Generate markdown report of pending proposals
   */
  generateReport(): string {
    const proposals = this.getPendingProposals();
    const stats = this.db.getStats();

    const lines: string[] = [
      '# Wiki Sentinel Report',
      '',
      `Generated: ${new Date().toISOString()}`,
      '',
      '## Summary',
      '',
      `- **Total Projects**: ${stats.totalProjects}`,
      `- **Projects with Context**: ${stats.projectsWithContext}`,
      `- **Pending Changes**: ${stats.pendingChanges}`,
      `- **Pending Proposals**: ${stats.pendingProposals}`,
      '',
      '## Pending Proposals',
      '',
    ];

    if (proposals.length === 0) {
      lines.push('No pending proposals. All systems nominal.');
    } else {
      // Group by priority
      const byPriority = {
        critical: proposals.filter(p => p.priority.includes('Critical')),
        high: proposals.filter(p => p.priority.includes('High')),
        medium: proposals.filter(p => p.priority.includes('Medium')),
        low: proposals.filter(p => p.priority.includes('Low')),
      };

      for (const [priority, group] of Object.entries(byPriority)) {
        if (group.length === 0) continue;

        lines.push(`### ${priority.charAt(0).toUpperCase() + priority.slice(1)} Priority`);
        lines.push('');

        for (const proposal of group) {
          lines.push(`#### ${proposal.title}`);
          lines.push(`**Project**: ${proposal.project} | **Category**: ${proposal.category} | **Revenue**: ${proposal.revenue_impact}`);
          lines.push('');
          lines.push(proposal.description);
          lines.push('');
          lines.push('**Actions**:');
          for (const action of proposal.actions) {
            lines.push(`- [ ] ${action}`);
          }
          lines.push('');
        }
      }
    }

    return lines.join('\n');
  }

  /**
   * Generate concise summary for terminal display
   */
  generateSummary(): string {
    const proposals = this.getPendingProposals();
    const stats = this.db.getStats();

    const lines: string[] = [
      '',
      '┌─────────────────────────────────────────────────────────┐',
      '│  WIKI SENTINEL - Codebase Intelligence Report          │',
      '└─────────────────────────────────────────────────────────┘',
      '',
      `  Projects: ${stats.totalProjects} indexed | ${stats.projectsWithContext} with context`,
      `  Changes:  ${stats.pendingChanges} pending | ${stats.pendingProposals} proposals`,
      '',
    ];

    if (proposals.length > 0) {
      lines.push('  ═══ TOP PROPOSALS ═══');
      lines.push('');

      // Show top 5 proposals
      for (const proposal of proposals.slice(0, 5)) {
        lines.push(`  ${proposal.priority}`);
        lines.push(`  └─ ${proposal.title}`);
        lines.push(`     Project: ${proposal.project} | Revenue: ${proposal.revenue_impact}`);
        lines.push('');
      }

      if (proposals.length > 5) {
        lines.push(`  ... and ${proposals.length - 5} more proposals`);
        lines.push('');
      }
    } else {
      lines.push('  ✓ All systems nominal - no proposals pending');
      lines.push('');
    }

    lines.push('  Run `wiki sentinel report` for full details');
    lines.push('');

    return lines.join('\n');
  }
}

export default Proposer;
