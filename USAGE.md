# Self-Improving Development Journal: User Manual

> **System Status:** ACTIVE
> **Role:** Operational Intelligence Engine
> **Goal:** Compounding Knowledge from every debugging session.

This system transforms the wiki from a passive code index into an active learning partner. It watches your work, learns from your solutions, and proactively assists in future debugging sessions.

---

## The "Golden Loop" Workflow

To train the system, follow this cycle for every task:

### 1. Start a Session (Intent)

Tell the system what you are doing. This sets the context.

```bash
wiki session start "project-name" "Fixing the flaky auth test"
```

### 2. Do the Work (Action)

**Run Tests:** The Sentinel watches `junit.xml` automatically. Just run `npm test`.

**Log Thoughts:** If you have a hypothesis, log it. This helps the AI connect "Thinking" to "Results".

```bash
wiki journal log AI_HYPOTHESIS "The token might be expiring too fast"
```

### 3. Get Intelligence (Support)

Ask the system what it knows about this context.

```bash
wiki briefing
```

*Output: "I've seen this error 3 times. The 'mock-reset' strategy worked 80% of the time."*

### 4. Close & Reflect (Learning)

**Crucial Step.** When you finish (success or failure), close the session.

```bash
wiki session end <id> --summary "Fixed by adding cleanup in afterEach hook"
```

**Trigger:** This wakes up the Reflector.
**Action:** It analyzes the timeline, links the Error to the Fix, and updates the `universal_patterns` database.

---

## CLI Command Reference

| Command | Arguments | Description |
|---------|-----------|-------------|
| `wiki session start` | `<project> <goal>` | Starts a new tracking session |
| `wiki session end` | `<id> --summary <outcome>` | Ends the session and triggers the Reflector |
| `wiki session list` | `[limit]` | Shows recent sessions |
| `wiki session show` | `<id>` | Shows session details |
| `wiki journal` | `[limit]` | Shows recent journal entries |
| `wiki journal log` | `<type> <text>` | Logs an event manually (e.g., NOTE, AI_HYPOTHESIS) |
| `wiki briefing` | | Generates AI prompt based on project history |
| `wiki stats` | | Displays learning metrics (patterns, playbooks) |
| `wiki reflect` | `[session_id]` | Manually trigger reflection |
| `wiki playbooks` | `[error]` | Show/search troubleshooting playbooks |
| `wiki tests flaky` | `[limit]` | Show flaky tests detected |

### Entry Types for `wiki journal log`

- `AI_HYPOTHESIS` - Your theory about the problem
- `AI_OBSERVATION` - What you observed
- `NOTE` - General notes
- `ERROR_LOG` - Error messages
- `COMMAND_RUN` - Commands executed
- `BUILD_EVENT` - Build-related events

---

## How It Works (The Architecture)

### 1. The Memory (SQLite)

```
~/.local/share/claude-wiki/wiki.db
```

| Table | Purpose |
|-------|---------|
| `dev_sessions` | Container for a unit of work |
| `dev_journal` | Chronological timeline (Errors, Tests, Hypotheses) |
| `universal_patterns` | Cross-project knowledge base |
| `troubleshooting_playbooks` | Proven solutions with confidence scores |
| `test_runs` | Test execution history |
| `test_results` | Individual test outcomes |

### 2. The Eyes (Sentinel)

A background watcher that monitors:

- `junit.xml` / `jest-results.json`: Auto-logs `TEST_RUN` and `ERROR_LOG` events
- File changes: Links code edits to session outcomes

### 3. The Brain (Reflector)

Run automatically at session end. It performs Reinforcement Learning:

1. Reconstructs the reasoning trail
2. Identifies the "Winning Hypothesis" (the one preceding the fix)
3. Extracts Strategy Tags (e.g., `mock-reset`, `cache-clear`, `null-check`)
4. Updates confidence scores in the Knowledge Base

---

## Viewing Intelligence

To see what the system has learned:

```bash
# See the most successful debugging strategies
sqlite3 ~/.local/share/claude-wiki/wiki.db "SELECT * FROM top_strategies"

# See high-confidence playbooks
sqlite3 ~/.local/share/claude-wiki/wiki.db "SELECT * FROM trusted_playbooks"

# See universal patterns
sqlite3 ~/.local/share/claude-wiki/wiki.db "SELECT * FROM universal_patterns"

# See flaky tests
sqlite3 ~/.local/share/claude-wiki/wiki.db "SELECT * FROM flaky_tests"
```

---

## Strategy Tags (Common)

The system recognizes and tracks these debugging strategies:

| Tag | Meaning |
|-----|---------|
| `mock-reset` | Reset mocks between tests |
| `cache-clear` | Clear cached data |
| `null-check` | Add defensive null checks |
| `defensive-coding` | Add guard clauses |
| `async-await` | Fix async/await issues |
| `type-coercion` | Fix type conversion bugs |
| `race-condition` | Fix timing/concurrency issues |
| `env-config` | Environment configuration fix |
| `dependency-update` | Update dependencies |

---

## System Timeline

| Time | System Behavior |
|------|-----------------|
| Week 1 | Collects error signatures, stores raw patterns |
| Week 2 | `wiki briefing` starts surfacing relevant past solutions |
| Week 4 | High-confidence playbooks emerge for recurring issues |
| Month 2+ | 30-minute debugging → 30-second fix via institutional memory |

---

## Quick Start

```bash
# Start your first tracked debugging session
wiki session start "my-project" "Fix login timeout"

# Work normally... run tests
npm test

# Log a hypothesis when you have one
wiki journal log AI_HYPOTHESIS "Session token expiring prematurely"

# When fixed, end the session
wiki session end 1 --summary "Extended token TTL from 1h to 24h"

# Check what the system learned
wiki stats
```

---

## Troubleshooting

### Session not starting?

```bash
# Check if sentinel is built
ls ~/claude-code-wiki/sentinel/dist/index.js

# Rebuild if needed
cd ~/claude-code-wiki/sentinel && npm run build
```

### Database not found?

```bash
# Run wiki scan to initialize
wiki scan
```

### Reflector not triggering?

The Reflector runs automatically when you use `wiki session end`. Check the output for:

```
🧠 Reflector: Analyzing session N...
```

---

## File Locations

| Component | Path |
|-----------|------|
| Wiki CLI | `~/claude-code-wiki/bin/wiki` |
| Sentinel | `~/claude-code-wiki/sentinel/dist/index.js` |
| Database | `~/.local/share/claude-wiki/wiki.db` |
| Config | `~/.config/claude-wiki/config.json` |

---

**Last Updated:** 2025-12-03
**System Version:** 1.0
**Status:** ACTIVE
