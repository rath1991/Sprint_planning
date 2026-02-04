#!/bin/bash
# Teams Webhook Notification Script for Sprint Planning
# Usage: ./send-teams-notification.sh <project> <sprint_number>
# Sends full sprint content (stories, tasks, assignments) to Teams

set -e

PROJECT=$1
SPRINT=$2
CONFIG_FILE=".sprint-planning/teams-webhook-alerts-config.json"
OUTPUT_DIR="sprint/sprint-${SPRINT}/${PROJECT}/outputs"

if [ -z "$PROJECT" ] || [ -z "$SPRINT" ]; then
    echo "Usage: $0 <project> <sprint_number>"
    echo "Example: $0 rockapedia 23"
    exit 1
fi

# Check if jq is available
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required. Install with: brew install jq"
    exit 1
fi

# Check if config exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Config file not found: $CONFIG_FILE"
    exit 1
fi

# Check if outputs exist
if [ ! -d "$OUTPUT_DIR" ]; then
    echo "Error: Output directory not found: $OUTPUT_DIR"
    exit 1
fi

# Check for approval (Phase 6 must be complete)
APPROVAL_FILE="${OUTPUT_DIR}/approval.md"
if [ ! -f "$APPROVAL_FILE" ]; then
    echo "❌ Error: Sprint plan not approved yet."
    echo "   Missing: $APPROVAL_FILE"
    echo "   Please complete Phase 6 (Human Review & Approval) before sending notifications."
    exit 1
fi

# Verify approval status
APPROVAL_STATUS=$(grep -oE "Status: [A-Z]+" "$APPROVAL_FILE" 2>/dev/null | cut -d' ' -f2 || echo "UNKNOWN")
if [ "$APPROVAL_STATUS" != "APPROVED" ]; then
    echo "❌ Error: Sprint plan status is '$APPROVAL_STATUS', not APPROVED."
    echo "   Please approve the sprint plan before sending notifications."
    exit 1
fi

APPROVED_BY=$(grep 'Approved by:' "$APPROVAL_FILE" 2>/dev/null | sed 's/Approved by: //' || echo "Unknown")
APPROVED_AT=$(grep 'Approved at:' "$APPROVAL_FILE" 2>/dev/null | sed 's/Approved at: //' || echo "Unknown")
echo "✅ Approval verified: $APPROVED_BY at $APPROVED_AT"

# Get webhook URL for project
WEBHOOK_URL=$(jq -r ".webhooks.${PROJECT}.url" "$CONFIG_FILE")
ENABLED=$(jq -r ".webhooks.${PROJECT}.enabled" "$CONFIG_FILE")

if [ "$ENABLED" != "true" ]; then
    echo "Webhook disabled for project: $PROJECT"
    exit 0
fi

if [ "$WEBHOOK_URL" == "null" ] || [[ "$WEBHOOK_URL" == *"YOUR_"* ]]; then
    echo "Error: Webhook URL not configured for project: $PROJECT"
    exit 1
fi

# File paths
USER_STORIES_FILE="${OUTPUT_DIR}/user_stories.md"
TASK_BREAKDOWN_FILE="${OUTPUT_DIR}/task_breakdown.md"
SPRINT_SUMMARY_FILE="${OUTPUT_DIR}/sprint_summary.md"
TEAM_ASSIGNMENTS_FILE="${OUTPUT_DIR}/team_assignments.md"

# ============================================
# EXTRACT METRICS
# ============================================
echo "📊 Extracting metrics..."

STORY_COUNT=$(grep -c "^## [A-Z]*-[0-9]*-[0-9]*:" "$USER_STORIES_FILE" 2>/dev/null || echo "0")
TOTAL_SP=$(grep -oE "\*\*Story Points:\*\* [0-9]+ SP" "$USER_STORIES_FILE" 2>/dev/null | grep -oE "[0-9]+" | awk '{sum+=$1} END {print sum+0}')
TASK_COUNT=$(grep -cE "^\| [A-Z]*-[0-9]*-[0-9]*-T[0-9]+" "$TASK_BREAKDOWN_FILE" 2>/dev/null || echo "0")
TOTAL_HOURS=$(grep -oE "\*\*Estimated Hours:\*\* [0-9]+" "$USER_STORIES_FILE" 2>/dev/null | grep -oE "[0-9]+" | awk '{sum+=$1} END {print sum+0}')
HIGH_PRIORITY=$(grep -c "\*\*Priority:\*\* High" "$USER_STORIES_FILE" 2>/dev/null || echo "0")
BLOCKERS=$(grep -c "Blocked By:\*\* [^N]" "$USER_STORIES_FILE" 2>/dev/null || echo "0")

# ============================================
# EXTRACT USER STORIES CONTENT
# ============================================
echo "📋 Extracting user stories..."

STORIES_CONTENT=""
while IFS= read -r line; do
    if [[ "$line" =~ ^##[[:space:]]([A-Z]+-[0-9]+-[0-9]+):(.*)$ ]]; then
        STORY_ID="${BASH_REMATCH[1]}"
        STORY_TITLE="${BASH_REMATCH[2]}"
        STORIES_CONTENT="${STORIES_CONTENT}**${STORY_ID}:** ${STORY_TITLE}  \\n"
    fi
done < "$USER_STORIES_FILE"

# Add story details (SP, Priority)
STORIES_LIST=""
while IFS= read -r story_line; do
    STORY_ID=$(echo "$story_line" | grep -oE "^[A-Z]+-[0-9]+-[0-9]+")
    if [ -n "$STORY_ID" ]; then
        # Extract details for this story
        SP=$(grep -A5 "## ${STORY_ID}:" "$USER_STORIES_FILE" | grep -oE "Story Points:\*\* [0-9]+" | grep -oE "[0-9]+" || echo "?")
        PRIORITY=$(grep -A5 "## ${STORY_ID}:" "$USER_STORIES_FILE" | grep -oE "Priority:\*\* [A-Za-z]+" | sed 's/Priority:\*\* //' || echo "?")
        TITLE=$(echo "$story_line" | sed "s/^${STORY_ID}: //")

        PRIORITY_ICON="⚪"
        [[ "$PRIORITY" == "High" ]] && PRIORITY_ICON="🔴"
        [[ "$PRIORITY" == "Medium" ]] && PRIORITY_ICON="🟡"
        [[ "$PRIORITY" == "Low" ]] && PRIORITY_ICON="🟢"

        STORIES_LIST="${STORIES_LIST}${PRIORITY_ICON} **${STORY_ID}** (${SP} SP) - ${TITLE}  \\n\\n"
    fi
done <<< "$(grep -oE "^## [A-Z]+-[0-9]+-[0-9]+:.*" "$USER_STORIES_FILE" | sed 's/## //')"

# ============================================
# EXTRACT TASKS CONTENT
# ============================================
echo "✅ Extracting tasks..."

TASKS_CONTENT=""
CURRENT_STORY=""
while IFS= read -r line; do
    # Check for story header
    if [[ "$line" =~ ^##[[:space:]]([A-Z]+-[0-9]+-[0-9]+): ]]; then
        CURRENT_STORY="${BASH_REMATCH[1]}"
        TASKS_CONTENT="${TASKS_CONTENT}\\n**${CURRENT_STORY}**\\n"
    fi
    # Check for task row
    if [[ "$line" =~ ^\|[[:space:]]([A-Z]+-[0-9]+-[0-9]+-T[0-9]+) ]]; then
        TASK_ID="${BASH_REMATCH[1]}"
        # Extract task details from the row
        TASK_DESC=$(echo "$line" | awk -F'|' '{print $3}' | xargs)
        TASK_HOURS=$(echo "$line" | awk -F'|' '{print $4}' | xargs)
        TASK_ASSIGNEE=$(echo "$line" | awk -F'|' '{print $5}' | xargs)
        TASKS_CONTENT="${TASKS_CONTENT}  • ${TASK_ID}: ${TASK_DESC} (${TASK_HOURS}h) → ${TASK_ASSIGNEE}\\n"
    fi
done < "$TASK_BREAKDOWN_FILE"

# ============================================
# EXTRACT TEAM ASSIGNMENTS
# ============================================
echo "👥 Extracting team assignments..."

TEAM_CONTENT=""
if [ -f "$TEAM_ASSIGNMENTS_FILE" ]; then
    # Extract summary table rows
    while IFS= read -r line; do
        if [[ "$line" =~ ^\|[[:space:]]@([a-zA-Z._-]+) ]]; then
            MEMBER="@${BASH_REMATCH[1]}"
            ASSIGNED=$(echo "$line" | awk -F'|' '{print $4}' | xargs)
            CAPACITY=$(echo "$line" | awk -F'|' '{print $3}' | xargs)
            HOURS=$(echo "$line" | awk -F'|' '{print $5}' | xargs)
            UTIL=$(echo "$line" | awk -F'|' '{print $6}' | xargs)
            TEAM_CONTENT="${TEAM_CONTENT}• **${MEMBER}**: ${ASSIGNED} / ${CAPACITY} (${UTIL})\\n"
        fi
    done < "$TEAM_ASSIGNMENTS_FILE"
fi

# ============================================
# EXTRACT SPRINT SUMMARY (if exists)
# ============================================
SUMMARY_CONTENT=""
if [ -f "$SPRINT_SUMMARY_FILE" ]; then
    echo "📈 Extracting sprint summary..."
    SUMMARY_CONTENT=$(cat "$SPRINT_SUMMARY_FILE" | head -50 | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')
fi

# ============================================
# BUILD PAYLOAD
# ============================================
echo "📦 Building notification payload..."

# Escape special characters for JSON
escape_json() {
    echo "$1" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed "s/'/\\'/g"
}

STORIES_LIST_ESCAPED=$(escape_json "$STORIES_LIST")
TASKS_CONTENT_ESCAPED=$(escape_json "$TASKS_CONTENT")
TEAM_CONTENT_ESCAPED=$(escape_json "$TEAM_CONTENT")

PROJECT_UPPER=$(echo "${PROJECT}" | awk '{print toupper(substr($0,1,1)) tolower(substr($0,2))}')

PAYLOAD=$(cat <<EOF
{
  "@type": "MessageCard",
  "@context": "http://schema.org/extensions",
  "themeColor": "0076D7",
  "summary": "Sprint ${SPRINT} Planning - ${PROJECT_UPPER}",
  "sections": [
    {
      "activityTitle": "🚀 Sprint ${SPRINT} - ${PROJECT_UPPER}",
      "activitySubtitle": "Approved by ${APPROVED_BY} on ${APPROVED_AT}",
      "facts": [
        {"name": "📋 Stories", "value": "${STORY_COUNT}"},
        {"name": "📊 Story Points", "value": "${TOTAL_SP} SP"},
        {"name": "✅ Tasks", "value": "${TASK_COUNT}"},
        {"name": "⏱️ Total Hours", "value": "${TOTAL_HOURS}h"},
        {"name": "🔥 High Priority", "value": "${HIGH_PRIORITY}"},
        {"name": "🚧 Blockers", "value": "${BLOCKERS}"}
      ],
      "markdown": true
    },
    {
      "activityTitle": "📋 User Stories",
      "text": "${STORIES_LIST_ESCAPED}"
    },
    {
      "activityTitle": "✅ Task Breakdown",
      "text": "${TASKS_CONTENT_ESCAPED}"
    },
    {
      "activityTitle": "👥 Team Assignments",
      "text": "${TEAM_CONTENT_ESCAPED}"
    }
  ]
}
EOF
)

# ============================================
# SEND TO TEAMS
# ============================================
echo "📤 Sending notification to Teams..."

RESPONSE=$(curl -s -w "%{http_code}" -H "Content-Type: application/json" -d "$PAYLOAD" "$WEBHOOK_URL")
HTTP_CODE="${RESPONSE: -3}"

if [ "$HTTP_CODE" == "200" ] || [ "$HTTP_CODE" == "202" ]; then
    echo ""
    echo "✅ Notification sent successfully to ${PROJECT} channel!"
    echo ""
    echo "Summary sent:"
    echo "  • ${STORY_COUNT} stories (${TOTAL_SP} SP)"
    echo "  • ${TASK_COUNT} tasks (${TOTAL_HOURS}h)"
    echo "  • ${HIGH_PRIORITY} high priority"
else
    echo "❌ Failed to send notification. HTTP code: $HTTP_CODE"
    echo "Response: ${RESPONSE:0:-3}"
    exit 1
fi
