-- ============================================================================
-- SELF-IMPROVING DEVELOPMENT JOURNAL
-- Migration 002: Complete schema for learning, reflection, and prediction
-- ============================================================================

-- ============================================================================
-- CORE JOURNAL TABLES
-- ============================================================================

-- Development sessions (groups related work with clear goals)
CREATE TABLE IF NOT EXISTS dev_sessions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    project_id INTEGER NOT NULL,
    start_time DATETIME NOT NULL DEFAULT (STRFTIME('%Y-%m-%d %H:%M:%f', 'NOW')),
    end_time DATETIME,
    goal TEXT NOT NULL,
    status TEXT DEFAULT 'IN_PROGRESS' CHECK(status IN ('IN_PROGRESS', 'COMPLETED', 'ABANDONED')),
    outcome_summary TEXT,
    -- Reflection metadata (populated by Reflector)
    reflection_status TEXT DEFAULT 'PENDING' CHECK(reflection_status IN ('PENDING', 'ANALYZED', 'SKIPPED')),
    winning_strategy TEXT,
    time_to_fix_ms INTEGER,
    hypothesis_count INTEGER,
    successful_hypothesis_id INTEGER,
    FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE
);

-- The journal itself (chronological event log with reasoning trails)
CREATE TABLE IF NOT EXISTS dev_journal (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    project_id INTEGER NOT NULL,
    session_id INTEGER,
    parent_id INTEGER,  -- For AI reasoning trails (hypothesis -> tool_call -> result)
    entry_type TEXT NOT NULL CHECK(entry_type IN (
        'SESSION_START', 'SESSION_END',
        'TEST_RUN', 'ERROR_LOG', 'FILE_CHANGE',
        'AI_TASK', 'AI_HYPOTHESIS', 'AI_TOOL_CALL', 'AI_OBSERVATION',
        'NOTE', 'COMMAND_RUN', 'BUILD_EVENT'
    )),
    timestamp DATETIME DEFAULT (STRFTIME('%Y-%m-%d %H:%M:%f', 'NOW')),
    summary TEXT NOT NULL,
    details TEXT,  -- JSON blob for structured data
    git_commit_hash TEXT,
    -- Analysis metadata (populated by Reflector)
    analysis_outcome TEXT CHECK(analysis_outcome IN ('SUCCESS', 'FAILURE', 'NEUTRAL', NULL)),
    approach_tags TEXT,  -- JSON array of extracted strategy tags
    FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE,
    FOREIGN KEY (session_id) REFERENCES dev_sessions(id) ON DELETE SET NULL,
    FOREIGN KEY (parent_id) REFERENCES dev_journal(id) ON DELETE CASCADE
);

-- ============================================================================
-- TEST TRACKING TABLES
-- ============================================================================

-- Normalized test run summaries
CREATE TABLE IF NOT EXISTS test_runs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    journal_entry_id INTEGER NOT NULL,
    status TEXT NOT NULL CHECK(status IN ('PASSED', 'FAILED', 'ERROR')),
    duration_ms INTEGER,
    total_tests INTEGER,
    passed_tests INTEGER,
    failed_tests INTEGER,
    skipped_tests INTEGER,
    source_file TEXT,  -- junit.xml, jest-results.json, etc.
    FOREIGN KEY (journal_entry_id) REFERENCES dev_journal(id) ON DELETE CASCADE
);

-- Individual test results (for flaky test detection)
CREATE TABLE IF NOT EXISTS test_results (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    test_run_id INTEGER NOT NULL,
    test_name TEXT NOT NULL,
    test_file TEXT,
    status TEXT NOT NULL CHECK(status IN ('PASSED', 'FAILED', 'SKIPPED', 'ERROR')),
    duration_ms INTEGER,
    error_message TEXT,
    error_signature TEXT,  -- Canonicalized for pattern matching
    stdout TEXT,
    stderr TEXT,
    FOREIGN KEY (test_run_id) REFERENCES test_runs(id) ON DELETE CASCADE
);

-- ============================================================================
-- KNOWLEDGE BASE TABLES (Self-Improving)
-- ============================================================================

-- Universal patterns (cross-project learning)
CREATE TABLE IF NOT EXISTS universal_patterns (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    signature TEXT NOT NULL UNIQUE,  -- Canonicalized error/issue fingerprint
    pattern_type TEXT DEFAULT 'error' CHECK(pattern_type IN ('error', 'flaky_test', 'build_failure', 'performance')),
    best_strategy TEXT,  -- Most successful approach tag
    success_count INTEGER DEFAULT 0,
    failure_count INTEGER DEFAULT 0,
    total_occurrences INTEGER DEFAULT 0,
    projects_seen TEXT,  -- JSON array of project IDs
    avg_time_to_fix_ms INTEGER,
    first_seen DATETIME DEFAULT (STRFTIME('%Y-%m-%d %H:%M:%f', 'NOW')),
    last_seen DATETIME DEFAULT (STRFTIME('%Y-%m-%d %H:%M:%f', 'NOW')),
    -- Strategy breakdown (JSON: {"mock-reset": 5, "cache-clear": 2})
    strategy_stats TEXT DEFAULT '{}'
);

-- Troubleshooting playbooks (curated knowledge)
CREATE TABLE IF NOT EXISTS troubleshooting_playbooks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    error_signature TEXT NOT NULL UNIQUE,
    title TEXT NOT NULL,
    context_summary TEXT NOT NULL,
    symptoms TEXT,  -- JSON array
    root_cause TEXT,
    solution_steps TEXT,  -- JSON array
    code_example TEXT,
    -- Evolution tracking
    success_count INTEGER DEFAULT 0,
    failure_count INTEGER DEFAULT 0,
    confidence_score REAL DEFAULT 0.5,
    -- Provenance
    source_session_ids TEXT,  -- JSON array
    project_id INTEGER,  -- NULL = global playbook
    created_at DATETIME DEFAULT (STRFTIME('%Y-%m-%d %H:%M:%f', 'NOW')),
    last_used_at DATETIME,
    last_evolved_at DATETIME,
    -- Status
    status TEXT DEFAULT 'ACTIVE' CHECK(status IN ('ACTIVE', 'ARCHIVED', 'DRAFT')),
    FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE SET NULL
);

-- Playbook usage log (for evolution)
CREATE TABLE IF NOT EXISTS playbook_usage_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    playbook_id INTEGER NOT NULL,
    session_id INTEGER,
    was_helpful BOOLEAN,
    feedback TEXT,
    used_at DATETIME DEFAULT (STRFTIME('%Y-%m-%d %H:%M:%f', 'NOW')),
    FOREIGN KEY (playbook_id) REFERENCES troubleshooting_playbooks(id) ON DELETE CASCADE,
    FOREIGN KEY (session_id) REFERENCES dev_sessions(id) ON DELETE SET NULL
);

-- ============================================================================
-- PREDICTIVE & PERSONALIZATION TABLES
-- ============================================================================

-- Predictive rules (learned correlations)
CREATE TABLE IF NOT EXISTS predictive_rules (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    trigger_pattern TEXT NOT NULL,  -- JSON: what event triggers this
    predicted_outcome TEXT NOT NULL,  -- JSON: what we predict
    advice TEXT NOT NULL,  -- Human-readable warning
    confidence REAL NOT NULL DEFAULT 0.5,
    occurrences INTEGER DEFAULT 0,
    correct_predictions INTEGER DEFAULT 0,
    project_id INTEGER,  -- NULL = global rule
    created_at DATETIME DEFAULT (STRFTIME('%Y-%m-%d %H:%M:%f', 'NOW')),
    last_triggered_at DATETIME,
    status TEXT DEFAULT 'ACTIVE' CHECK(status IN ('ACTIVE', 'TESTING', 'ARCHIVED')),
    FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE SET NULL
);

-- Developer preference model (personalization)
CREATE TABLE IF NOT EXISTS developer_preferences (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    preference_key TEXT NOT NULL UNIQUE,
    preference_value TEXT NOT NULL,  -- JSON value
    confidence REAL DEFAULT 0.5,
    observation_count INTEGER DEFAULT 1,
    updated_at DATETIME DEFAULT (STRFTIME('%Y-%m-%d %H:%M:%f', 'NOW'))
);

-- AI performance tracking (meta-learning)
CREATE TABLE IF NOT EXISTS ai_performance_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id INTEGER NOT NULL,
    hypothesis_count INTEGER,
    successful_hypothesis_index INTEGER,  -- Which hypothesis worked (1-indexed)
    approach_tags_tried TEXT,  -- JSON array of all approaches tried
    winning_approach_tag TEXT,
    time_to_first_hypothesis_ms INTEGER,
    time_to_fix_ms INTEGER,
    error_signature TEXT,
    outcome TEXT CHECK(outcome IN ('FIXED', 'PARTIAL', 'ABANDONED', 'FALSE_POSITIVE')),
    created_at DATETIME DEFAULT (STRFTIME('%Y-%m-%d %H:%M:%f', 'NOW')),
    FOREIGN KEY (session_id) REFERENCES dev_sessions(id) ON DELETE CASCADE
);

-- ============================================================================
-- INDEXES FOR PERFORMANCE
-- ============================================================================

-- Journal queries
CREATE INDEX IF NOT EXISTS idx_dev_journal_session ON dev_journal(session_id);
CREATE INDEX IF NOT EXISTS idx_dev_journal_project ON dev_journal(project_id);
CREATE INDEX IF NOT EXISTS idx_dev_journal_type ON dev_journal(entry_type);
CREATE INDEX IF NOT EXISTS idx_dev_journal_timestamp ON dev_journal(timestamp);

-- Test result queries
CREATE INDEX IF NOT EXISTS idx_test_results_name ON test_results(test_name);
CREATE INDEX IF NOT EXISTS idx_test_results_status ON test_results(status);
CREATE INDEX IF NOT EXISTS idx_test_results_signature ON test_results(error_signature);

-- Pattern matching
CREATE INDEX IF NOT EXISTS idx_universal_patterns_sig ON universal_patterns(signature);
CREATE INDEX IF NOT EXISTS idx_playbooks_signature ON troubleshooting_playbooks(error_signature);
CREATE INDEX IF NOT EXISTS idx_playbooks_confidence ON troubleshooting_playbooks(confidence_score);

-- Session queries
CREATE INDEX IF NOT EXISTS idx_dev_sessions_project ON dev_sessions(project_id);
CREATE INDEX IF NOT EXISTS idx_dev_sessions_status ON dev_sessions(status);

-- ============================================================================
-- VIEWS FOR COMMON QUERIES
-- ============================================================================

-- Flaky tests view (tests that sometimes pass, sometimes fail)
CREATE VIEW IF NOT EXISTS flaky_tests AS
SELECT
    tr.test_name,
    tr.test_file,
    COUNT(*) as total_runs,
    SUM(CASE WHEN tr.status = 'PASSED' THEN 1 ELSE 0 END) as passes,
    SUM(CASE WHEN tr.status = 'FAILED' THEN 1 ELSE 0 END) as failures,
    ROUND(100.0 * SUM(CASE WHEN tr.status = 'FAILED' THEN 1 ELSE 0 END) / COUNT(*), 1) as flakiness_pct,
    MAX(dj.timestamp) as last_run
FROM test_results tr
JOIN test_runs run ON tr.test_run_id = run.id
JOIN dev_journal dj ON run.journal_entry_id = dj.id
WHERE dj.timestamp > datetime('now', '-30 days')
GROUP BY tr.test_name, tr.test_file
HAVING passes > 0 AND failures > 0
ORDER BY flakiness_pct DESC;

-- Top debugging strategies view
CREATE VIEW IF NOT EXISTS top_strategies AS
SELECT
    json_each.value as strategy,
    COUNT(*) as uses,
    SUM(CASE WHEN dj.analysis_outcome = 'SUCCESS' THEN 1 ELSE 0 END) as successes,
    ROUND(100.0 * SUM(CASE WHEN dj.analysis_outcome = 'SUCCESS' THEN 1 ELSE 0 END) / COUNT(*), 1) as success_rate
FROM dev_journal dj, json_each(dj.approach_tags)
WHERE dj.entry_type = 'AI_HYPOTHESIS'
  AND dj.approach_tags IS NOT NULL
GROUP BY json_each.value
HAVING uses >= 3
ORDER BY success_rate DESC, uses DESC;

-- Recent sessions summary view
CREATE VIEW IF NOT EXISTS recent_sessions AS
SELECT
    s.id,
    p.name as project,
    s.goal,
    s.status,
    s.winning_strategy,
    s.time_to_fix_ms,
    s.hypothesis_count,
    s.start_time,
    s.end_time
FROM dev_sessions s
JOIN projects p ON s.project_id = p.id
ORDER BY s.start_time DESC
LIMIT 50;

-- High-confidence playbooks view
CREATE VIEW IF NOT EXISTS trusted_playbooks AS
SELECT
    id,
    title,
    error_signature,
    confidence_score,
    success_count,
    failure_count,
    CASE WHEN project_id IS NULL THEN 'Global' ELSE 'Project-specific' END as scope
FROM troubleshooting_playbooks
WHERE status = 'ACTIVE' AND confidence_score >= 0.7
ORDER BY confidence_score DESC;

-- ============================================================================
-- MAINTENANCE
-- ============================================================================

-- Record migration
INSERT OR IGNORE INTO context_cache (project_id, context_type, content, generated_at)
VALUES (0, 'migration', 'self_improving_journal_v002', datetime('now'));
