#!/bin/bash
# Teams Webhook Notification Script for Sprint Planning
# Usage: ./send-teams-notification.sh <project> <sprint_number>

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

# Extract metrics from output files
USER_STORIES_FILE="${OUTPUT_DIR}/user_stories.md"
TASK_BREAKDOWN_FILE="${OUTPUT_DIR}/task_breakdown.md"
TEAM_ASSIGNMENTS_FILE="${OUTPUT_DIR}/team_assignments.md"

# Count stories
STORY_COUNT=$(grep -c "^## [A-Z]*-[0-9]*-[0-9]*:" "$USER_STORIES_FILE" 2>/dev/null || echo "0")

# Sum story points
TOTAL_SP=$(grep -oE "\*\*Story Points:\*\* [0-9]+ SP" "$USER_STORIES_FILE" 2>/dev/null | grep -oE "[0-9]+" | awk '{sum+=$1} END {print sum}' || echo "0")

# Count tasks
TASK_COUNT=$(grep -cE "^\| [A-Z]*-[0-9]*-[0-9]*-T[0-9]+" "$TASK_BREAKDOWN_FILE" 2>/dev/null || echo "0")

# Sum hours
TOTAL_HOURS=$(grep -oE "\*\*Estimated Hours:\*\* [0-9]+" "$USER_STORIES_FILE" 2>/dev/null | grep -oE "[0-9]+" | awk '{sum+=$1} END {print sum}' || echo "0")

# Count high priority
HIGH_PRIORITY=$(grep -c "\*\*Priority:\*\* High" "$USER_STORIES_FILE" 2>/dev/null || echo "0")

# Count blockers
BLOCKERS=$(grep -c "Blocked By:\*\* [^N]" "$USER_STORIES_FILE" 2>/dev/null || echo "0")
WARNINGS=$(grep -c "⚠️" "$USER_STORIES_FILE" "$TEAM_ASSIGNMENTS_FILE" 2>/dev/null || echo "0")

# Get capacity and utilization from team assignments
CAPACITY=$(grep -oE "Team Capacity:\*\* [0-9]+ SP" "$USER_STORIES_FILE" 2>/dev/null | grep -oE "[0-9]+" || echo "0")
UTILIZATION=$(grep -oE "Utilization:\*\* [0-9]+%" "$USER_STORIES_FILE" 2>/dev/null | grep -oE "[0-9]+" || echo "0")

# Build top stories list
TOP_STORIES=$(grep -E "^## [A-Z]*-[0-9]*-[0-9]*:" "$USER_STORIES_FILE" 2>/dev/null | head -5 | sed 's/## /- /' || echo "None")

# Build payload
PAYLOAD=$(cat <<EOF
{
  "@type": "MessageCard",
  "@context": "http://schema.org/extensions",
  "themeColor": "0076D7",
  "summary": "Sprint ${SPRINT} Planning - ${PROJECT^}",
  "sections": [
    {
      "activityTitle": "🚀 Sprint ${SPRINT} - ${PROJECT^} Planning Complete",
      "activitySubtitle": "Generated on $(date '+%Y-%m-%d %H:%M')",
      "facts": [
        {"name": "📋 Stories", "value": "${STORY_COUNT}"},
        {"name": "📊 Story Points", "value": "${TOTAL_SP} SP"},
        {"name": "✅ Tasks", "value": "${TASK_COUNT}"},
        {"name": "⏱️ Total Hours", "value": "${TOTAL_HOURS}h"},
        {"name": "🔥 High Priority", "value": "${HIGH_PRIORITY}"},
        {"name": "🚧 Blockers", "value": "${BLOCKERS}"},
        {"name": "📈 Utilization", "value": "${UTILIZATION}%"}
      ],
      "markdown": true
    },
    {
      "activityTitle": "📝 Top Stories",
      "text": "${TOP_STORIES}"
    }
  ],
  "potentialAction": [
    {
      "@type": "OpenUri",
      "name": "View Full Plan",
      "targets": [{"os": "default", "uri": "file://${PWD}/${OUTPUT_DIR}"}]
    }
  ]
}
EOF
)

# Send to Teams
echo "Sending notification for ${PROJECT} Sprint ${SPRINT}..."
RESPONSE=$(curl -s -w "%{http_code}" -H "Content-Type: application/json" -d "$PAYLOAD" "$WEBHOOK_URL")
HTTP_CODE="${RESPONSE: -3}"

if [ "$HTTP_CODE" == "200" ] || [ "$HTTP_CODE" == "202" ]; then
    echo "✅ Notification sent successfully to ${PROJECT} channel"
else
    echo "❌ Failed to send notification. HTTP code: $HTTP_CODE"
    echo "Response: ${RESPONSE:0:-3}"
    exit 1
fi
