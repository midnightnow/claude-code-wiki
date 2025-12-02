#!/bin/bash
#═══════════════════════════════════════════════════════════════════════════════
#  CLAUDE CODE WIKI - Indexer Module
#  Project discovery, indexing, and search
#═══════════════════════════════════════════════════════════════════════════════

# Ensure common is loaded
[[ -z "$WIKI_VERSION" ]] && source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

#───────────────────────────────────────────────────────────────────────────────
# Index a single project
#───────────────────────────────────────────────────────────────────────────────

wiki_index_project() {
    local dir="$1"
    local name=$(basename "$dir")
    local type=$(wiki_detect_project_type "$dir")
    local lang=$(wiki_detect_language "$dir")
    local has_context=$([[ -f "$dir/GEMINI.md" || -f "$dir/GEMINI_CONTEXT.md" ]] && echo 1 || echo 0)

    # Count source files
    local file_count=$(find "$dir" -maxdepth 4 -type f \( \
        -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" \
        -o -name "*.py" -o -name "*.go" -o -name "*.rs" \
        -o -name "*.json" -o -name "*.md" -o -name "*.yaml" -o -name "*.yml" \
    \) ! -path "*/node_modules/*" ! -path "*/.git/*" ! -path "*/dist/*" \
       ! -path "*/.next/*" ! -path "*/__pycache__/*" 2>/dev/null | wc -l | tr -d ' ')

    # Skip if too few files
    [[ $file_count -lt 3 ]] && return 1

    # Escape single quotes for SQL
    local safe_path="${dir//\'/\'\'}"
    local safe_name="${name//\'/\'\'}"

    # Insert or update project
    wiki_db_query "INSERT OR REPLACE INTO projects (name, path, type, has_context, file_count, primary_language, last_indexed_at)
                   VALUES ('$safe_name', '$safe_path', '$type', $has_context, $file_count, '$lang', datetime('now'));"

    local project_id=$(wiki_db_query "SELECT id FROM projects WHERE name='$safe_name';")

    # Clear old files for this project
    wiki_db_query "DELETE FROM files WHERE project_id=$project_id;"

    # Index important files
    find "$dir" -maxdepth 4 -type f \( \
        -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" \
        -o -name "*.py" -o -name "*.go" -o -name "*.rs" \
        -o -name "*.json" -o -name "*.md" -o -name "*.yaml" -o -name "*.yml" \
    \) ! -path "*/node_modules/*" ! -path "*/.git/*" ! -path "*/dist/*" \
       ! -path "*/.next/*" ! -path "*/__pycache__/*" 2>/dev/null | while read -r file; do
        local filename=$(basename "$file")
        local ext="${filename##*.}"
        local size=$(wiki_file_size "$file")
        local is_config=0

        # Detect config files
        [[ "$filename" =~ ^(package|tsconfig|firebase|next\.config|docker-compose|\.env|Dockerfile|Makefile) ]] && is_config=1

        local safe_file="${file//\'/\'\'}"
        wiki_db_query "INSERT INTO files (project_id, path, filename, extension, size, is_config)
                       VALUES ($project_id, '$safe_file', '$filename', '$ext', $size, $is_config);"
    done

    [[ -z "$WIKI_QUIET" ]] && echo -e "  ${GREEN}✓${NC} $name ${CYAN}($type, $file_count files)${NC}"
    return 0
}

#───────────────────────────────────────────────────────────────────────────────
# Scan all projects
#───────────────────────────────────────────────────────────────────────────────

wiki_scan() {
    wiki_print_header "Scanning Projects"

    wiki_acquire_lock || wiki_die "Another wiki operation is in progress"

    # Initialize database
    wiki_db_init

    local scan_dir="${1:-$HOME}"
    local count=0
    local skipped=0

    wiki_info "Scanning: $scan_dir"
    echo ""

    # Find directories with git or package.json (real projects)
    for dir in "$scan_dir"/*/; do
        [[ ! -d "$dir" ]] && continue

        # Check if it's a project
        if [[ -d "$dir/.git" || -f "$dir/package.json" || -f "$dir/firebase.json" || \
              -f "$dir/requirements.txt" || -f "$dir/go.mod" || -f "$dir/Cargo.toml" ]]; then
            if wiki_index_project "$dir"; then
                ((count++))
            else
                ((skipped++))
            fi
        fi
    done

    # Also scan nested directories (firebase_projects, worktrees, etc.)
    for parent in "$scan_dir"/*/; do
        [[ ! -d "$parent" ]] && continue
        for dir in "$parent"/*/; do
            [[ ! -d "$dir" ]] && continue
            if [[ -d "$dir/.git" || -f "$dir/package.json" ]]; then
                if wiki_index_project "$dir"; then
                    ((count++))
                fi
            fi
        done 2>/dev/null
    done

    wiki_release_lock

    echo ""
    wiki_print_section "Summary"
    local total=$(wiki_db_query "SELECT COUNT(*) FROM projects;")
    local total_files=$(wiki_db_query "SELECT COALESCE(SUM(file_count), 0) FROM projects;")
    echo -e "  Projects indexed: ${GREEN}$total${NC}"
    echo -e "  Total files: ${CYAN}$total_files${NC}"
    echo -e "  New this scan: ${GREEN}$count${NC}"
    [[ $skipped -gt 0 ]] && echo -e "  Skipped (too small): ${YELLOW}$skipped${NC}"
}

#───────────────────────────────────────────────────────────────────────────────
# Search across projects
#───────────────────────────────────────────────────────────────────────────────

wiki_search() {
    local query="$1"

    if [[ -z "$query" ]]; then
        wiki_error "Usage: wiki find <query>"
        return 1
    fi

    wiki_print_header "Search: $query"

    local results=$(wiki_db_query_formatted "
        SELECT p.name AS project, p.type, f.path
        FROM files f
        JOIN projects p ON f.project_id = p.id
        WHERE f.filename LIKE '%$query%' OR f.path LIKE '%$query%'
        ORDER BY p.name
        LIMIT 50;
    ")

    if [[ -n "$results" ]]; then
        echo "$results"
    else
        wiki_warn "No results found for: $query"
    fi
}

#───────────────────────────────────────────────────────────────────────────────
# List all projects
#───────────────────────────────────────────────────────────────────────────────

wiki_list_projects() {
    wiki_print_header "Indexed Projects"

    wiki_db_query_formatted "
        SELECT name, type, primary_language AS lang, file_count AS files,
               CASE WHEN has_context THEN '✓' ELSE '' END AS context,
               datetime(last_indexed_at, 'localtime') AS indexed
        FROM projects
        ORDER BY last_indexed_at DESC;
    "
}

#───────────────────────────────────────────────────────────────────────────────
# Project info
#───────────────────────────────────────────────────────────────────────────────

wiki_project_info() {
    local name="$1"

    if [[ -z "$name" ]]; then
        wiki_error "Usage: wiki info <project>"
        return 1
    fi

    local project=$(wiki_db_query "SELECT * FROM projects WHERE name LIKE '%$name%' LIMIT 1;")

    if [[ -z "$project" ]]; then
        wiki_error "Project not found: $name"
        return 1
    fi

    wiki_print_header "Project: $name"

    wiki_db_query_formatted "
        SELECT name, path, type, primary_language AS language,
               file_count AS files, has_context AS 'has context',
               datetime(last_indexed_at, 'localtime') AS 'last indexed'
        FROM projects
        WHERE name LIKE '%$name%'
        LIMIT 1;
    "

    echo ""
    wiki_print_section "Config Files"
    wiki_db_query "
        SELECT path FROM files
        WHERE project_id = (SELECT id FROM projects WHERE name LIKE '%$name%' LIMIT 1)
        AND is_config = 1;
    "

    echo ""
    wiki_print_section "File Types"
    wiki_db_query_formatted "
        SELECT extension, COUNT(*) as count
        FROM files
        WHERE project_id = (SELECT id FROM projects WHERE name LIKE '%$name%' LIMIT 1)
        GROUP BY extension
        ORDER BY count DESC
        LIMIT 10;
    "
}
