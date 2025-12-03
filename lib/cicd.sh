#!/bin/bash
#═══════════════════════════════════════════════════════════════════════════════
#  CLAUDE CODE WIKI - CI/CD Automation Library
#  Commands for automated documentation updates in CI/CD pipelines
#═══════════════════════════════════════════════════════════════════════════════

# Source common library if not already loaded
if [[ -z "$WIKI_VERSION" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$SCRIPT_DIR/common.sh"
fi

#───────────────────────────────────────────────────────────────────────────────
# Configuration Parser
#───────────────────────────────────────────────────────────────────────────────

# Parse codewiki.yaml configuration
wiki_parse_config() {
    local config_file="${1:-codewiki.yaml}"

    if [[ ! -f "$config_file" ]]; then
        wiki_warn "No codewiki.yaml found, using defaults"
        return 1
    fi

    # Use Python for YAML parsing (more reliable than bash)
    python3 << EOF
import yaml
import json
import sys

try:
    with open("$config_file", 'r') as f:
        config = yaml.safe_load(f)
    print(json.dumps(config))
except Exception as e:
    print(json.dumps({"error": str(e)}), file=sys.stderr)
    sys.exit(1)
EOF
}

#───────────────────────────────────────────────────────────────────────────────
# Diff Scan - Identify changed files
#───────────────────────────────────────────────────────────────────────────────

wiki_diff_scan() {
    local ref="${1:-HEAD~1}"
    local target_ref="${2:-HEAD}"
    local output_format="${3:-json}"

    wiki_print_header "Diff Scan: $ref..$target_ref"

    # Get changed files
    local added=$(git diff --name-only --diff-filter=A "$ref" "$target_ref" 2>/dev/null)
    local modified=$(git diff --name-only --diff-filter=M "$ref" "$target_ref" 2>/dev/null)
    local deleted=$(git diff --name-only --diff-filter=D "$ref" "$target_ref" 2>/dev/null)

    # Count changes (handle empty strings)
    local added_count=0
    local modified_count=0
    local deleted_count=0

    [[ -n "$added" ]] && added_count=$(echo "$added" | wc -l | tr -d ' ')
    [[ -n "$modified" ]] && modified_count=$(echo "$modified" | wc -l | tr -d ' ')
    [[ -n "$deleted" ]] && deleted_count=$(echo "$deleted" | wc -l | tr -d ' ')

    local total=$((added_count + modified_count + deleted_count))

    if [[ "$output_format" == "json" ]]; then
        # Output as JSON for programmatic use
        cat << EOF
{
  "ref": "$ref",
  "target": "$target_ref",
  "summary": {
    "added": $added_count,
    "modified": $modified_count,
    "deleted": $deleted_count,
    "total": $total
  },
  "files": {
    "added": $(echo "$added" | jq -R . | jq -s . 2>/dev/null || echo "[]"),
    "modified": $(echo "$modified" | jq -R . | jq -s . 2>/dev/null || echo "[]"),
    "deleted": $(echo "$deleted" | jq -R . | jq -s . 2>/dev/null || echo "[]")
  }
}
EOF
    else
        # Human-readable output
        echo ""
        echo -e "${GREEN}Added ($added_count):${NC}"
        [[ -n "$added" ]] && echo "$added" | sed 's/^/  + /'

        echo ""
        echo -e "${YELLOW}Modified ($modified_count):${NC}"
        [[ -n "$modified" ]] && echo "$modified" | sed 's/^/  ~ /'

        echo ""
        echo -e "${RED}Deleted ($deleted_count):${NC}"
        [[ -n "$deleted" ]] && echo "$deleted" | sed 's/^/  - /'

        echo ""
        echo -e "${BOLD}Total: $total files changed${NC}"
    fi
}

#───────────────────────────────────────────────────────────────────────────────
# Generate for specific files
#───────────────────────────────────────────────────────────────────────────────

wiki_generate_files() {
    local files="$1"
    local output_dir="${2:-docs/generated}"
    local dry_run="${3:-false}"

    wiki_print_header "Generating Documentation"

    if [[ -z "$files" ]]; then
        wiki_error "No files specified"
        return 1
    fi

    # Ensure output directory exists
    if [[ "$dry_run" != "true" ]]; then
        mkdir -p "$output_dir"
    fi

    local count=0
    local success=0
    local failed=0

    # Process each file
    for file in $files; do
        ((count++))

        # Skip if file doesn't exist (might be deleted)
        if [[ ! -f "$file" ]]; then
            wiki_warn "Skipping $file (not found)"
            continue
        fi

        # Determine output path
        local basename=$(basename "$file")
        local dirname=$(dirname "$file")
        local output_file="$output_dir/${dirname//\//_}_${basename%.}_doc.md"

        echo -e "  [$count] Processing: ${CYAN}$file${NC}"

        if [[ "$dry_run" == "true" ]]; then
            echo "      Would generate: $output_file"
            ((success++))
            continue
        fi

        # Generate documentation using the context generator
        if wiki_generate_file_doc "$file" "$output_file"; then
            echo -e "      ${GREEN}Generated: $output_file${NC}"
            ((success++))
        else
            echo -e "      ${RED}Failed${NC}"
            ((failed++))
        fi
    done

    echo ""
    echo -e "${BOLD}Summary:${NC} $success succeeded, $failed failed out of $count files"

    return $((failed > 0 ? 1 : 0))
}

# Generate documentation for a single file
wiki_generate_file_doc() {
    local input_file="$1"
    local output_file="$2"

    # Read file content
    local content=$(cat "$input_file")
    local filename=$(basename "$input_file")
    local extension="${filename##*.}"

    # Generate basic documentation
    cat > "$output_file" << EOF
# Documentation: $filename

**Source:** \`$input_file\`
**Type:** $extension
**Generated:** $(date -Iseconds)

## Overview

This file is part of the project codebase.

## Contents

\`\`\`$extension
$(head -100 "$input_file")
\`\`\`

$(if [[ $(wc -l < "$input_file") -gt 100 ]]; then echo "*... truncated ($(wc -l < "$input_file") total lines)*"; fi)

## Analysis

*Auto-generated documentation. For detailed analysis, use \`wiki prepare\` with AI model.*

---
*Generated by Claude Code Wiki CI/CD*
EOF

    return 0
}

#───────────────────────────────────────────────────────────────────────────────
# Commit Documentation
#───────────────────────────────────────────────────────────────────────────────

wiki_commit_docs() {
    local message="${1:-docs: auto-update wiki documentation}"
    local author="${2:-Wiki Bot <wiki@codewiki.dev>}"
    local docs_dir="${3:-docs/generated}"
    local dry_run="${4:-false}"

    wiki_print_header "Committing Documentation"

    # Check if there are changes to commit
    if ! git diff --quiet "$docs_dir" 2>/dev/null && ! git diff --cached --quiet "$docs_dir" 2>/dev/null; then
        wiki_info "No documentation changes to commit"
        return 0
    fi

    # Check for untracked files in docs dir
    local untracked=$(git ls-files --others --exclude-standard "$docs_dir" 2>/dev/null)
    local modified=$(git diff --name-only "$docs_dir" 2>/dev/null)

    if [[ -z "$untracked" && -z "$modified" ]]; then
        wiki_info "No documentation changes to commit"
        return 0
    fi

    echo -e "Files to commit:"
    [[ -n "$untracked" ]] && echo "$untracked" | sed 's/^/  + /'
    [[ -n "$modified" ]] && echo "$modified" | sed 's/^/  ~ /'

    if [[ "$dry_run" == "true" ]]; then
        wiki_info "[DRY RUN] Would commit with message: $message"
        return 0
    fi

    # Stage and commit
    git add "$docs_dir"

    # Commit with author override
    if git commit --author="$author" -m "$message" -m "🤖 Generated with Claude Code Wiki"; then
        wiki_info "Documentation committed successfully"

        # Show commit hash
        local commit_hash=$(git rev-parse HEAD)
        echo -e "  Commit: ${CYAN}$commit_hash${NC}"

        return 0
    else
        wiki_error "Failed to commit documentation"
        return 1
    fi
}

#───────────────────────────────────────────────────────────────────────────────
# Full CI/CD Pipeline
#───────────────────────────────────────────────────────────────────────────────

wiki_cicd_run() {
    local ref="${1:-HEAD~1}"
    local dry_run="${2:-false}"
    local config_file="${3:-codewiki.yaml}"

    wiki_print_header "Wiki CI/CD Pipeline"

    echo -e "Reference: ${CYAN}$ref${NC}"
    echo -e "Dry Run: ${CYAN}$dry_run${NC}"
    echo -e "Config: ${CYAN}$config_file${NC}"
    echo ""

    # Step 1: Diff scan
    echo -e "${BOLD}Step 1: Analyzing changes...${NC}"
    local diff_output=$(wiki_diff_scan "$ref" "HEAD" "json")

    local total=$(echo "$diff_output" | jq -r '.summary.total' 2>/dev/null || echo "0")

    if [[ "$total" == "0" ]]; then
        wiki_info "No relevant changes detected"
        return 0
    fi

    echo -e "  Found ${CYAN}$total${NC} changed files"
    echo ""

    # Step 2: Get files to process
    echo -e "${BOLD}Step 2: Identifying documentation targets...${NC}"
    local modified_files=$(echo "$diff_output" | jq -r '.files.modified[]' 2>/dev/null | tr '\n' ' ')
    local added_files=$(echo "$diff_output" | jq -r '.files.added[]' 2>/dev/null | tr '\n' ' ')
    local all_files="$modified_files $added_files"

    # Filter to relevant file types
    local relevant_files=""
    for file in $all_files; do
        case "$file" in
            *.ts|*.tsx|*.js|*.jsx|*.py|*.go|*.rs|*.java|*.md)
                relevant_files="$relevant_files $file"
                ;;
        esac
    done

    if [[ -z "$relevant_files" ]]; then
        wiki_info "No relevant files to document"
        return 0
    fi

    echo -e "  Processing:$relevant_files"
    echo ""

    # Step 3: Generate documentation
    echo -e "${BOLD}Step 3: Generating documentation...${NC}"
    wiki_generate_files "$relevant_files" "docs/generated" "$dry_run"
    echo ""

    # Step 4: Commit if not dry run
    if [[ "$dry_run" != "true" ]]; then
        echo -e "${BOLD}Step 4: Committing changes...${NC}"
        wiki_commit_docs
    else
        echo -e "${BOLD}Step 4: [DRY RUN] Skipping commit${NC}"
    fi

    echo ""
    wiki_info "CI/CD pipeline complete"
}

#───────────────────────────────────────────────────────────────────────────────
# Command Entry Points
#───────────────────────────────────────────────────────────────────────────────

cmd_diff_scan() {
    local ref="${1:-HEAD~1}"
    local format="${2:-text}"
    wiki_diff_scan "$ref" "HEAD" "$format"
}

cmd_generate_files() {
    local files="$*"
    wiki_generate_files "$files"
}

cmd_commit_docs() {
    local message="${1:-docs: auto-update wiki documentation}"
    wiki_commit_docs "$message"
}

cmd_cicd() {
    local subcmd="${1:-run}"
    shift 2>/dev/null || true

    case "$subcmd" in
        run)
            wiki_cicd_run "$@"
            ;;
        diff)
            cmd_diff_scan "$@"
            ;;
        generate)
            cmd_generate_files "$@"
            ;;
        commit)
            cmd_commit_docs "$@"
            ;;
        *)
            echo "Usage: wiki cicd <run|diff|generate|commit> [options]"
            echo ""
            echo "Commands:"
            echo "  run [ref] [--dry-run]     Run full CI/CD pipeline"
            echo "  diff [ref] [json|text]    Show changed files since ref"
            echo "  generate <files...>       Generate docs for specific files"
            echo "  commit [message]          Commit generated documentation"
            ;;
    esac
}
