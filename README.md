# Claude Code Wiki

[![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)](https://github.com/patrickdellis/claude-code-wiki)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey.svg)]()

**Ultra-Agentic Wiki System for Claude Code** - A persistent, auto-updating, multi-model codebase understanding system.

## Features

- **SQLite-Backed Indexing** - Fast cross-project search across your entire codebase
- **Smart Context Generation** - Auto-generates AI-optimized context manifests
- **Multi-Model Routing** - Routes queries to optimal AI model based on task type
- **Self-Healing System** - Built-in diagnostics, health checks, and auto-repair
- **Claude Code Integration** - Native slash commands for seamless workflow
- **Terminal Access** - Full CLI for direct terminal usage
- **XDG Compliant** - Follows XDG Base Directory Specification

## Quick Install

```bash
curl -sL https://raw.githubusercontent.com/patrickdellis/claude-code-wiki/main/install.sh | bash
```

Or clone and install:

```bash
git clone https://github.com/patrickdellis/claude-code-wiki.git
cd claude-code-wiki
./setup.sh
```

## Requirements

- **Required:** `sqlite3`, `bash` 4.0+
- **Optional:** `jq` (JSON parsing), `tree` (structure display)
- **Recommended:** Gemini CLI for multi-model support

## Usage

### Terminal Commands

```bash
# Index all projects in home directory
wiki scan

# Search across all indexed projects
wiki find "authentication"

# List all indexed projects
wiki list

# Get detailed info about a project
wiki info myproject

# Generate AI context manifest
wiki prepare ~/myproject

# Run health check
wiki health

# Auto-fix issues
wiki fix

# Jump to project directory (with cdp)
cdp myproject
```

### Claude Code Slash Commands

| Command | Description |
|---------|-------------|
| `/wiki-scan` | Index all projects |
| `/wiki-find <query>` | Search across projects |
| `/wiki-prepare <path>` | Generate context manifest |
| `/wiki-health` | Run diagnostics |

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    CLAUDE CODE WIKI SYSTEM                      │
├─────────────────────────────────────────────────────────────────┤
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐      │
│  │ Wiki Indexer │───▶│  SQLite DB   │◀───│ Auto-Update  │      │
│  │   (scan)     │    │ (wiki.db)    │    │  (hooks)     │      │
│  └──────────────┘    └──────────────┘    └──────────────┘      │
│          │                  │                    │              │
│          ▼                  ▼                    ▼              │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │              Smart Context Generator                      │  │
│  │           (GEMINI_CONTEXT.md per project)                │  │
│  └──────────────────────────────────────────────────────────┘  │
│                           │                                     │
│          ┌────────────────┼────────────────┐                   │
│          ▼                ▼                ▼                   │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐           │
│  │ Gemini 2.5   │ │   Claude     │ │   GPT-5      │           │
│  │ (breadth)    │ │ (precision)  │ │ (consensus)  │           │
│  └──────────────┘ └──────────────┘ └──────────────┘           │
└─────────────────────────────────────────────────────────────────┘
```

## Directory Structure

```
~/.config/claude-wiki/      # Configuration
├── config.json             # User settings

~/.local/share/claude-wiki/ # Data
├── wiki.db                 # SQLite database

~/.local/state/claude-wiki/ # State
├── wiki.log                # Log file
├── wiki.lock               # Lock file

~/.cache/claude-wiki/       # Cache
└── ...                     # Temporary files
```

## Configuration

Edit configuration:

```bash
wiki config edit
```

Default `config.json`:

```json
{
    "version": "1.0.0",
    "project_dirs": ["~"],
    "default_model": "gemini-2.5-pro",
    "auto_index": true,
    "excluded_patterns": ["node_modules", ".git", "dist", "build"],
    "index_depth": 4
}
```

## Context Manifest

The `wiki prepare` command generates a `GEMINI_CONTEXT.md` file containing:

- Project overview and metadata
- Directory structure
- Key configuration files
- Dependencies list
- Architecture patterns detected
- Entry points and run commands
- Quick reference for AI assistants

This file is optimized for large context windows (1M+ tokens) and helps AI assistants understand your project quickly.

## Health System

The wiki includes self-monitoring capabilities:

```bash
# Run full health check
wiki health

# Auto-fix detected issues
wiki fix
```

Health checks include:
- Required dependency verification
- Database integrity
- Configuration validity
- Lock file status
- Log rotation
- Claude integration status

## Updating

```bash
wiki update
```

Or manually:

```bash
cd ~/.local/share/claude-code-wiki
git pull origin main
./setup.sh
```

## Uninstalling

```bash
wiki uninstall
```

This will:
- Remove shell integration
- Remove Claude commands
- Optionally remove database and config

## Integration with Gemini CLI

For multi-model support, install Gemini CLI:

```bash
npm install -g @google/gemini-cli
```

Recommended extensions:

```bash
gemini extensions install https://github.com/upstash/context7
gemini extensions install https://github.com/exa-labs/exa-mcp-server
```

## Project Detection

The indexer automatically detects project types:

| Indicator | Type |
|-----------|------|
| `firebase.json` | Firebase |
| `next.config.js` | Next.js |
| `package.json` + `tsconfig.json` | TypeScript |
| `package.json` | Node.js |
| `requirements.txt` | Python |
| `pyproject.toml` | Python (modern) |
| `go.mod` | Go |
| `Cargo.toml` | Rust |
| `pom.xml` | Java (Maven) |
| `build.gradle` | Java (Gradle) |

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run `wiki health` to verify
5. Submit a pull request

## License

MIT License - see [LICENSE](LICENSE) for details.

## Credits

Created by Patrick Ellis for the Claude Code ecosystem.

---

**Version:** 1.0.0
**Last Updated:** 2024-12-03
