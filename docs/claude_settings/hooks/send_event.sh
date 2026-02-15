#!/bin/bash
# Observatory hook event sender
# Reads Claude Code hook JSON from stdin, POSTs to Observatory server.
# Usage: echo '{"session_id":"..."}' | send_event.sh <EventType>

set -e

SERVER_URL="${OBSERVATORY_URL:-http://localhost:4005/api/events}"
SOURCE_APP="${OBSERVATORY_APP:-default}"

# Read JSON from stdin
INPUT=$(cat)

# Extract session_id
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"')

# Event type from first arg
HOOK_EVENT_TYPE="${1:-Stop}"

# Build and send payload
jq -n \
  --arg source_app "$SOURCE_APP" \
  --arg session_id "$SESSION_ID" \
  --arg hook_event_type "$HOOK_EVENT_TYPE" \
  --argjson payload "$INPUT" \
  '{
    source_app: $source_app,
    session_id: $session_id,
    hook_event_type: $hook_event_type,
    payload: $payload
  }' | curl -s -X POST \
  -H "Content-Type: application/json" \
  -d @- \
  "$SERVER_URL" > /dev/null 2>&1 || true

exit 0
