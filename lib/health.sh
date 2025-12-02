#!/bin/bash
#═══════════════════════════════════════════════════════════════════════════════
#  CLAUDE CODE WIKI - Health Check & Self-Improvement Module
#  Diagnostics, monitoring, and auto-repair
#═══════════════════════════════════════════════════════════════════════════════

# Ensure common is loaded
[[ -z "$WIKI_VERSION" ]] && source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

#───────────────────────────────────────────────────────────────────────────────
# Health Check
#───────────────────────────────────────────────────────────────────────────────

wiki_health_check() {
    wiki_print_header "Wiki System Health Check"

    local issues=0
    local warnings=0
    local checks_passed=0

    # Check 1: Required commands
    wiki_print_section "Required Commands"
    for cmd in sqlite3 find basename dirname; do
        if command -v "$cmd" &> /dev/null; then
            echo -e "  ${GREEN}✓${NC} $cmd"
            ((checks_passed++))
        else
            echo -e "  ${RED}✗${NC} $cmd - MISSING"
            ((issues++))
        fi
    done

    # Check 2: Optional commands
    wiki_print_section "Optional Commands"
    for cmd in jq tree rg; do
        if command -v "$cmd" &> /dev/null; then
            echo -e "  ${GREEN}✓${NC} $cmd"
        else
            echo -e "  ${YELLOW}○${NC} $cmd - not installed (optional)"
            ((warnings++))
        fi
    done

    # Check 3: Directory structure
    wiki_print_section "Directory Structure"
    for dir in "$WIKI_CONFIG_DIR" "$WIKI_DATA_DIR" "$WIKI_STATE_DIR" "$WIKI_CACHE_DIR"; do
        if [[ -d "$dir" ]]; then
            echo -e "  ${GREEN}✓${NC} $dir"
            ((checks_passed++))
        else
            echo -e "  ${YELLOW}○${NC} $dir - will be created"
            ((warnings++))
        fi
    done

    # Check 4: Database
    wiki_print_section "Database"
    if [[ -f "$WIKI_DB" ]]; then
        local size=$(wiki_file_size "$WIKI_DB")
        local project_count=$(wiki_db_query "SELECT COUNT(*) FROM projects;" 2>/dev/null || echo "0")
        local file_count=$(wiki_db_query "SELECT COUNT(*) FROM files;" 2>/dev/null || echo "0")
        echo -e "  ${GREEN}✓${NC} Database exists ($size bytes)"
        echo -e "  ${GREEN}✓${NC} Projects indexed: $project_count"
        echo -e "  ${GREEN}✓${NC} Files indexed: $file_count"
        ((checks_passed+=3))

        # Check for stale data
        local stale_count=$(wiki_db_query "SELECT COUNT(*) FROM projects WHERE last_indexed_at < datetime('now', '-7 days');" 2>/dev/null || echo "0")
        if [[ "$stale_count" -gt 0 ]]; then
            echo -e "  ${YELLOW}○${NC} $stale_count projects need re-indexing"
            ((warnings++))
        fi
    else
        echo -e "  ${YELLOW}○${NC} Database not initialized"
        ((warnings++))
    fi

    # Check 5: Config file
    wiki_print_section "Configuration"
    if [[ -f "$WIKI_CONFIG_FILE" ]]; then
        echo -e "  ${GREEN}✓${NC} Config file exists"
        ((checks_passed++))

        if command -v jq &> /dev/null; then
            if jq empty "$WIKI_CONFIG_FILE" 2>/dev/null; then
                echo -e "  ${GREEN}✓${NC} Config is valid JSON"
                ((checks_passed++))
            else
                echo -e "  ${RED}✗${NC} Config has invalid JSON"
                ((issues++))
            fi
        fi
    else
        echo -e "  ${YELLOW}○${NC} No config file (using defaults)"
        ((warnings++))
    fi

    # Check 6: Lock file
    wiki_print_section "System State"
    if [[ -f "$WIKI_LOCK_FILE" ]]; then
        local lock_pid=$(cat "$WIKI_LOCK_FILE" 2>/dev/null)
        if kill -0 "$lock_pid" 2>/dev/null; then
            echo -e "  ${YELLOW}○${NC} Lock held by PID $lock_pid"
            ((warnings++))
        else
            echo -e "  ${RED}✗${NC} Stale lock file (PID $lock_pid not running)"
            ((issues++))
        fi
    else
        echo -e "  ${GREEN}✓${NC} No active locks"
        ((checks_passed++))
    fi

    # Check 7: Log file
    if [[ -f "$WIKI_LOG_FILE" ]]; then
        local log_size=$(wiki_file_size "$WIKI_LOG_FILE")
        if [[ $log_size -gt 10485760 ]]; then  # 10MB
            echo -e "  ${YELLOW}○${NC} Log file large ($log_size bytes)"
            ((warnings++))
        else
            echo -e "  ${GREEN}✓${NC} Log file OK ($log_size bytes)"
            ((checks_passed++))
        fi

        # Check for recent errors
        local recent_errors=$(tail -100 "$WIKI_LOG_FILE" 2>/dev/null | grep -c "\[ERROR\]" || echo "0")
        recent_errors=$(echo "$recent_errors" | tr -d '[:space:]')
        if [[ "$recent_errors" -gt 0 ]]; then
            echo -e "  ${YELLOW}○${NC} $recent_errors recent errors in log"
            ((warnings++))
        fi
    fi

    # Check 8: Claude integration
    wiki_print_section "Claude Code Integration"
    if [[ -d "$CLAUDE_DIR" ]]; then
        echo -e "  ${GREEN}✓${NC} Claude directory exists"
        ((checks_passed++))
    else
        echo -e "  ${YELLOW}○${NC} Claude directory not found"
        ((warnings++))
    fi

    if [[ -d "$CLAUDE_COMMANDS_DIR" ]]; then
        local cmd_count=$(find "$CLAUDE_COMMANDS_DIR" -name "wiki*.md" 2>/dev/null | wc -l | tr -d ' ')
        if [[ "$cmd_count" -gt 0 ]]; then
            echo -e "  ${GREEN}✓${NC} $cmd_count wiki commands installed"
            ((checks_passed++))
        else
            echo -e "  ${YELLOW}○${NC} No wiki commands installed"
            ((warnings++))
        fi
    fi

    # Summary
    wiki_print_section "Summary"
    echo -e "  Checks passed: ${GREEN}$checks_passed${NC}"
    echo -e "  Warnings: ${YELLOW}$warnings${NC}"
    echo -e "  Issues: ${RED}$issues${NC}"
    echo ""

    if [[ $issues -gt 0 ]]; then
        echo -e "  Status: ${RED}UNHEALTHY${NC}"
        echo -e "  Run ${CYAN}wiki fix${NC} to attempt auto-repair"
        return 1
    elif [[ $warnings -gt 3 ]]; then
        echo -e "  Status: ${YELLOW}DEGRADED${NC}"
        echo -e "  Run ${CYAN}wiki fix${NC} for improvements"
        return 0
    else
        echo -e "  Status: ${GREEN}HEALTHY${NC}"
        return 0
    fi
}

#───────────────────────────────────────────────────────────────────────────────
# Auto-Fix
#───────────────────────────────────────────────────────────────────────────────

wiki_auto_fix() {
    wiki_print_header "Auto-Fix Wiki System"

    local fixed=0

    # Fix 1: Create missing directories
    wiki_print_section "Directories"
    for dir in "$WIKI_CONFIG_DIR" "$WIKI_DATA_DIR" "$WIKI_STATE_DIR" "$WIKI_CACHE_DIR"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            echo -e "  ${GREEN}✓${NC} Created $dir"
            ((fixed++))
        fi
    done

    # Fix 2: Remove stale lock
    wiki_print_section "Lock Files"
    if [[ -f "$WIKI_LOCK_FILE" ]]; then
        local lock_pid=$(cat "$WIKI_LOCK_FILE" 2>/dev/null)
        if ! kill -0 "$lock_pid" 2>/dev/null; then
            rm -f "$WIKI_LOCK_FILE"
            echo -e "  ${GREEN}✓${NC} Removed stale lock file"
            ((fixed++))
        fi
    else
        echo -e "  ${CYAN}○${NC} No lock issues"
    fi

    # Fix 3: Initialize database if missing
    wiki_print_section "Database"
    if [[ ! -f "$WIKI_DB" ]]; then
        wiki_db_init
        echo -e "  ${GREEN}✓${NC} Initialized database"
        ((fixed++))
    else
        # Vacuum to optimize
        sqlite3 "$WIKI_DB" "VACUUM;" 2>/dev/null && echo -e "  ${GREEN}✓${NC} Optimized database"
    fi

    # Fix 4: Create default config if missing
    wiki_print_section "Configuration"
    if [[ ! -f "$WIKI_CONFIG_FILE" ]]; then
        wiki_save_config
        echo -e "  ${GREEN}✓${NC} Created default config"
        ((fixed++))
    fi

    # Fix 5: Rotate large log file
    wiki_print_section "Logs"
    if [[ -f "$WIKI_LOG_FILE" ]]; then
        local log_size=$(wiki_file_size "$WIKI_LOG_FILE")
        if [[ $log_size -gt 10485760 ]]; then
            mv "$WIKI_LOG_FILE" "$WIKI_LOG_FILE.old"
            echo -e "  ${GREEN}✓${NC} Rotated large log file"
            ((fixed++))
        fi
    fi

    # Fix 6: Clean orphaned files from database
    wiki_print_section "Database Integrity"
    local orphans=$(wiki_db_query "SELECT COUNT(*) FROM files WHERE project_id NOT IN (SELECT id FROM projects);" 2>/dev/null || echo "0")
    if [[ "$orphans" -gt 0 ]]; then
        wiki_db_query "DELETE FROM files WHERE project_id NOT IN (SELECT id FROM projects);"
        echo -e "  ${GREEN}✓${NC} Removed $orphans orphaned file records"
        ((fixed++))
    fi

    # Fix 7: Remove projects with invalid paths
    local invalid=$(wiki_db_query "SELECT name FROM projects;" 2>/dev/null | while read -r name; do
        local path=$(wiki_db_query "SELECT path FROM projects WHERE name='$name';")
        [[ ! -d "$path" ]] && echo "$name"
    done | wc -l | tr -d ' ')

    if [[ "$invalid" -gt 0 ]]; then
        wiki_db_query "DELETE FROM projects WHERE path NOT IN (SELECT path FROM projects WHERE 1=0);" 2>/dev/null
        # Actually delete invalid
        wiki_db_query "SELECT name, path FROM projects;" 2>/dev/null | while IFS='|' read -r name path; do
            if [[ ! -d "$path" ]]; then
                wiki_db_query "DELETE FROM projects WHERE name='$name';"
                echo -e "  ${GREEN}✓${NC} Removed invalid project: $name"
                ((fixed++))
            fi
        done
    fi

    # Fix 8: Install Claude commands if missing
    wiki_print_section "Claude Integration"
    if [[ -d "$CLAUDE_COMMANDS_DIR" ]]; then
        local needs_install=0
        for cmd in wiki-scan wiki-find wiki-health; do
            [[ ! -f "$CLAUDE_COMMANDS_DIR/$cmd.md" ]] && needs_install=1
        done

        if [[ $needs_install -eq 1 ]]; then
            wiki_install_commands
            echo -e "  ${GREEN}✓${NC} Installed missing Claude commands"
            ((fixed++))
        else
            echo -e "  ${CYAN}○${NC} Commands already installed"
        fi
    fi

    wiki_print_section "Summary"
    echo -e "  Fixed: ${GREEN}$fixed${NC} issues"
    echo ""

    if [[ $fixed -gt 0 ]]; then
        wiki_info "Run 'wiki health' to verify fixes"
    fi
}

#───────────────────────────────────────────────────────────────────────────────
# Install Claude Commands
#───────────────────────────────────────────────────────────────────────────────

wiki_install_commands() {
    mkdir -p "$CLAUDE_COMMANDS_DIR"

    # wiki-scan command
    cat > "$CLAUDE_COMMANDS_DIR/wiki-scan.md" << 'EOF'
# Wiki Scan

Index all projects in configured directories.

```bash
wiki scan
```

This updates the project database with:
- Project names and paths
- Project types (nextjs, firebase, python, etc.)
- File counts and primary languages
- Context file detection
EOF

    # wiki-find command
    cat > "$CLAUDE_COMMANDS_DIR/wiki-find.md" << 'EOF'
# Wiki Find

Search across all indexed projects.

**Usage:** `wiki find <query>`

**Arguments:**
- `$ARGUMENTS` - Search query

```bash
wiki find "$ARGUMENTS"
```

Search matches:
- File names
- File paths
- Project names
EOF

    # wiki-health command
    cat > "$CLAUDE_COMMANDS_DIR/wiki-health.md" << 'EOF'
# Wiki Health Check

Run diagnostics on the wiki system.

```bash
wiki health
```

Checks:
- Required dependencies
- Database integrity
- Configuration validity
- System state
EOF

    # wiki-prepare command
    cat > "$CLAUDE_COMMANDS_DIR/wiki-prepare.md" << 'EOF'
# Wiki Prepare Context

Generate AI context manifest for a project.

**Usage:** `wiki prepare <path>`

**Arguments:**
- `$ARGUMENTS` - Project path (default: current directory)

```bash
wiki prepare "$ARGUMENTS"
```

Creates GEMINI_CONTEXT.md with:
- Project structure
- Dependencies
- Architecture notes
- Entry points
EOF

    wiki_debug "Installed Claude commands to $CLAUDE_COMMANDS_DIR"
}

#───────────────────────────────────────────────────────────────────────────────
# Diagnostic Report
#───────────────────────────────────────────────────────────────────────────────

wiki_diagnostic_report() {
    wiki_print_header "Diagnostic Report"

    echo "Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    echo "Wiki Version: $WIKI_VERSION"
    echo "Platform: $WIKI_PLATFORM"
    echo ""

    wiki_print_section "Environment"
    echo "HOME: $HOME"
    echo "SHELL: $SHELL"
    echo "PATH entries: $(echo "$PATH" | tr ':' '\n' | wc -l | tr -d ' ')"
    echo ""

    wiki_print_section "Database Stats"
    if [[ -f "$WIKI_DB" ]]; then
        echo "Size: $(wiki_file_size "$WIKI_DB") bytes"
        echo "Projects: $(wiki_db_query "SELECT COUNT(*) FROM projects;")"
        echo "Files: $(wiki_db_query "SELECT COUNT(*) FROM files;")"
        echo ""

        echo "Projects by type:"
        wiki_db_query "SELECT type, COUNT(*) as count FROM projects GROUP BY type ORDER BY count DESC;"
        echo ""

        echo "Top languages:"
        wiki_db_query "SELECT primary_language, COUNT(*) as count FROM projects GROUP BY primary_language ORDER BY count DESC LIMIT 5;"
    else
        echo "Database not initialized"
    fi

    wiki_print_section "Recent Log Entries"
    if [[ -f "$WIKI_LOG_FILE" ]]; then
        tail -20 "$WIKI_LOG_FILE"
    else
        echo "No log file"
    fi
}
