#!/bin/bash
#═══════════════════════════════════════════════════════════════════════════════
#  CLAUDE CODE WIKI - Git Hooks Library
#  Auto-update wiki documentation on git events
#═══════════════════════════════════════════════════════════════════════════════

# Source common library if not already loaded
if [[ -z "$WIKI_VERSION" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$SCRIPT_DIR/common.sh"
fi

#───────────────────────────────────────────────────────────────────────────────
# Git Hook Templates
#───────────────────────────────────────────────────────────────────────────────

# Post-commit hook content
HOOK_POST_COMMIT='#!/bin/bash
#═══════════════════════════════════════════════════════════════════════════════
#  Claude Code Wiki - Post-Commit Hook
#  Triggers wiki update after each commit (async/background)
#═══════════════════════════════════════════════════════════════════════════════

# Skip if already in a wiki update commit
if git log -1 --format="%s" | grep -q "\[skip wiki\]"; then
    exit 0
fi

# Skip if no wiki command available
if ! command -v wiki &>/dev/null; then
    exit 0
fi

# Check for codewiki.yaml config
if [[ ! -f "codewiki.yaml" && ! -f ".codewiki.yaml" ]]; then
    exit 0
fi

# Run wiki update in background (non-blocking)
(
    sleep 2  # Brief delay to let commit complete
    wiki cicd run HEAD~1 --quiet 2>/dev/null
) &

exit 0
'

# Pre-push hook content
HOOK_PRE_PUSH='#!/bin/bash
#═══════════════════════════════════════════════════════════════════════════════
#  Claude Code Wiki - Pre-Push Hook
#  Ensures documentation is up-to-date before pushing
#═══════════════════════════════════════════════════════════════════════════════

# Skip if marked
if [[ -n "$WIKI_SKIP_HOOKS" ]]; then
    exit 0
fi

# Check for wiki command
if ! command -v wiki &>/dev/null; then
    exit 0
fi

# Check for config
if [[ ! -f "codewiki.yaml" && ! -f ".codewiki.yaml" ]]; then
    exit 0
fi

# Get the remote and branch being pushed to
remote="$1"
url="$2"

# Read stdin for refs being pushed
while read local_ref local_sha remote_ref remote_sha; do
    # Only check pushes to main/develop
    if [[ "$remote_ref" =~ refs/heads/(main|master|develop) ]]; then
        echo "Wiki: Checking documentation freshness..."

        # Quick check if docs are stale
        if wiki cicd diff "$remote_sha" --quiet 2>/dev/null | grep -q "total.*[1-9]"; then
            echo "Wiki: Documentation may be out of date. Running update..."
            wiki cicd run "$remote_sha" --quiet
        fi
    fi
done

exit 0
'

#───────────────────────────────────────────────────────────────────────────────
# Hook Management Functions
#───────────────────────────────────────────────────────────────────────────────

# Install hooks in a repository
wiki_hooks_install() {
    local repo_path="${1:-.}"
    local force="${2:-false}"

    wiki_print_header "Installing Git Hooks"

    # Verify it's a git repository
    if [[ ! -d "$repo_path/.git" ]]; then
        wiki_error "Not a git repository: $repo_path"
        return 1
    fi

    local hooks_dir="$repo_path/.git/hooks"
    mkdir -p "$hooks_dir"

    # Install post-commit hook
    local post_commit="$hooks_dir/post-commit"
    if [[ -f "$post_commit" && "$force" != "true" ]]; then
        wiki_warn "post-commit hook already exists. Use --force to overwrite."
    else
        echo "$HOOK_POST_COMMIT" > "$post_commit"
        chmod +x "$post_commit"
        wiki_info "Installed: post-commit hook"
    fi

    # Install pre-push hook
    local pre_push="$hooks_dir/pre-push"
    if [[ -f "$pre_push" && "$force" != "true" ]]; then
        wiki_warn "pre-push hook already exists. Use --force to overwrite."
    else
        echo "$HOOK_PRE_PUSH" > "$pre_push"
        chmod +x "$pre_push"
        wiki_info "Installed: pre-push hook"
    fi

    # Create sample config if none exists
    if [[ ! -f "$repo_path/codewiki.yaml" && ! -f "$repo_path/.codewiki.yaml" ]]; then
        wiki_info "Creating sample codewiki.yaml..."
        cp "$WIKI_HOME/config/codewiki.yaml.example" "$repo_path/codewiki.yaml"
        wiki_info "Edit codewiki.yaml to configure your documentation settings."
    fi

    echo ""
    wiki_info "Git hooks installed successfully!"
    echo ""
    echo "Next steps:"
    echo "  1. Edit codewiki.yaml to configure triggers and scope"
    echo "  2. Make a commit to test the hooks"
    echo "  3. Check docs/generated/ for output"
}

# Uninstall hooks from a repository
wiki_hooks_uninstall() {
    local repo_path="${1:-.}"

    wiki_print_header "Uninstalling Git Hooks"

    if [[ ! -d "$repo_path/.git" ]]; then
        wiki_error "Not a git repository: $repo_path"
        return 1
    fi

    local hooks_dir="$repo_path/.git/hooks"

    # Remove our hooks (check content first)
    for hook in post-commit pre-push; do
        local hook_file="$hooks_dir/$hook"
        if [[ -f "$hook_file" ]] && grep -q "Claude Code Wiki" "$hook_file"; then
            rm "$hook_file"
            wiki_info "Removed: $hook hook"
        fi
    done

    wiki_info "Git hooks uninstalled"
}

# Install hooks in all indexed projects
wiki_hooks_install_all() {
    wiki_print_header "Installing Hooks in All Projects"

    source "$WIKI_HOME/lib/indexer.sh"
    wiki_db_init 2>/dev/null

    local projects=$(wiki_db_query "SELECT path FROM projects WHERE path IS NOT NULL;")

    if [[ -z "$projects" ]]; then
        wiki_warn "No indexed projects found. Run 'wiki scan' first."
        return 1
    fi

    local count=0
    local success=0

    while IFS= read -r project_path; do
        ((count++))

        if [[ -d "$project_path/.git" ]]; then
            echo -e "  [$count] Installing in: ${CYAN}$project_path${NC}"
            if wiki_hooks_install "$project_path" "false" 2>/dev/null; then
                ((success++))
            fi
        fi
    done <<< "$projects"

    echo ""
    wiki_info "Installed hooks in $success of $count projects"
}

# Show hook status
wiki_hooks_status() {
    local repo_path="${1:-.}"

    wiki_print_header "Git Hooks Status"

    if [[ ! -d "$repo_path/.git" ]]; then
        wiki_error "Not a git repository: $repo_path"
        return 1
    fi

    local hooks_dir="$repo_path/.git/hooks"

    echo -e "Repository: ${CYAN}$repo_path${NC}"
    echo ""

    for hook in post-commit pre-push post-merge; do
        local hook_file="$hooks_dir/$hook"
        if [[ -f "$hook_file" ]]; then
            if grep -q "Claude Code Wiki" "$hook_file"; then
                echo -e "  ${GREEN}✓${NC} $hook (wiki-managed)"
            else
                echo -e "  ${YELLOW}○${NC} $hook (custom)"
            fi
        else
            echo -e "  ${RED}✗${NC} $hook (not installed)"
        fi
    done

    echo ""

    # Check for config
    if [[ -f "$repo_path/codewiki.yaml" ]]; then
        echo -e "Config: ${GREEN}codewiki.yaml${NC}"
    elif [[ -f "$repo_path/.codewiki.yaml" ]]; then
        echo -e "Config: ${GREEN}.codewiki.yaml${NC}"
    else
        echo -e "Config: ${YELLOW}Not found${NC} (create codewiki.yaml to enable)"
    fi
}

#───────────────────────────────────────────────────────────────────────────────
# Main Entry Point
#───────────────────────────────────────────────────────────────────────────────

wiki_hooks() {
    local subcmd="${1:-status}"
    shift 2>/dev/null || true

    case "$subcmd" in
        install)
            local force=""
            local path="."
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --force|-f) force="true"; shift ;;
                    --all|-a) wiki_hooks_install_all; return ;;
                    *) path="$1"; shift ;;
                esac
            done
            wiki_hooks_install "$path" "$force"
            ;;
        uninstall|remove)
            wiki_hooks_uninstall "${1:-.}"
            ;;
        status)
            wiki_hooks_status "${1:-.}"
            ;;
        *)
            echo "Usage: wiki hooks <install|uninstall|status> [options]"
            echo ""
            echo "Commands:"
            echo "  install [path]       Install git hooks in repository"
            echo "  install --all        Install hooks in all indexed projects"
            echo "  install --force      Overwrite existing hooks"
            echo "  uninstall [path]     Remove wiki git hooks"
            echo "  status [path]        Show hook installation status"
            ;;
    esac
}
