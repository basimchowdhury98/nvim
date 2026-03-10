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
MOCK_BIN_DIR=""

cleanup() {
    if [ -n "$MOCK_BIN_DIR" ] && [ -d "$MOCK_BIN_DIR" ]; then
        rm -rf "$MOCK_BIN_DIR"
        echo "[e2e] Mock CLI removed"
    fi
}
trap cleanup EXIT

# --- 1. Cleanup (no leftovers to clean for CLI-only mock) ---

# --- 2. Setup ---

MOCK_BIN_DIR=$(mktemp -d)
ln -s "$E2E_DIR/mock_opencode.sh" "$MOCK_BIN_DIR/opencode"
export PATH="$MOCK_BIN_DIR:$PATH"
echo "[e2e] Mock CLI installed at $MOCK_BIN_DIR"

unset AI_WORK 2>/dev/null || true

# --- 3. Test ---

echo "[e2e] Running tests..."
cd "$PROJECT_DIR"
nvim --headless -u ./e2e/specs/init.lua \
    -c "PlenaryBustedDirectory e2e/specs/ { minimal_init = 'e2e/specs/init.lua' }"
echo "[e2e] Done."

# --- 4. Cleanup runs via trap EXIT ---
