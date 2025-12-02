#!/bin/bash
#═══════════════════════════════════════════════════════════════════════════════
#  CLAUDE CODE WIKI - Common Library
#  Shared functions for all wiki scripts
#═══════════════════════════════════════════════════════════════════════════════

# Version
export WIKI_VERSION="1.0.0"

# XDG Base Directory Specification
export WIKI_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/claude-wiki"
export WIKI_DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/claude-wiki"
export WIKI_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/claude-wiki"
export WIKI_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/claude-wiki"

# Claude Code integration
export CLAUDE_DIR="$HOME/.claude"
export CLAUDE_COMMANDS_DIR="$CLAUDE_DIR/commands"
export CLAUDE_SCRIPTS_DIR="$CLAUDE_DIR/scripts"

# Database
export WIKI_DB="$WIKI_DATA_DIR/wiki.db"
export WIKI_ISSUES_DB="$WIKI_DATA_DIR/issues.db"

# Logs
export WIKI_LOG_FILE="$WIKI_STATE_DIR/wiki.log"

# Config file
export WIKI_CONFIG_FILE="$WIKI_CONFIG_DIR/config.json"

# Colors (with fallback for non-interactive)
if [[ -t 1 ]]; then
    export RED='\033[0;31m'
    export GREEN='\033[0;32m'
    export YELLOW='\033[0;33m'
    export BLUE='\033[0;34m'
    export PURPLE='\033[0;35m'
    export CYAN='\033[0;36m'
    export WHITE='\033[0;37m'
    export BOLD='\033[1m'
    export NC='\033[0m' # No Color
else
    export RED='' GREEN='' YELLOW='' BLUE='' PURPLE='' CYAN='' WHITE='' BOLD='' NC=''
fi

#───────────────────────────────────────────────────────────────────────────────
# Logging Functions
#───────────────────────────────────────────────────────────────────────────────

wiki_log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Ensure log directory exists
    mkdir -p "$(dirname "$WIKI_LOG_FILE")"

    # Log to file
    echo "[$timestamp] [$level] $message" >> "$WIKI_LOG_FILE"

    # Log to stderr based on level
    case "$level" in
        ERROR)   echo -e "${RED}ERROR:${NC} $message" >&2 ;;
        WARN)    echo -e "${YELLOW}WARN:${NC} $message" >&2 ;;
        INFO)    echo -e "${GREEN}INFO:${NC} $message" ;;
        DEBUG)   [[ "${WIKI_DEBUG:-0}" == "1" ]] && echo -e "${CYAN}DEBUG:${NC} $message" || true ;;
    esac
}

wiki_info()  { wiki_log "INFO" "$@"; }
wiki_warn()  { wiki_log "WARN" "$@"; }
wiki_error() { wiki_log "ERROR" "$@"; }
wiki_debug() { wiki_log "DEBUG" "$@"; }

#───────────────────────────────────────────────────────────────────────────────
# Error Handling
#───────────────────────────────────────────────────────────────────────────────

wiki_die() {
    wiki_error "$@"
    exit 1
}

wiki_require() {
    local cmd="$1"
    if ! command -v "$cmd" &> /dev/null; then
        wiki_die "Required command not found: $cmd"
    fi
}

#───────────────────────────────────────────────────────────────────────────────
# Directory Setup
#───────────────────────────────────────────────────────────────────────────────

wiki_init_dirs() {
    mkdir -p "$WIKI_CONFIG_DIR" "$WIKI_DATA_DIR" "$WIKI_STATE_DIR" "$WIKI_CACHE_DIR"
    mkdir -p "$CLAUDE_COMMANDS_DIR" "$CLAUDE_SCRIPTS_DIR"
}

#───────────────────────────────────────────────────────────────────────────────
# Configuration
#───────────────────────────────────────────────────────────────────────────────

wiki_load_config() {
    if [[ -f "$WIKI_CONFIG_FILE" ]]; then
        # Load config values (requires jq)
        if command -v jq &> /dev/null; then
            export WIKI_PROJECT_DIRS=$(jq -r '.project_dirs // ["'$HOME'"] | join(":")' "$WIKI_CONFIG_FILE" 2>/dev/null)
            export WIKI_DEFAULT_MODEL=$(jq -r '.default_model // "gemini-2.5-pro"' "$WIKI_CONFIG_FILE" 2>/dev/null)
            export WIKI_AUTO_INDEX=$(jq -r '.auto_index // true' "$WIKI_CONFIG_FILE" 2>/dev/null)
        fi
    else
        # Defaults
        export WIKI_PROJECT_DIRS="$HOME"
        export WIKI_DEFAULT_MODEL="gemini-2.5-pro"
        export WIKI_AUTO_INDEX="true"
    fi
}

wiki_save_config() {
    wiki_init_dirs
    cat > "$WIKI_CONFIG_FILE" << EOF
{
    "version": "$WIKI_VERSION",
    "project_dirs": ["$HOME"],
    "default_model": "gemini-2.5-pro",
    "auto_index": true,
    "excluded_patterns": ["node_modules", ".git", "dist", "build", "__pycache__", ".next"],
    "index_depth": 4,
    "created_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
    wiki_info "Config saved to $WIKI_CONFIG_FILE"
}

#───────────────────────────────────────────────────────────────────────────────
# Database Functions
#───────────────────────────────────────────────────────────────────────────────

wiki_db_init() {
    wiki_init_dirs
    wiki_require sqlite3

    sqlite3 "$WIKI_DB" << 'SQL'
CREATE TABLE IF NOT EXISTS projects (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT UNIQUE NOT NULL,
    path TEXT NOT NULL,
    type TEXT,
    last_indexed_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    has_context BOOLEAN DEFAULT 0,
    file_count INTEGER DEFAULT 0,
    primary_language TEXT
);

CREATE TABLE IF NOT EXISTS files (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    project_id INTEGER,
    path TEXT NOT NULL,
    filename TEXT NOT NULL,
    extension TEXT,
    size INTEGER,
    last_modified DATETIME,
    is_config BOOLEAN DEFAULT 0,
    content_hash TEXT,
    FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS context_cache (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    project_id INTEGER,
    context_type TEXT,
    content TEXT,
    generated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    model_used TEXT,
    FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_files_project ON files(project_id);
CREATE INDEX IF NOT EXISTS idx_files_extension ON files(extension);
CREATE INDEX IF NOT EXISTS idx_files_filename ON files(filename);
CREATE INDEX IF NOT EXISTS idx_projects_name ON projects(name);
SQL
    wiki_debug "Database initialized at $WIKI_DB"
}

wiki_db_query() {
    sqlite3 "$WIKI_DB" "$@"
}

wiki_db_query_formatted() {
    sqlite3 -header -column "$WIKI_DB" "$@"
}

#───────────────────────────────────────────────────────────────────────────────
# Platform Detection
#───────────────────────────────────────────────────────────────────────────────

wiki_detect_platform() {
    case "$(uname -s)" in
        Darwin*)  export WIKI_PLATFORM="macos" ;;
        Linux*)   export WIKI_PLATFORM="linux" ;;
        MINGW*|CYGWIN*|MSYS*) export WIKI_PLATFORM="windows" ;;
        *)        export WIKI_PLATFORM="unknown" ;;
    esac
    wiki_debug "Platform detected: $WIKI_PLATFORM"
}

# Cross-platform stat for file size
wiki_file_size() {
    local file="$1"
    if [[ "$WIKI_PLATFORM" == "macos" ]]; then
        stat -f%z "$file" 2>/dev/null || echo 0
    else
        stat -c%s "$file" 2>/dev/null || echo 0
    fi
}

# Cross-platform date
wiki_file_mtime() {
    local file="$1"
    if [[ "$WIKI_PLATFORM" == "macos" ]]; then
        stat -f%m "$file" 2>/dev/null || echo 0
    else
        stat -c%Y "$file" 2>/dev/null || echo 0
    fi
}

#───────────────────────────────────────────────────────────────────────────────
# Project Detection
#───────────────────────────────────────────────────────────────────────────────

wiki_detect_project_type() {
    local dir="$1"
    if [[ -f "$dir/firebase.json" ]]; then echo "firebase"
    elif [[ -f "$dir/next.config.js" || -f "$dir/next.config.mjs" || -f "$dir/next.config.ts" ]]; then echo "nextjs"
    elif [[ -f "$dir/package.json" && -f "$dir/tsconfig.json" ]]; then echo "typescript"
    elif [[ -f "$dir/package.json" ]]; then echo "nodejs"
    elif [[ -f "$dir/pyproject.toml" ]]; then echo "python-modern"
    elif [[ -f "$dir/requirements.txt" ]]; then echo "python"
    elif [[ -f "$dir/go.mod" ]]; then echo "golang"
    elif [[ -f "$dir/Cargo.toml" ]]; then echo "rust"
    elif [[ -f "$dir/pom.xml" ]]; then echo "java-maven"
    elif [[ -f "$dir/build.gradle" ]]; then echo "java-gradle"
    elif [[ -f "$dir/Gemfile" ]]; then echo "ruby"
    elif [[ -f "$dir/composer.json" ]]; then echo "php"
    else echo "unknown"
    fi
}

wiki_detect_language() {
    local dir="$1"
    local ts_count=$(find "$dir" -maxdepth 3 \( -name "*.ts" -o -name "*.tsx" \) 2>/dev/null | wc -l | tr -d ' ')
    local js_count=$(find "$dir" -maxdepth 3 \( -name "*.js" -o -name "*.jsx" \) 2>/dev/null | wc -l | tr -d ' ')
    local py_count=$(find "$dir" -maxdepth 3 -name "*.py" 2>/dev/null | wc -l | tr -d ' ')
    local go_count=$(find "$dir" -maxdepth 3 -name "*.go" 2>/dev/null | wc -l | tr -d ' ')
    local rs_count=$(find "$dir" -maxdepth 3 -name "*.rs" 2>/dev/null | wc -l | tr -d ' ')

    local max=$ts_count lang="typescript"
    [[ $js_count -gt $max ]] && max=$js_count && lang="javascript"
    [[ $py_count -gt $max ]] && max=$py_count && lang="python"
    [[ $go_count -gt $max ]] && max=$go_count && lang="golang"
    [[ $rs_count -gt $max ]] && max=$rs_count && lang="rust"

    echo "$lang"
}

#───────────────────────────────────────────────────────────────────────────────
# Locking (prevent concurrent operations)
#───────────────────────────────────────────────────────────────────────────────

WIKI_LOCK_FILE="$WIKI_STATE_DIR/wiki.lock"

wiki_acquire_lock() {
    local timeout="${1:-30}"
    local waited=0

    mkdir -p "$(dirname "$WIKI_LOCK_FILE")"

    while [[ -f "$WIKI_LOCK_FILE" ]]; do
        if [[ $waited -ge $timeout ]]; then
            wiki_warn "Lock acquisition timed out after ${timeout}s"
            return 1
        fi
        sleep 1
        ((waited++))
    done

    echo $$ > "$WIKI_LOCK_FILE"
    trap 'rm -f "$WIKI_LOCK_FILE"' EXIT
    wiki_debug "Lock acquired"
    return 0
}

wiki_release_lock() {
    rm -f "$WIKI_LOCK_FILE"
    wiki_debug "Lock released"
}

#───────────────────────────────────────────────────────────────────────────────
# Utility Functions
#───────────────────────────────────────────────────────────────────────────────

wiki_print_header() {
    echo -e "${BOLD}${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${BLUE}║${NC}  ${BOLD}$1${NC}"
    echo -e "${BOLD}${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
}

wiki_print_section() {
    echo -e "\n${BOLD}${CYAN}► $1${NC}"
    echo -e "${CYAN}─────────────────────────────────────────${NC}"
}

wiki_confirm() {
    local prompt="${1:-Continue?}"
    read -p "$prompt [y/N] " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]]
}

# Initialize on source
wiki_detect_platform
wiki_load_config
