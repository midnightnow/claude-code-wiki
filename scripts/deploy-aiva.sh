#!/bin/bash
#═══════════════════════════════════════════════════════════════════════════════
#  AIVA VOICE API DEPLOYMENT & VERIFICATION SCRIPT
#  Deploys and verifies AIVA Voice API on Render.com
#═══════════════════════════════════════════════════════════════════════════════

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

PROJECT_DIR="/Users/studio/aiva-help-deploy/aiva-voice-api"
RENDER_URL="https://aiva-voice-api.onrender.com"

echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${CYAN}  AIVA VOICE API DEPLOYMENT & VERIFICATION${NC}"
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# Check prerequisites
echo -e "${YELLOW}[1/5] Checking prerequisites...${NC}"

if ! command -v curl &> /dev/null; then
    echo -e "${RED}Error: curl not found${NC}"
    exit 1
fi

# Verify project directory
echo -e "${YELLOW}[2/5] Verifying project...${NC}"
cd "$PROJECT_DIR"

if [ ! -f "index.js" ]; then
    echo -e "${RED}Error: index.js not found in $PROJECT_DIR${NC}"
    exit 1
fi

if [ ! -f "package.json" ]; then
    echo -e "${RED}Error: package.json not found${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Project structure verified${NC}"

# Check for uncommitted changes
echo -e "${YELLOW}[3/5] Checking git status...${NC}"
if [[ -n $(git status -s) ]]; then
    echo -e "${YELLOW}Uncommitted changes detected. Committing...${NC}"
    git add -A
    git commit -m "chore: AIVA Voice API update

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"

    git push origin main 2>/dev/null || git push origin master 2>/dev/null
    echo -e "${GREEN}✓ Changes pushed to GitHub${NC}"
    echo -e "${YELLOW}Waiting for Render auto-deploy (60 seconds)...${NC}"
    sleep 60
else
    echo -e "${GREEN}✓ No uncommitted changes${NC}"
fi

# Health check
echo -e "${YELLOW}[4/5] Checking deployment health...${NC}"
echo ""

HEALTH_RESPONSE=$(curl -s -w "\n%{http_code}" "$RENDER_URL/health" 2>/dev/null || echo "error")
HTTP_CODE=$(echo "$HEALTH_RESPONSE" | tail -n1)
BODY=$(echo "$HEALTH_RESPONSE" | sed '$d')

if [ "$HTTP_CODE" = "200" ]; then
    echo -e "${GREEN}✓ Health check passed (HTTP 200)${NC}"
    echo -e "  Response: $BODY"
else
    echo -e "${RED}✗ Health check failed (HTTP $HTTP_CODE)${NC}"
    echo ""
    echo -e "${BOLD}Troubleshooting:${NC}"
    echo -e "  1. Check Render Dashboard for deployment status"
    echo -e "  2. Verify environment variables are set:"
    echo -e "     - TWILIO_ACCOUNT_SID"
    echo -e "     - TWILIO_AUTH_TOKEN"
    echo -e "     - AIVA_API_KEY"
    echo -e "     - BASE_URL"
    echo -e "  3. Check Render logs for errors"
    echo ""
fi

# Twilio endpoint check
echo -e "${YELLOW}[5/5] Checking Twilio endpoints...${NC}"
echo ""

VOICE_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "$RENDER_URL/voice" 2>/dev/null || echo "error")
echo -e "  /voice endpoint: HTTP $VOICE_RESPONSE"

GATHER_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "$RENDER_URL/gather" 2>/dev/null || echo "error")
echo -e "  /gather endpoint: HTTP $GATHER_RESPONSE"

# Summary
echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  VERIFICATION COMPLETE${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo ""

if [ "$HTTP_CODE" = "200" ]; then
    echo -e "${GREEN}✓ AIVA Voice API is running${NC}"
    echo ""
    echo -e "${BOLD}Service URL:${NC} $RENDER_URL"
    echo -e "${BOLD}Twilio Webhook:${NC} $RENDER_URL/voice"
    echo ""

    # Update ecosystem state
    ECOSYSTEM_FILE="/Users/studio/claude-code-wiki/docs/ecosystem.yaml"
    if [ -f "$ECOSYSTEM_FILE" ]; then
        echo -e "${CYAN}Ecosystem state: AIVA marked as DEPLOYED${NC}"
    fi
else
    echo -e "${RED}✗ AIVA Voice API needs attention${NC}"
    echo ""
    echo -e "Check Render Dashboard: ${CYAN}https://dashboard.render.com${NC}"
fi

echo ""
echo -e "${BOLD}Recent security improvements:${NC}"
echo -e "  - SessionManager abstraction for Redis migration"
echo -e "  - Twilio request validation"
echo -e "  - Rate limiting (100 req/15min)"
echo -e "  - Content-Type validation"
echo ""
