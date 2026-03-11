#!/usr/bin/env bash
#
# E2E test runner for AI plugin.
#
# Phases:
#   1. Setup    - start mock HTTP server, symlink mock CLI onto PATH
#   2. Test     - run plenary busted tests
#   3. Cleanup  - kill mock server, remove temp files
#
# Usage:
#   make e2e
#   # or directly:
#   bash e2e/run.sh

set -euo pipefail

E2E_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$E2E_DIR")"
MOCK_PORT=42070
MOCK_BIN_DIR=""
MOCK_SERVER_PID=""

cleanup() {
    if [ -n "$MOCK_SERVER_PID" ] && kill -0 "$MOCK_SERVER_PID" 2>/dev/null; then
        kill "$MOCK_SERVER_PID" 2>/dev/null || true
        wait "$MOCK_SERVER_PID" 2>/dev/null || true
        echo "[e2e] Mock server stopped"
    fi
    if [ -n "$MOCK_BIN_DIR" ] && [ -d "$MOCK_BIN_DIR" ]; then
        rm -rf "$MOCK_BIN_DIR"
        echo "[e2e] Mock CLI removed"
    fi
}
trap cleanup EXIT

# --- 1. Setup ---

# Start mock server directly (provider will see it as already running)
echo "[e2e] Starting mock server on port $MOCK_PORT..."
python3 "$E2E_DIR/mock_server.py" --port "$MOCK_PORT" > /dev/null 2>&1 &
MOCK_SERVER_PID=$!

# Wait for server to be ready
for i in $(seq 1 20); do
    if curl -s --max-time 2 "http://127.0.0.1:$MOCK_PORT/global/health" >/dev/null 2>&1; then
        echo "[e2e] Mock server ready (attempt $i)"
        break
    fi
    if [ "$i" -eq 20 ]; then
        echo "[e2e] ERROR: Mock server failed to start"
        exit 1
    fi
    sleep 0.25
done

# Symlink mock CLI (not strictly needed since server is pre-started,
# but keeps PATH clean in case provider tries to spawn another)
MOCK_BIN_DIR=$(mktemp -d)
ln -s "$E2E_DIR/mock_opencode.sh" "$MOCK_BIN_DIR/opencode"
export PATH="$MOCK_BIN_DIR:$PATH"
echo "[e2e] Mock CLI installed at $MOCK_BIN_DIR"

unset AI_WORK 2>/dev/null || true
export OPENCODE_E2E_PORT="$MOCK_PORT"

# --- 2. Test ---

echo "[e2e] Running tests..."
cd "$PROJECT_DIR"
nvim --headless -u ./e2e/specs/init.lua \
    -c "PlenaryBustedDirectory e2e/specs/ { minimal_init = 'e2e/specs/init.lua' }"
echo "[e2e] Done."

# --- 3. Cleanup runs via trap EXIT ---
