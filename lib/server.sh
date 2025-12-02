#!/bin/bash
#═══════════════════════════════════════════════════════════════════════════════
#  CLAUDE CODE WIKI - HTTP API Server
#  Lightweight REST API for inter-agent communication
#═══════════════════════════════════════════════════════════════════════════════

# Find installation directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WIKI_HOME="$(dirname "$SCRIPT_DIR")"

# Source common library
source "$WIKI_HOME/lib/common.sh"

# Server configuration
WIKI_SERVER_PORT="${WIKI_SERVER_PORT:-3030}"
WIKI_SERVER_HOST="${WIKI_SERVER_HOST:-127.0.0.1}"
WIKI_SERVER_PID_FILE="$WIKI_STATE_DIR/wiki-server.pid"

#───────────────────────────────────────────────────────────────────────────────
# HTTP Response Helpers
#───────────────────────────────────────────────────────────────────────────────

http_response() {
    local status="$1"
    local content_type="${2:-application/json}"
    local body="$3"

    echo -e "HTTP/1.1 $status\r"
    echo -e "Content-Type: $content_type\r"
    echo -e "Access-Control-Allow-Origin: *\r"
    echo -e "Access-Control-Allow-Methods: GET, POST, OPTIONS\r"
    echo -e "Access-Control-Allow-Headers: Content-Type\r"
    echo -e "Connection: close\r"
    echo -e "\r"
    echo "$body"
}

json_response() {
    local status="$1"
    local json="$2"
    http_response "$status" "application/json" "$json"
}

json_error() {
    local status="$1"
    local message="$2"
    json_response "$status" "{\"error\": \"$message\"}"
}

json_success() {
    local data="$1"
    json_response "200 OK" "{\"success\": true, \"data\": $data}"
}

#───────────────────────────────────────────────────────────────────────────────
# API Handlers
#───────────────────────────────────────────────────────────────────────────────

handle_health() {
    local project_count=$(wiki_db_query "SELECT COUNT(*) FROM projects;" 2>/dev/null || echo "0")
    local file_count=$(wiki_db_query "SELECT COUNT(*) FROM files;" 2>/dev/null || echo "0")

    json_success "{
        \"status\": \"healthy\",
        \"version\": \"$WIKI_VERSION\",
        \"projects\": $project_count,
        \"files\": $file_count,
        \"database\": \"$WIKI_DB\"
    }"
}

handle_list() {
    wiki_db_init 2>/dev/null

    local projects=$(wiki_db_query "
        SELECT json_group_array(json_object(
            'name', name,
            'path', path,
            'type', type,
            'language', primary_language,
            'files', file_count,
            'has_context', has_context
        ))
        FROM projects
        ORDER BY last_indexed_at DESC;
    " 2>/dev/null)

    if [[ -z "$projects" || "$projects" == "[]" ]]; then
        projects="[]"
    fi

    json_success "$projects"
}

handle_search() {
    local query="$1"

    if [[ -z "$query" ]]; then
        json_error "400 Bad Request" "Query parameter required"
        return
    fi

    wiki_db_init 2>/dev/null

    # Search files table
    local results=$(wiki_db_query "
        SELECT json_group_array(json_object(
            'project', p.name,
            'path', f.path,
            'filename', f.filename,
            'extension', f.extension
        ))
        FROM files f
        JOIN projects p ON f.project_id = p.id
        WHERE f.filename LIKE '%$query%'
           OR f.path LIKE '%$query%'
        LIMIT 50;
    " 2>/dev/null)

    if [[ -z "$results" ]]; then
        results="[]"
    fi

    json_success "{\"query\": \"$query\", \"results\": $results}"
}

handle_info() {
    local project="$1"

    if [[ -z "$project" ]]; then
        json_error "400 Bad Request" "Project name required"
        return
    fi

    wiki_db_init 2>/dev/null

    local info=$(wiki_db_query "
        SELECT json_object(
            'name', name,
            'path', path,
            'type', type,
            'language', primary_language,
            'files', file_count,
            'has_context', has_context,
            'last_indexed', last_indexed_at
        )
        FROM projects
        WHERE name = '$project' OR path LIKE '%$project%'
        LIMIT 1;
    " 2>/dev/null)

    if [[ -z "$info" || "$info" == "null" ]]; then
        json_error "404 Not Found" "Project not found: $project"
        return
    fi

    json_success "$info"
}

handle_context() {
    local project="$1"

    if [[ -z "$project" ]]; then
        json_error "400 Bad Request" "Project name required"
        return
    fi

    # Find project path
    local project_path=$(wiki_db_query "SELECT path FROM projects WHERE name = '$project' LIMIT 1;" 2>/dev/null)

    if [[ -z "$project_path" ]]; then
        json_error "404 Not Found" "Project not found: $project"
        return
    fi

    local context_file="$project_path/GEMINI_CONTEXT.md"

    if [[ -f "$context_file" ]]; then
        # Return context as JSON with escaped content
        local content=$(cat "$context_file" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null)
        json_success "{\"project\": \"$project\", \"path\": \"$context_file\", \"content\": $content}"
    else
        json_error "404 Not Found" "No context file found. Run: wiki prepare $project_path"
    fi
}

handle_ask() {
    local question="$1"

    if [[ -z "$question" ]]; then
        json_error "400 Bad Request" "Question parameter required"
        return
    fi

    # Use the wiki search to find relevant files
    local search_results=$(wiki_db_query "
        SELECT p.name, f.path
        FROM files f
        JOIN projects p ON f.project_id = p.id
        WHERE f.filename LIKE '%${question}%'
           OR f.path LIKE '%${question}%'
        LIMIT 10;
    " 2>/dev/null)

    # Build response with suggestions
    json_success "{
        \"question\": $(echo "$question" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))'),
        \"suggestion\": \"Use wiki find or wiki prepare to get detailed context\",
        \"related_files\": \"$search_results\"
    }"
}

#───────────────────────────────────────────────────────────────────────────────
# Request Router
#───────────────────────────────────────────────────────────────────────────────

route_request() {
    local request="$1"

    # Parse HTTP request line
    local method=$(echo "$request" | head -1 | cut -d' ' -f1)
    local path=$(echo "$request" | head -1 | cut -d' ' -f2)

    # Handle CORS preflight
    if [[ "$method" == "OPTIONS" ]]; then
        http_response "200 OK" "text/plain" ""
        return
    fi

    # Parse path and query string
    local endpoint="${path%%\?*}"
    local query_string="${path#*\?}"

    # URL decode query parameter
    local query=""
    if [[ "$query_string" != "$path" ]]; then
        query=$(echo "$query_string" | sed 's/q=//' | sed 's/+/ /g' | python3 -c "import sys,urllib.parse; print(urllib.parse.unquote(sys.stdin.read().strip()))" 2>/dev/null)
    fi

    wiki_debug "Request: $method $endpoint query='$query'"

    # Route to handler
    case "$endpoint" in
        "/"|"/health")
            handle_health
            ;;
        "/list"|"/projects")
            handle_list
            ;;
        "/search"|"/find")
            handle_search "$query"
            ;;
        "/info")
            handle_info "$query"
            ;;
        "/context")
            handle_context "$query"
            ;;
        "/ask")
            handle_ask "$query"
            ;;
        *)
            json_error "404 Not Found" "Unknown endpoint: $endpoint"
            ;;
    esac
}

#───────────────────────────────────────────────────────────────────────────────
# Server Management
#───────────────────────────────────────────────────────────────────────────────

start_server() {
    wiki_init_dirs
    wiki_db_init 2>/dev/null

    # Check if already running
    if [[ -f "$WIKI_SERVER_PID_FILE" ]]; then
        local pid=$(cat "$WIKI_SERVER_PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            wiki_warn "Wiki server already running on PID $pid"
            wiki_info "Stop it with: wiki server stop"
            return 1
        fi
    fi

    wiki_info "Starting Wiki API Server on http://$WIKI_SERVER_HOST:$WIKI_SERVER_PORT"

    # Check for required tools
    if ! command -v nc &>/dev/null && ! command -v ncat &>/dev/null; then
        wiki_die "netcat (nc) required for server. Install with: brew install netcat"
    fi

    # Create named pipe for handling requests
    local pipe_dir="$WIKI_STATE_DIR/server"
    mkdir -p "$pipe_dir"
    local request_pipe="$pipe_dir/request.pipe"
    local response_pipe="$pipe_dir/response.pipe"

    # Cleanup old pipes
    rm -f "$request_pipe" "$response_pipe"
    mkfifo "$request_pipe" "$response_pipe"

    # Start server loop in background
    (
        while true; do
            # Read request, route it, write response
            cat "$request_pipe" | while read -r line; do
                request="$line"
                # Read remaining headers
                while read -r header && [[ -n "$header" && "$header" != $'\r' ]]; do
                    request="$request"$'\n'"$header"
                done
                route_request "$request"
                break
            done > "$response_pipe"
        done
    ) &

    local handler_pid=$!

    # Start netcat listener
    if command -v ncat &>/dev/null; then
        ncat -lk "$WIKI_SERVER_HOST" "$WIKI_SERVER_PORT" < "$response_pipe" > "$request_pipe" &
    else
        # Use basic nc (may need adjustments per platform)
        while true; do
            nc -l "$WIKI_SERVER_HOST" "$WIKI_SERVER_PORT" < "$response_pipe" > "$request_pipe"
        done &
    fi

    local server_pid=$!
    echo "$server_pid" > "$WIKI_SERVER_PID_FILE"

    wiki_info "Wiki API Server started (PID: $server_pid)"
    echo ""
    echo "API Endpoints:"
    echo "  GET /health        - Server status"
    echo "  GET /list          - List all projects"
    echo "  GET /search?q=     - Search files"
    echo "  GET /info?q=       - Project info"
    echo "  GET /context?q=    - Get GEMINI_CONTEXT.md"
    echo "  GET /ask?q=        - Natural language query"
    echo ""
    echo "Example: curl http://$WIKI_SERVER_HOST:$WIKI_SERVER_PORT/search?q=auth"
}

stop_server() {
    if [[ -f "$WIKI_SERVER_PID_FILE" ]]; then
        local pid=$(cat "$WIKI_SERVER_PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null
            wiki_info "Wiki server stopped (PID: $pid)"
        fi
        rm -f "$WIKI_SERVER_PID_FILE"
    else
        wiki_warn "No wiki server running"
    fi

    # Cleanup pipes
    rm -f "$WIKI_STATE_DIR/server/"*.pipe 2>/dev/null
}

server_status() {
    if [[ -f "$WIKI_SERVER_PID_FILE" ]]; then
        local pid=$(cat "$WIKI_SERVER_PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            wiki_info "Wiki server running on http://$WIKI_SERVER_HOST:$WIKI_SERVER_PORT (PID: $pid)"
            return 0
        fi
    fi
    wiki_info "Wiki server not running"
    return 1
}

#───────────────────────────────────────────────────────────────────────────────
# Main Entry Point
#───────────────────────────────────────────────────────────────────────────────

wiki_server() {
    local action="${1:-status}"

    case "$action" in
        start)
            start_server
            ;;
        stop)
            stop_server
            ;;
        restart)
            stop_server
            sleep 1
            start_server
            ;;
        status)
            server_status
            ;;
        *)
            echo "Usage: wiki server [start|stop|restart|status]"
            ;;
    esac
}

# If run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    wiki_server "$@"
fi
