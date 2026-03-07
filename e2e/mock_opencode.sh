#!/usr/bin/env bash
#
# Mock OpenCode CLI for e2e testing.
#
# Reads stdin (the flattened prompt), hashes the last user message
# to look up a fixture file, and prints it to stdout line by line.
#
# Fixture lookup:
#   The last <|user|> block content is hashed to produce a key.
#   Looks for: e2e/fixtures/opencode/<key>.txt
#
#   If no fixture exists, prints a JSON error event:
#     {"type":"error","part":{"message":"NO_FIXTURE: <key>"}}
#
# Fixture file format:
#   Raw NDJSON exactly as the real opencode CLI would print, e.g.:
#     {"type":"text","part":{"text":"Hello"}}
#     {"type":"text","part":{"text":" world"}}
#     {"type":"step_finish","part":{"reason":"stop","tokens":{"input":10,"output":5},"cost":0.001}}
#
# Usage:
#   echo "prompt" | e2e/mock_opencode.sh run --format json --title nvim-ai

# Resolve symlinks to find the real script location
REAL_PATH="$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")"
SCRIPT_DIR="$(cd "$(dirname "$REAL_PATH")" && pwd)"
FIXTURE_DIR="$SCRIPT_DIR/fixtures/opencode"

# Read all of stdin
INPUT=$(cat)

# Extract the last <|user|> block content for fixture key
# Get everything after the last <|user|> and before the last <|assistant|>
LAST_USER=$(echo "$INPUT" | awk '
    /<\|user\|>/ { capture=1; content=""; next }
    /<\|assistant\|>/ { if(capture) { capture=0; last=content } }
    capture { content = content (content ? "\n" : "") $0 }
    END { print last }
')

if [ -z "$LAST_USER" ]; then
    LAST_USER="no_user_message"
fi

# Trim trailing whitespace/newlines
LAST_USER=$(printf '%s' "$LAST_USER" | sed 's/[[:space:]]*$//')

# Create slug + hash (matching Python server's approach)
SLUG=$(printf '%s' "$LAST_USER" | head -c 80 | tr -cs 'a-zA-Z0-9 _-' '_' | tr ' ' '_' | head -c 60 | sed 's/_$//')
HASH=$(printf '%s' "$LAST_USER" | sha256sum | head -c 12)
KEY="${SLUG}_${HASH}"

FIXTURE_FILE="$FIXTURE_DIR/$KEY.txt"

if [ ! -f "$FIXTURE_FILE" ]; then
    echo "{\"type\":\"error\",\"part\":{\"message\":\"NO_FIXTURE: $KEY - capture a real response and save to e2e/fixtures/opencode/$KEY.txt\"}}"
    exit 0
fi

# Stream the fixture line by line with small delays
while IFS= read -r line; do
    echo "$line"
    sleep 0.005
done < "$FIXTURE_FILE"
