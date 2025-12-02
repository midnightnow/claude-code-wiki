#!/bin/bash
#═══════════════════════════════════════════════════════════════════════════════
#  CLAUDE CODE WIKI - Setup Script
#  Run after cloning or updating
#═══════════════════════════════════════════════════════════════════════════════

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# XDG directories
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/claude-wiki"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/claude-wiki"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/claude-wiki"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/claude-wiki"
BIN_DIR="${HOME}/.local/bin"

# Claude directories
CLAUDE_DIR="$HOME/.claude"
CLAUDE_COMMANDS="$CLAUDE_DIR/commands"
CLAUDE_SCRIPTS="$CLAUDE_DIR/scripts"

echo -e "${BOLD}Claude Code Wiki Setup${NC}"
echo "─────────────────────────────────────"
echo ""

#───────────────────────────────────────────────────────────────────────────────
# Create directories
#───────────────────────────────────────────────────────────────────────────────

echo -e "${CYAN}► Creating directories...${NC}"
mkdir -p "$CONFIG_DIR" "$DATA_DIR" "$STATE_DIR" "$CACHE_DIR" "$BIN_DIR"
mkdir -p "$CLAUDE_COMMANDS" "$CLAUDE_SCRIPTS"
echo -e "  ${GREEN}✓${NC} Directories created"

#───────────────────────────────────────────────────────────────────────────────
# Make scripts executable
#───────────────────────────────────────────────────────────────────────────────

echo -e "${CYAN}► Setting permissions...${NC}"
chmod +x "$SCRIPT_DIR/bin/wiki"
chmod +x "$SCRIPT_DIR/lib/"*.sh 2>/dev/null || true
echo -e "  ${GREEN}✓${NC} Scripts are executable"

#───────────────────────────────────────────────────────────────────────────────
# Create symlink in PATH
#───────────────────────────────────────────────────────────────────────────────

echo -e "${CYAN}► Creating wiki command...${NC}"
ln -sf "$SCRIPT_DIR/bin/wiki" "$BIN_DIR/wiki"
echo -e "  ${GREEN}✓${NC} Linked to $BIN_DIR/wiki"

#───────────────────────────────────────────────────────────────────────────────
# Install Claude commands
#───────────────────────────────────────────────────────────────────────────────

echo -e "${CYAN}► Installing Claude commands...${NC}"

# wiki-scan
cat > "$CLAUDE_COMMANDS/wiki-scan.md" << 'EOF'
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

# wiki-find
cat > "$CLAUDE_COMMANDS/wiki-find.md" << 'EOF'
# Wiki Find

Search across all indexed projects.

**Usage:** `wiki find <query>`

```bash
wiki find "$ARGUMENTS"
```

Search matches file names, paths, and project names.
EOF

# wiki-health
cat > "$CLAUDE_COMMANDS/wiki-health.md" << 'EOF'
# Wiki Health Check

Run diagnostics on the wiki system.

```bash
wiki health
```

Checks dependencies, database, configuration, and system state.
EOF

# wiki-prepare
cat > "$CLAUDE_COMMANDS/wiki-prepare.md" << 'EOF'
# Wiki Prepare Context

Generate AI context manifest for a project.

**Usage:** `wiki prepare <path>`

```bash
wiki prepare "${ARGUMENTS:-.}"
```

Creates GEMINI_CONTEXT.md with project structure, dependencies, and entry points.
EOF

echo -e "  ${GREEN}✓${NC} Claude commands installed"

#───────────────────────────────────────────────────────────────────────────────
# Add shell integration
#───────────────────────────────────────────────────────────────────────────────

echo -e "${CYAN}► Setting up shell integration...${NC}"

# Detect shell config
SHELL_CONFIG=""
if [[ -f "$HOME/.zshrc" ]]; then
    SHELL_CONFIG="$HOME/.zshrc"
elif [[ -f "$HOME/.bashrc" ]]; then
    SHELL_CONFIG="$HOME/.bashrc"
fi

if [[ -n "$SHELL_CONFIG" ]]; then
    # Check if already configured
    if ! grep -q "CLAUDE CODE WIKI" "$SHELL_CONFIG" 2>/dev/null; then
        cat >> "$SHELL_CONFIG" << 'SHELL_EOF'

#═══════════════════════════════════════════════════════════════════════════════
# CLAUDE CODE WIKI - Shell Integration
#═══════════════════════════════════════════════════════════════════════════════

# Add wiki to PATH
export PATH="$HOME/.local/bin:$PATH"

# Project quick-jump function
cdp() {
    local db="${XDG_DATA_HOME:-$HOME/.local/share}/claude-wiki/wiki.db"
    if [[ -f "$db" ]]; then
        local project_path=$(sqlite3 "$db" "SELECT path FROM projects WHERE name LIKE '%$1%' LIMIT 1;" 2>/dev/null)
        if [[ -n "$project_path" && -d "$project_path" ]]; then
            cd "$project_path"
            echo "📁 $project_path"
            [[ -f "GEMINI.md" || -f "GEMINI_CONTEXT.md" ]] && echo "📖 Has AI context"
        else
            echo "Project not found: $1"
            echo "Run 'wiki scan' to index projects"
        fi
    else
        echo "Wiki database not initialized. Run 'wiki scan' first."
    fi
}

# Tab completion for wiki
_wiki_completions() {
    local commands="scan find list info prepare health fix config update uninstall"
    COMPREPLY=($(compgen -W "$commands" -- "${COMP_WORDS[1]}"))
}
complete -F _wiki_completions wiki 2>/dev/null || true

#═══════════════════════════════════════════════════════════════════════════════
SHELL_EOF
        echo -e "  ${GREEN}✓${NC} Added to $SHELL_CONFIG"
    else
        echo -e "  ${YELLOW}○${NC} Shell integration already configured"
    fi
else
    echo -e "  ${YELLOW}○${NC} No .zshrc or .bashrc found"
fi

#───────────────────────────────────────────────────────────────────────────────
# Initialize database
#───────────────────────────────────────────────────────────────────────────────

echo -e "${CYAN}► Initializing database...${NC}"
"$SCRIPT_DIR/bin/wiki" health > /dev/null 2>&1 || true
echo -e "  ${GREEN}✓${NC} Database ready"

#───────────────────────────────────────────────────────────────────────────────
# Summary
#───────────────────────────────────────────────────────────────────────────────

echo ""
echo -e "${GREEN}Setup complete!${NC}"
echo ""
echo "Next steps:"
echo "  1. Reload shell: source $SHELL_CONFIG"
echo "  2. Index projects: wiki scan"
echo "  3. Search: wiki find <query>"
echo ""
