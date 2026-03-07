#!/usr/bin/env bash
#
# E2E test runner for AI plugin.
#
# Phases:
#   1. Cleanup  - kill leftover processes from previous runs
#   2. Setup    - start mock server, symlink mock CLI, set env vars
#   3. Test     - run plenary busted tests
#   4. Cleanup  - tear down mock server, remove temp files
#
# Usage:
#   make e2e
#   # or directly:
#   bash e2e/run.sh

set -euo pipefail

E2E_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$E2E_DIR")"
MOCK_PORT=9871
MOCK_PID=""
MOCK_BIN_DIR=""

cleanup() {
    if [ -n "$MOCK_PID" ] && kill -0 "$MOCK_PID" 2>/dev/null; then
        kill "$MOCK_PID" 2>/dev/null || true
        wait "$MOCK_PID" 2>/dev/null || true
        echo "[e2e] Mock server stopped"
    fi
    if [ -n "$MOCK_BIN_DIR" ] && [ -d "$MOCK_BIN_DIR" ]; then
        rm -rf "$MOCK_BIN_DIR"
        echo "[e2e] Mock CLI removed"
    fi
}
trap cleanup EXIT

# --- 1. Cleanup leftovers from previous runs ---

EXISTING_PID=$(lsof -ti :"$MOCK_PORT" 2>/dev/null || true)
if [ -n "$EXISTING_PID" ]; then
    echo "[e2e] Killing leftover process on port $MOCK_PORT (pid=$EXISTING_PID)"
    kill "$EXISTING_PID" 2>/dev/null || true
    sleep 0.2
fi

# --- 2. Setup ---

python3 "$E2E_DIR/mock_server.py" "$MOCK_PORT" &
MOCK_PID=$!

for i in $(seq 1 20); do
    if curl -s "http://127.0.0.1:$MOCK_PORT" >/dev/null 2>&1; then
        break
    fi
    if ! kill -0 "$MOCK_PID" 2>/dev/null; then
        echo "ERROR: Mock server died during startup"
        exit 1
    fi
    sleep 0.1
done
echo "[e2e] Mock server started (pid=$MOCK_PID, port=$MOCK_PORT)"

MOCK_BIN_DIR=$(mktemp -d)
ln -s "$E2E_DIR/mock_opencode.sh" "$MOCK_BIN_DIR/7619b34b-opencode-d0a72d8a"
export PATH="$MOCK_BIN_DIR:$PATH"
echo "[e2e] Mock CLI installed at $MOCK_BIN_DIR"

export AI_ALT_URL="http://127.0.0.1:$MOCK_PORT/v1/chat/completions"
export AI_ALT_API_KEY="test-key"
export AI_ALT_MODEL="test-model"
unset AI_WORK 2>/dev/null || true

# --- 3. Test ---

echo "[e2e] Running tests..."
cd "$PROJECT_DIR"
nvim --headless -u ./e2e/specs/init.lua \
    -c "PlenaryBustedDirectory e2e/specs/ { minimal_init = 'e2e/specs/init.lua' }"
echo "[e2e] Done."

# --- 4. Cleanup runs via trap EXIT ---
