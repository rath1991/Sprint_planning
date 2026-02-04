#!/bin/bash
# Teams Workflow Notification Script for Sprint Planning
# Usage: ./send-teams-notification.sh <project> <sprint_number>
# Sends full sprint content via Power Automate Workflow (Adaptive Cards)

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
    echo "   Please update .sprint-planning/teams-webhook-alerts-config.json with your workflow URL"
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
# EXTRACT USER STORIES
# ============================================
echo "📋 Extracting user stories..."

STORIES_TEXT=""
while IFS= read -r story_line; do
    STORY_ID=$(echo "$story_line" | grep -oE "^[A-Z]+-[0-9]+-[0-9]+")
    if [ -n "$STORY_ID" ]; then
        SP=$(grep -A5 "## ${STORY_ID}:" "$USER_STORIES_FILE" | grep -oE "Story Points:\*\* [0-9]+" | grep -oE "[0-9]+" || echo "?")
        PRIORITY=$(grep -A5 "## ${STORY_ID}:" "$USER_STORIES_FILE" | grep -oE "Priority:\*\* [A-Za-z]+" | sed 's/Priority:\*\* //' || echo "?")
        TITLE=$(echo "$story_line" | sed "s/^${STORY_ID}: //")

        PRIORITY_ICON="⚪"
        [[ "$PRIORITY" == "High" ]] && PRIORITY_ICON="🔴"
        [[ "$PRIORITY" == "Medium" ]] && PRIORITY_ICON="🟡"
        [[ "$PRIORITY" == "Low" ]] && PRIORITY_ICON="🟢"

        STORIES_TEXT="${STORIES_TEXT}${PRIORITY_ICON} **${STORY_ID}** (${SP} SP) - ${TITLE}\n\n"
    fi
done <<< "$(grep -oE "^## [A-Z]+-[0-9]+-[0-9]+:.*" "$USER_STORIES_FILE" | sed 's/## //')"

# ============================================
# EXTRACT TASKS
# ============================================
echo "✅ Extracting tasks..."

TASKS_TEXT=""
CURRENT_STORY=""
while IFS= read -r line; do
    if [[ "$line" =~ ^##[[:space:]]([A-Z]+-[0-9]+-[0-9]+): ]]; then
        CURRENT_STORY="${BASH_REMATCH[1]}"
        TASKS_TEXT="${TASKS_TEXT}\n**${CURRENT_STORY}**\n"
    fi
    if [[ "$line" =~ ^\|[[:space:]]([A-Z]+-[0-9]+-[0-9]+-T[0-9]+) ]]; then
        TASK_ID="${BASH_REMATCH[1]}"
        TASK_DESC=$(echo "$line" | awk -F'|' '{print $3}' | xargs)
        TASK_HOURS=$(echo "$line" | awk -F'|' '{print $4}' | xargs)
        TASK_ASSIGNEE=$(echo "$line" | awk -F'|' '{print $5}' | xargs)
        TASKS_TEXT="${TASKS_TEXT}  • ${TASK_ID}: ${TASK_DESC} (${TASK_HOURS}h) → ${TASK_ASSIGNEE}\n"
    fi
done < "$TASK_BREAKDOWN_FILE"

# ============================================
# EXTRACT TEAM ASSIGNMENTS
# ============================================
echo "👥 Extracting team assignments..."

TEAM_TEXT=""
if [ -f "$TEAM_ASSIGNMENTS_FILE" ]; then
    while IFS= read -r line; do
        if [[ "$line" =~ ^\|[[:space:]]@([a-zA-Z._-]+) ]]; then
            MEMBER="@${BASH_REMATCH[1]}"
            ASSIGNED=$(echo "$line" | awk -F'|' '{print $4}' | xargs)
            CAPACITY=$(echo "$line" | awk -F'|' '{print $3}' | xargs)
            UTIL=$(echo "$line" | awk -F'|' '{print $6}' | xargs)
            TEAM_TEXT="${TEAM_TEXT}• **${MEMBER}**: ${ASSIGNED} / ${CAPACITY} (${UTIL})\n"
        fi
    done < "$TEAM_ASSIGNMENTS_FILE"
fi

# ============================================
# BUILD ADAPTIVE CARD PAYLOAD
# ============================================
echo "📦 Building Adaptive Card payload..."

PROJECT_UPPER=$(echo "${PROJECT}" | awk '{print toupper(substr($0,1,1)) tolower(substr($0,2))}')

# Escape for JSON
escape_json() {
    printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'  | sed 's/^"//;s/"$//'
}

STORIES_ESCAPED=$(escape_json "$STORIES_TEXT")
TASKS_ESCAPED=$(escape_json "$TASKS_TEXT")
TEAM_ESCAPED=$(escape_json "$TEAM_TEXT")

# Adaptive Card payload for Power Automate Workflow
PAYLOAD=$(cat <<EOF
{
  "type": "message",
  "attachments": [
    {
      "contentType": "application/vnd.microsoft.card.adaptive",
      "contentUrl": null,
      "content": {
        "\$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
        "type": "AdaptiveCard",
        "version": "1.4",
        "body": [
          {
            "type": "TextBlock",
            "size": "Large",
            "weight": "Bolder",
            "text": "🚀 Sprint ${SPRINT} - ${PROJECT_UPPER}",
            "wrap": true,
            "style": "heading"
          },
          {
            "type": "TextBlock",
            "text": "Approved by ${APPROVED_BY} on ${APPROVED_AT}",
            "isSubtle": true,
            "wrap": true
          },
          {
            "type": "ColumnSet",
            "columns": [
              {
                "type": "Column",
                "width": "stretch",
                "items": [
                  {"type": "TextBlock", "text": "📋 Stories", "weight": "Bolder"},
                  {"type": "TextBlock", "text": "${STORY_COUNT}", "size": "ExtraLarge", "color": "Accent"}
                ]
              },
              {
                "type": "Column",
                "width": "stretch",
                "items": [
                  {"type": "TextBlock", "text": "📊 Story Points", "weight": "Bolder"},
                  {"type": "TextBlock", "text": "${TOTAL_SP} SP", "size": "ExtraLarge", "color": "Accent"}
                ]
              },
              {
                "type": "Column",
                "width": "stretch",
                "items": [
                  {"type": "TextBlock", "text": "✅ Tasks", "weight": "Bolder"},
                  {"type": "TextBlock", "text": "${TASK_COUNT}", "size": "ExtraLarge", "color": "Accent"}
                ]
              },
              {
                "type": "Column",
                "width": "stretch",
                "items": [
                  {"type": "TextBlock", "text": "⏱️ Hours", "weight": "Bolder"},
                  {"type": "TextBlock", "text": "${TOTAL_HOURS}h", "size": "ExtraLarge", "color": "Accent"}
                ]
              }
            ]
          },
          {
            "type": "TextBlock",
            "text": "🔥 High Priority: ${HIGH_PRIORITY} | 🚧 Blockers: ${BLOCKERS}",
            "wrap": true,
            "spacing": "Medium"
          },
          {
            "type": "Container",
            "style": "emphasis",
            "items": [
              {
                "type": "TextBlock",
                "text": "📋 User Stories",
                "weight": "Bolder",
                "size": "Medium"
              },
              {
                "type": "TextBlock",
                "text": "${STORIES_ESCAPED}",
                "wrap": true
              }
            ]
          },
          {
            "type": "Container",
            "style": "emphasis",
            "items": [
              {
                "type": "TextBlock",
                "text": "✅ Task Breakdown",
                "weight": "Bolder",
                "size": "Medium"
              },
              {
                "type": "TextBlock",
                "text": "${TASKS_ESCAPED}",
                "wrap": true
              }
            ]
          },
          {
            "type": "Container",
            "style": "emphasis",
            "items": [
              {
                "type": "TextBlock",
                "text": "👥 Team Assignments",
                "weight": "Bolder",
                "size": "Medium"
              },
              {
                "type": "TextBlock",
                "text": "${TEAM_ESCAPED}",
                "wrap": true
              }
            ]
          }
        ]
      }
    }
  ]
}
EOF
)

# ============================================
# SEND TO TEAMS WORKFLOW
# ============================================
echo "📤 Sending to Teams Workflow..."

RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" \
    "$WEBHOOK_URL")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" == "200" ] || [ "$HTTP_CODE" == "202" ] || [ "$HTTP_CODE" == "204" ]; then
    echo ""
    echo "✅ Notification sent successfully to ${PROJECT} channel!"
    echo ""
    echo "Summary sent:"
    echo "  • ${STORY_COUNT} stories (${TOTAL_SP} SP)"
    echo "  • ${TASK_COUNT} tasks (${TOTAL_HOURS}h)"
    echo "  • ${HIGH_PRIORITY} high priority"
else
    echo "❌ Failed to send notification. HTTP code: $HTTP_CODE"
    echo "Response: $BODY"
    exit 1
fi
