#!/bin/bash
#═══════════════════════════════════════════════════════════════════════════════
#  CLAUDE CODE WIKI - Universal Installer
#  curl -sL https://raw.githubusercontent.com/patrickdellis/claude-code-wiki/main/install.sh | bash
#═══════════════════════════════════════════════════════════════════════════════

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Configuration
REPO_URL="https://github.com/patrickdellis/claude-code-wiki"
INSTALL_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/claude-code-wiki"
BIN_DIR="${HOME}/.local/bin"

echo -e "${BOLD}${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${BLUE}║${NC}  ${BOLD}Claude Code Wiki Installer${NC}"
echo -e "${BOLD}${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""

#───────────────────────────────────────────────────────────────────────────────
# Check requirements
#───────────────────────────────────────────────────────────────────────────────

echo -e "${CYAN}► Checking requirements...${NC}"

# Check for git
if ! command -v git &> /dev/null; then
    echo -e "${RED}✗ git is required but not installed${NC}"
    exit 1
fi
echo -e "  ${GREEN}✓${NC} git"

# Check for sqlite3
if ! command -v sqlite3 &> /dev/null; then
    echo -e "${RED}✗ sqlite3 is required but not installed${NC}"
    echo "  Install with: brew install sqlite3 (macOS) or apt install sqlite3 (Linux)"
    exit 1
fi
echo -e "  ${GREEN}✓${NC} sqlite3"

# Check for bash version
bash_version="${BASH_VERSION%%.*}"
if [[ "$bash_version" -lt 4 ]]; then
    echo -e "${YELLOW}○ bash 4.0+ recommended (current: $BASH_VERSION)${NC}"
else
    echo -e "  ${GREEN}✓${NC} bash $BASH_VERSION"
fi

# Optional: jq
if command -v jq &> /dev/null; then
    echo -e "  ${GREEN}✓${NC} jq (optional)"
else
    echo -e "  ${YELLOW}○${NC} jq not installed (optional, for config parsing)"
fi

echo ""

#───────────────────────────────────────────────────────────────────────────────
# Clone or update repository
#───────────────────────────────────────────────────────────────────────────────

echo -e "${CYAN}► Installing Claude Code Wiki...${NC}"

if [[ -d "$INSTALL_DIR/.git" ]]; then
    echo "  Updating existing installation..."
    cd "$INSTALL_DIR"
    git pull origin main
else
    echo "  Cloning repository..."
    mkdir -p "$(dirname "$INSTALL_DIR")"
    git clone "$REPO_URL" "$INSTALL_DIR"
fi

echo -e "  ${GREEN}✓${NC} Installed to $INSTALL_DIR"
echo ""

#───────────────────────────────────────────────────────────────────────────────
# Run setup
#───────────────────────────────────────────────────────────────────────────────

echo -e "${CYAN}► Running setup...${NC}"
cd "$INSTALL_DIR"
bash ./setup.sh

echo ""
echo -e "${BOLD}${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║${NC}  ${BOLD}Installation Complete!${NC}"
echo -e "${BOLD}${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${CYAN}Reload your shell:${NC} source ~/.zshrc (or ~/.bashrc)"
echo ""
echo -e "  ${CYAN}Quick start:${NC}"
echo "    wiki scan        # Index all projects"
echo "    wiki find auth   # Search for 'auth'"
echo "    wiki health      # Check system health"
echo ""
echo -e "  ${CYAN}Documentation:${NC} $REPO_URL"
echo ""
