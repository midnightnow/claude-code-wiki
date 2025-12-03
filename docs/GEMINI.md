# Hardcard Ecosystem Context for Gemini CLI

> **Last Updated:** 2025-12-03
> **Purpose:** Central context file for Gemini CLI integration

---

## Quick Reference

### Ecosystem State File
```
/Users/studio/claude-code-wiki/docs/ecosystem.yaml
```

This YAML file is the **single source of truth** for all project states, blockers, and next actions.

### Priority Commands

```bash
# Check all service health
/Users/studio/claude-code-wiki/scripts/ecosystem-status.sh

# Deploy VetSorcery backend (CRITICAL - $10K MRR blocked)
/Users/studio/claude-code-wiki/scripts/deploy-vetsorcery.sh

# Verify AIVA Voice API
/Users/studio/claude-code-wiki/scripts/deploy-aiva.sh

# Audit Firebase projects
/Users/studio/claude-code-wiki/scripts/firebase-audit.sh
```

---

## Active Projects by Priority

### Tier 0: Critical (Revenue Blocking)

| Project | Status | Blocker | Next Action |
|---------|--------|---------|-------------|
| **VetSorcery** | BACKEND_NOT_DEPLOYED | FastAPI not on Render | Deploy with render.yaml |
| **AIVA Help** | MONITORING | Needs verification | Check /health endpoint |

### Tier 1: High (Ready for Launch)

| Project | Status | URL |
|---------|--------|-----|
| Influential Digital | DEPLOYED | https://influential.digital |
| Business Basics | DEPLOYED | https://businessbasics.site |

---

## Key File Locations

### VetSorcery
```
Root:           /Users/studio/vetsorcery
Backend:        /Users/studio/vetsorcery/main_production.py
Deployment:     /Users/studio/vetsorcery/render.yaml
Env Guide:      /Users/studio/vetsorcery/DEPLOYMENT_ENV_VARS.md
Blockers:       /Users/studio/vetsorcery/LAUNCH_BLOCKER_REPORT.md
```

### AIVA Help
```
Root:           /Users/studio/aiva-help-deploy
Voice API:      /Users/studio/aiva-help-deploy/aiva-voice-api/index.js
Env Example:    /Users/studio/aiva-help-deploy/aiva-voice-api/.env.example
Production:     https://aiva-voice-api.onrender.com
```

### Influential Digital
```
Root:           /Users/studio/influential-digital-site
Firebase:       influential-digital-2025
Production:     https://influential.digital
```

### Business Basics
```
Root:           /Users/studio/portfolio-businessbasics
Firebase:       businessbasics
Functions:      /quoteRequest, /submitApplication
Production:     https://businessbasics.site
```

---

## Environment Variables Required

### VetSorcery (Render.com)
```
TWILIO_ACCOUNT_SID      # Twilio Console
TWILIO_AUTH_TOKEN       # Twilio Console
TWILIO_PHONE_NUMBER     # +1XXXXXXXXXX format
OPENAI_API_KEY          # OpenAI Platform
FIREBASE_SERVICE_ACCOUNT_KEY  # Base64 encoded JSON
ALLOWED_HOST            # vetsorcery-api.onrender.com
FRONTEND_URL            # https://vetsorcery.com
ENVIRONMENT             # production
```

### AIVA Voice API (Render.com)
```
TWILIO_ACCOUNT_SID      # Twilio Console
TWILIO_AUTH_TOKEN       # Twilio Console
AIVA_API_KEY            # Internal API key
BASE_URL                # https://aiva-voice-api.onrender.com
```

---

## Revenue Unlocking Path

```
Current MRR:     $0
Potential MRR:   $21,000

Quick Wins:
├── [2 hours] Deploy VetSorcery backend    → +$10,000/mo
├── [30 min]  Configure Stripe (Influential) → +$3,000/mo
└── [ongoing] Client onboarding (AIVA)     → +$5,000/mo
```

---

## Integration with Claude Code Wiki

The wiki system at `/Users/studio/claude-code-wiki` provides:

1. **SQLite Index**: Project metadata searchable via `wiki find <term>`
2. **Scripts**: Automated deployment and status checks
3. **GEMINI_CONTEXT.md**: Per-project context files for deep dives
4. **ecosystem.yaml**: Structured state for programmatic access

### Wiki Commands
```bash
# Search wiki
wiki find "vetsorcery deployment"

# Scan for new projects
wiki scan /Users/studio

# Health check
wiki health
```

---

## Recent Session Findings (2025-12-03)

1. **VetSorcery**: Frontend deployed, backend missing. Created render.yaml for one-click deployment.

2. **AIVA Help**: Security refactoring pushed (SessionManager, Twilio validation, rate limiting). Awaiting verification.

3. **Firebase Sprawl**: 20+ projects identified. Audit script created to categorize active vs dormant.

4. **Documentation Gap**: Shifted from prose to structured YAML state for machine-readability.

---

## For Gemini CLI Sessions

When starting a new session, load context with:

```bash
# Via clink
gemini "Read /Users/studio/claude-code-wiki/docs/ecosystem.yaml and summarize blockers"

# Direct reference
cat /Users/studio/claude-code-wiki/docs/ecosystem.yaml
```

The ecosystem.yaml file contains:
- All project states
- Deployment configurations
- Blocker details
- Revenue potential
- Next actions

---

*This file is maintained by Claude Code Wiki system*
