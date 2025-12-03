#!/bin/bash
#═══════════════════════════════════════════════════════════════════════════════
#  VETSORCERY BACKEND DEPLOYMENT SCRIPT
#  One-click deployment to Render.com
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

PROJECT_DIR="/Users/studio/vetsorcery"
RENDER_SERVICE="vetsorcery-api"

echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${CYAN}  VETSORCERY BACKEND DEPLOYMENT${NC}"
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# Check prerequisites
echo -e "${YELLOW}[1/6] Checking prerequisites...${NC}"

if ! command -v git &> /dev/null; then
    echo -e "${RED}Error: git not found${NC}"
    exit 1
fi

if ! command -v render &> /dev/null; then
    echo -e "${YELLOW}Warning: Render CLI not installed. Using git push method.${NC}"
    USE_GIT=true
else
    USE_GIT=false
fi

# Verify project directory
echo -e "${YELLOW}[2/6] Verifying project...${NC}"
cd "$PROJECT_DIR"

if [ ! -f "render.yaml" ]; then
    echo -e "${RED}Error: render.yaml not found in $PROJECT_DIR${NC}"
    exit 1
fi

if [ ! -f "Dockerfile" ]; then
    echo -e "${RED}Error: Dockerfile not found${NC}"
    exit 1
fi

if [ ! -f "main_production.py" ]; then
    echo -e "${RED}Error: main_production.py not found${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Project structure verified${NC}"

# Check for uncommitted changes
echo -e "${YELLOW}[3/6] Checking git status...${NC}"
if [[ -n $(git status -s) ]]; then
    echo -e "${YELLOW}Uncommitted changes detected. Committing...${NC}"
    git add -A
    git commit -m "chore: pre-deployment commit

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
fi

# Push to GitHub
echo -e "${YELLOW}[4/6] Pushing to GitHub...${NC}"
git push origin main 2>/dev/null || git push origin master 2>/dev/null || {
    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
    git push origin "$CURRENT_BRANCH"
}
echo -e "${GREEN}✓ Code pushed to GitHub${NC}"

# Deploy instruction
echo -e "${YELLOW}[5/6] Deployment instructions...${NC}"
echo ""
echo -e "${BOLD}If this is your first deployment:${NC}"
echo -e "  1. Go to ${CYAN}https://dashboard.render.com${NC}"
echo -e "  2. Click ${BOLD}New > Blueprint${NC}"
echo -e "  3. Connect your GitHub repo: ${CYAN}vetsorcery${NC}"
echo -e "  4. Render will auto-detect render.yaml"
echo ""
echo -e "${BOLD}Set these secrets in Render Dashboard:${NC}"
echo -e "  ${YELLOW}TWILIO_ACCOUNT_SID${NC}     - From Twilio Console"
echo -e "  ${YELLOW}TWILIO_AUTH_TOKEN${NC}      - From Twilio Console"
echo -e "  ${YELLOW}TWILIO_PHONE_NUMBER${NC}    - Your Twilio number (+1...)"
echo -e "  ${YELLOW}OPENAI_API_KEY${NC}         - From OpenAI Platform"
echo -e "  ${YELLOW}FIREBASE_SERVICE_ACCOUNT_KEY${NC} - Base64 encoded JSON"
echo ""

# Verify deployment
echo -e "${YELLOW}[6/6] Post-deployment verification...${NC}"
echo ""
echo -e "${BOLD}After deployment, verify with:${NC}"
echo -e "  ${CYAN}curl https://vetsorcery-api.onrender.com/health${NC}"
echo ""
echo -e "${BOLD}Configure Twilio webhook to:${NC}"
echo -e "  ${CYAN}https://vetsorcery-api.onrender.com/api/v1/phone/incoming${NC}"
echo ""

# Summary
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  DEPLOYMENT PREPARED${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "Code is on GitHub. Complete deployment in Render Dashboard."
echo ""
echo -e "${BOLD}Estimated time to live:${NC} 5-10 minutes after secrets are set"
echo -e "${BOLD}Monthly cost:${NC} ~\$7 (Render Starter) + usage"
echo ""

# Update ecosystem state
ECOSYSTEM_FILE="/Users/studio/claude-code-wiki/docs/ecosystem.yaml"
if [ -f "$ECOSYSTEM_FILE" ]; then
    echo -e "${CYAN}Updating ecosystem state...${NC}"
    # Mark as deployment initiated
    sed -i '' 's/status: "NOT_DEPLOYED"/status: "DEPLOYING"/' "$ECOSYSTEM_FILE" 2>/dev/null || true
fi

echo -e "${GREEN}Done! Complete deployment at https://dashboard.render.com${NC}"
