#!/bin/bash
#═══════════════════════════════════════════════════════════════════════════════
#  FIREBASE PROJECT AUDIT SCRIPT
#  Identifies active vs abandoned Firebase projects
#═══════════════════════════════════════════════════════════════════════════════

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${CYAN}  FIREBASE PROJECT AUDIT${NC}"
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# Check if firebase CLI is available
if ! command -v firebase &> /dev/null; then
    echo -e "${RED}Error: Firebase CLI not found. Install with: npm install -g firebase-tools${NC}"
    exit 1
fi

# Output file
OUTPUT_FILE="/Users/studio/FIREBASE_AUDIT_$(date +%Y%m%d_%H%M%S).md"

echo "# Firebase Project Audit" > "$OUTPUT_FILE"
echo "Generated: $(date)" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# Get all projects
echo -e "${YELLOW}Fetching Firebase projects...${NC}"
PROJECTS=$(firebase projects:list --json 2>/dev/null || echo "[]")

if [ "$PROJECTS" = "[]" ]; then
    echo -e "${RED}No projects found or not authenticated. Run: firebase login${NC}"
    exit 1
fi

# Parse projects
PROJECT_COUNT=$(echo "$PROJECTS" | python3 -c "import json,sys; data=json.load(sys.stdin); print(len(data.get('result', [])))" 2>/dev/null || echo "0")

echo -e "${GREEN}Found ${PROJECT_COUNT} Firebase projects${NC}"
echo ""
echo "## Summary" >> "$OUTPUT_FILE"
echo "- Total Projects: $PROJECT_COUNT" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# Categories
echo "## Project Analysis" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# Active projects (have hosting, functions, or recent activity)
echo "### Likely Active Projects" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"
echo "| Project | ID | Status |" >> "$OUTPUT_FILE"
echo "|---------|-------|--------|" >> "$OUTPUT_FILE"

# Analyze each project
ACTIVE_COUNT=0
DORMANT_COUNT=0
UNKNOWN_COUNT=0

# Get project list as array
echo "$PROJECTS" | python3 -c "
import json
import sys

data = json.load(sys.stdin)
projects = data.get('result', [])

for p in projects:
    project_id = p.get('projectId', 'unknown')
    display_name = p.get('displayName', project_id)
    resources = p.get('resources', {})

    # Simple heuristics for activity
    has_hosting = resources.get('hostingSite') is not None
    has_storage = resources.get('storageBucket') is not None
    has_rtdb = resources.get('realtimeDatabaseInstance') is not None

    # Output in parseable format
    print(f'{project_id}|{display_name}|{has_hosting}|{has_storage}|{has_rtdb}')
" 2>/dev/null | while IFS='|' read -r PROJECT_ID DISPLAY_NAME HAS_HOSTING HAS_STORAGE HAS_RTDB; do
    # Check if project has hosting sites
    echo -ne "${CYAN}Checking ${PROJECT_ID}...${NC}\r"

    # Try to get hosting sites
    HOSTING_SITES=$(firebase hosting:sites:list --project "$PROJECT_ID" --json 2>/dev/null || echo "{}")
    SITE_COUNT=$(echo "$HOSTING_SITES" | python3 -c "import json,sys; data=json.load(sys.stdin); sites=data.get('result',{}).get('sites',[]); print(len(sites))" 2>/dev/null || echo "0")

    # Determine status
    if [ "$SITE_COUNT" -gt 0 ]; then
        STATUS="ACTIVE"
        echo "| $DISPLAY_NAME | $PROJECT_ID | ${GREEN}$STATUS${NC} |" >> "$OUTPUT_FILE"
    elif [ "$HAS_HOSTING" = "True" ] || [ "$HAS_STORAGE" = "True" ]; then
        STATUS="PROBABLY ACTIVE"
        echo "| $DISPLAY_NAME | $PROJECT_ID | ${YELLOW}$STATUS${NC} |" >> "$OUTPUT_FILE"
    else
        STATUS="DORMANT?"
        echo "| $DISPLAY_NAME | $PROJECT_ID | ${RED}$STATUS${NC} |" >> "$OUTPUT_FILE"
    fi
done

echo ""
echo "### Potentially Dormant Projects" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"
echo "Review these projects for cleanup:" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# Known active project IDs (from your ecosystem)
KNOWN_ACTIVE="
vetsorcery
aiva-help
hardcard
influential-digital-2025
businessbasics
hempex-92344
cairns-news
"

# List projects for review
echo "$PROJECTS" | python3 -c "
import json
import sys

data = json.load(sys.stdin)
projects = data.get('result', [])

known_active = '''$KNOWN_ACTIVE'''.strip().split()

dormant = []
active = []

for p in projects:
    project_id = p.get('projectId', 'unknown')
    display_name = p.get('displayName', project_id)

    if project_id in known_active or any(k in project_id for k in known_active):
        active.append((project_id, display_name))
    else:
        dormant.append((project_id, display_name))

print('### Confirmed Active Projects')
print('')
for pid, name in active:
    print(f'- **{name}** ({pid})')

print('')
print('### Review for Cleanup')
print('')
for pid, name in dormant:
    print(f'- {name} ({pid})')
"

echo ""
echo "## Recommendations" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"
echo "1. **Keep**: Projects with active hosting or recent deploys" >> "$OUTPUT_FILE"
echo "2. **Archive**: Export data from dormant projects before deletion" >> "$OUTPUT_FILE"
echo "3. **Delete**: Projects with no activity in 6+ months and no data" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"
echo "## Quick Cleanup Commands" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"
echo "\`\`\`bash" >> "$OUTPUT_FILE"
echo "# Delete a project (IRREVERSIBLE)" >> "$OUTPUT_FILE"
echo "firebase projects:delete PROJECT_ID" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"
echo "# Export Firestore data first" >> "$OUTPUT_FILE"
echo "gcloud firestore export gs://backup-bucket/PROJECT_ID" >> "$OUTPUT_FILE"
echo "\`\`\`" >> "$OUTPUT_FILE"

echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Audit complete! Report saved to:${NC}"
echo -e "${CYAN}  $OUTPUT_FILE${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"

# Also print summary to console
echo ""
echo -e "${BOLD}Quick Summary:${NC}"
firebase projects:list | head -25
echo ""
echo -e "${YELLOW}Run 'cat $OUTPUT_FILE' to see full report${NC}"
