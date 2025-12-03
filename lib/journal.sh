#!/bin/bash
#═══════════════════════════════════════════════════════════════════════════════
#  JOURNAL LIBRARY - Self-Improving Development Journal Integration
#  Part of Claude Code Wiki
#═══════════════════════════════════════════════════════════════════════════════

# Source common library if not already loaded
if [[ -z "$WIKI_VERSION" ]]; then
    source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
fi

#───────────────────────────────────────────────────────────────────────────────
# Constants
#───────────────────────────────────────────────────────────────────────────────

SENTINEL_DIR="$WIKI_HOME/sentinel"
SENTINEL_BIN="$SENTINEL_DIR/dist/index.js"

#───────────────────────────────────────────────────────────────────────────────
# Helpers
#───────────────────────────────────────────────────────────────────────────────

# Check if sentinel is built
check_sentinel() {
    if [[ ! -f "$SENTINEL_BIN" ]]; then
        wiki_error "Sentinel not built. Run: cd $SENTINEL_DIR && npm run build"
        return 1
    fi
}

# Run sentinel command
run_sentinel() {
    check_sentinel || return 1
    node "$SENTINEL_BIN" "$@"
}

#───────────────────────────────────────────────────────────────────────────────
# Session Commands
#───────────────────────────────────────────────────────────────────────────────

# Start a development session
# Usage: wiki_session_start <project> <goal>
wiki_session_start() {
    local project="$1"
    local goal="$2"

    if [[ -z "$project" ]] || [[ -z "$goal" ]]; then
        wiki_error "Usage: wiki session start <project> <goal>"
        echo ""
        echo "Examples:"
        echo "  wiki session start myproject \"Fix auth bug\""
        echo "  wiki session start vetsorcery \"Add payment integration\""
        return 1
    fi

    run_sentinel session start "$project" "$goal"
}

# End a development session
# Usage: wiki_session_end <id> [summary]
wiki_session_end() {
    local id="$1"
    local summary="$2"

    if [[ -z "$id" ]]; then
        wiki_error "Usage: wiki session end <id> [summary]"
        return 1
    fi

    if [[ -n "$summary" ]]; then
        run_sentinel session end "$id" --summary "$summary"
    else
        run_sentinel session end "$id"
    fi
}

# List recent sessions
# Usage: wiki_session_list [limit]
wiki_session_list() {
    local limit="${1:-10}"
    run_sentinel session list --limit "$limit"
}

# Show session details
# Usage: wiki_session_show <id>
wiki_session_show() {
    local id="$1"

    if [[ -z "$id" ]]; then
        wiki_error "Usage: wiki session show <id>"
        return 1
    fi

    run_sentinel session show "$id"
}

#───────────────────────────────────────────────────────────────────────────────
# Journal Commands
#───────────────────────────────────────────────────────────────────────────────

# Show recent journal entries
# Usage: wiki_journal [limit] [type_filter]
wiki_journal() {
    local limit="${1:-30}"
    local type_filter="$2"

    if [[ -n "$type_filter" ]]; then
        run_sentinel journal --limit "$limit" --type "$type_filter"
    else
        run_sentinel journal --limit "$limit"
    fi
}

#───────────────────────────────────────────────────────────────────────────────
# Test Commands
#───────────────────────────────────────────────────────────────────────────────

# Start watching for test results
# Usage: wiki_tests_watch [project]
wiki_tests_watch() {
    local project="$1"

    if [[ -n "$project" ]]; then
        run_sentinel tests watch --project "$project"
    else
        run_sentinel tests watch
    fi
}

# Process a test result file
# Usage: wiki_tests_process <file>
wiki_tests_process() {
    local file="$1"

    if [[ -z "$file" ]]; then
        wiki_error "Usage: wiki tests process <file>"
        return 1
    fi

    if [[ ! -f "$file" ]]; then
        wiki_error "File not found: $file"
        return 1
    fi

    run_sentinel tests process "$file"
}

# Show flaky tests
# Usage: wiki_tests_flaky [limit]
wiki_tests_flaky() {
    local limit="${1:-20}"
    run_sentinel tests flaky --limit "$limit"
}

#───────────────────────────────────────────────────────────────────────────────
# Stats & Reflection Commands
#───────────────────────────────────────────────────────────────────────────────

# Show journal statistics
wiki_stats() {
    run_sentinel stats
}

# Run reflection on sessions
# Usage: wiki_reflect [session_id]
wiki_reflect() {
    local session_id="$1"

    if [[ -n "$session_id" ]]; then
        run_sentinel reflect --session "$session_id"
    else
        run_sentinel reflect --all
    fi
}

# Show playbooks
# Usage: wiki_playbooks [error_signature]
wiki_playbooks() {
    local error="$1"

    if [[ -n "$error" ]]; then
        run_sentinel playbooks --error "$error"
    else
        run_sentinel playbooks
    fi
}

#───────────────────────────────────────────────────────────────────────────────
# Quick Commands (for Claude Code integration)
#───────────────────────────────────────────────────────────────────────────────

# Quick session start from current directory
# Usage: wiki_quick_session <goal>
wiki_quick_session() {
    local goal="$*"

    if [[ -z "$goal" ]]; then
        wiki_error "Usage: wiki quick <goal>"
        echo "Starts a session for the current project with the given goal."
        return 1
    fi

    # Detect project from current directory
    local current_dir="$(pwd)"
    local project_name="$(basename "$current_dir")"

    # Check if we're in a project directory
    if [[ ! -f "package.json" ]] && [[ ! -f "pyproject.toml" ]] && [[ ! -d ".git" ]]; then
        wiki_warn "Not in a project directory. Looking for closest project..."
        # Walk up to find project root
        local dir="$current_dir"
        while [[ "$dir" != "/" ]]; do
            if [[ -f "$dir/package.json" ]] || [[ -f "$dir/pyproject.toml" ]] || [[ -d "$dir/.git" ]]; then
                project_name="$(basename "$dir")"
                break
            fi
            dir="$(dirname "$dir")"
        done
    fi

    wiki_info "Starting session for: $project_name"
    wiki_session_start "$project_name" "$goal"
}

# Log a note to the current session
# Usage: wiki_note <message>
wiki_note() {
    local message="$*"

    if [[ -z "$message" ]]; then
        wiki_error "Usage: wiki note <message>"
        return 1
    fi

    # Add note via direct SQL (quick path)
    local project_id=$(wiki_db_query "SELECT id FROM projects WHERE path = '$(pwd)' LIMIT 1" 2>/dev/null)
    if [[ -z "$project_id" ]]; then
        wiki_warn "Current directory not indexed. Note will be added without project context."
        project_id=0
    fi

    wiki_db_query "
        INSERT INTO dev_journal (project_id, entry_type, summary)
        VALUES ($project_id, 'NOTE', '$(echo "$message" | sed "s/'/''/g")')
    " 2>/dev/null

    wiki_info "Note added: $message"
}

# Log a journal entry with specific type
# Usage: wiki_log <entry_type> <message>
wiki_log() {
    local entry_type="$1"
    shift
    local message="$*"

    if [[ -z "$entry_type" ]] || [[ -z "$message" ]]; then
        wiki_error "Usage: wiki journal log <entry_type> <message>"
        echo "Entry types: ERROR_LOG, AI_HYPOTHESIS, AI_TOOL_CALL, AI_OBSERVATION, NOTE"
        return 1
    fi

    # Validate entry type
    local valid_types="ERROR_LOG AI_HYPOTHESIS AI_TOOL_CALL AI_OBSERVATION NOTE FILE_CHANGE BUILD_EVENT COMMAND_RUN"
    if [[ ! " $valid_types " =~ " $entry_type " ]]; then
        wiki_warn "Unknown entry type: $entry_type (using anyway)"
    fi

    # Get current session if active
    local session_id=""
    local project_id=0

    # Try to find active session
    session_id=$(wiki_db_query "SELECT id FROM dev_sessions WHERE status = 'IN_PROGRESS' ORDER BY start_time DESC LIMIT 1" 2>/dev/null)

    if [[ -n "$session_id" ]]; then
        project_id=$(wiki_db_query "SELECT project_id FROM dev_sessions WHERE id = $session_id" 2>/dev/null)
    fi

    # Insert journal entry
    if [[ -n "$session_id" ]]; then
        wiki_db_query "
            INSERT INTO dev_journal (project_id, session_id, entry_type, summary)
            VALUES ($project_id, $session_id, '$entry_type', '$(echo "$message" | sed "s/'/''/g")')
        " 2>/dev/null
        wiki_info "[$entry_type] logged to session #$session_id"
    else
        wiki_db_query "
            INSERT INTO dev_journal (project_id, entry_type, summary)
            VALUES ($project_id, '$entry_type', '$(echo "$message" | sed "s/'/''/g")')
        " 2>/dev/null
        wiki_info "[$entry_type] logged (no active session)"
    fi
}

#───────────────────────────────────────────────────────────────────────────────
# Main Dispatcher
#───────────────────────────────────────────────────────────────────────────────

wiki_journal_cmd() {
    local cmd="${1:-}"
    shift 2>/dev/null || true

    case "$cmd" in
        # Session commands: wiki session start|end|list|show
        session)
            local subcmd="${1:-}"
            shift 2>/dev/null || true
            case "$subcmd" in
                start) wiki_session_start "$@" ;;
                end)   wiki_session_end "$@" ;;
                list)  wiki_session_list "$@" ;;
                show)  wiki_session_show "$@" ;;
                help|"") run_sentinel session --help ;;
                *) wiki_error "Unknown session command: $subcmd" ;;
            esac
            ;;
        # Journal command: wiki journal [log]
        journal)
            local subcmd="${1:-}"
            if [[ "$subcmd" == "log" ]]; then
                shift
                wiki_log "$@"
            else
                wiki_journal "$@"
            fi
            ;;
        # Test commands: wiki tests watch|process|flaky
        tests)
            local subcmd="${1:-}"
            shift 2>/dev/null || true
            case "$subcmd" in
                watch)   wiki_tests_watch "$@" ;;
                process) wiki_tests_process "$@" ;;
                flaky)   wiki_tests_flaky "$@" ;;
                help|"") run_sentinel tests --help ;;
                *) wiki_error "Unknown tests command: $subcmd" ;;
            esac
            ;;
        # Direct commands
        stats)
            wiki_stats "$@"
            ;;
        reflect)
            wiki_reflect "$@"
            ;;
        playbooks)
            wiki_playbooks "$@"
            ;;
        briefing|brief|b)
            run_sentinel briefing "$@"
            ;;
        patterns|p)
            run_sentinel patterns "$@"
            ;;
        quick|q)
            wiki_quick_session "$@"
            ;;
        note|n)
            wiki_note "$@"
            ;;
        help|"")
            cat << EOF
${BOLD}Development Journal Commands${NC}

${GREEN}Session Management:${NC}
    wiki session start <project> <goal>  Start a dev session
    wiki session end <id> [summary]      End a session
    wiki session list                    List recent sessions
    wiki session show <id>               Show session details

${GREEN}Journal:${NC}
    wiki journal                         Show recent entries
    wiki journal -t TEST_RUN             Filter by entry type
    wiki note <message>                  Add a quick note

${GREEN}Tests:${NC}
    wiki tests watch                     Watch for test results
    wiki tests process <file>            Process test result file
    wiki tests flaky                     Show flaky tests

${GREEN}Intelligence:${NC}
    wiki stats                           Show statistics
    wiki reflect [session_id]            Run reflection analysis
    wiki playbooks [error]               Show/search playbooks
    wiki briefing [-p project] [-e err]  Get AI-optimized briefing
    wiki patterns                        Show learned universal patterns

${GREEN}Quick Commands:${NC}
    wiki quick <goal>                    Start session in current dir
    wiki note <message>                  Add a note to journal

${BOLD}Entry Types:${NC}
    SESSION_START, SESSION_END, TEST_RUN, ERROR_LOG,
    FILE_CHANGE, AI_TASK, AI_HYPOTHESIS, AI_TOOL_CALL,
    AI_OBSERVATION, NOTE, COMMAND_RUN, BUILD_EVENT
EOF
            ;;
        *)
            wiki_error "Unknown journal command: $subcmd"
            echo "Run 'wiki session help' for usage"
            return 1
            ;;
    esac
}
