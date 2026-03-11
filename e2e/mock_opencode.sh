#!/usr/bin/env bash
#
# Mock OpenCode CLI for e2e testing.
#
# Intercepts "opencode serve --port <port>" and starts the Python mock server.
# All other subcommands are ignored.
#
# Usage (via symlink):
#   opencode serve --port 42070

REAL_PATH="$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")"
SCRIPT_DIR="$(cd "$(dirname "$REAL_PATH")" && pwd)"

if [ "$1" = "serve" ]; then
    # Extract --port value
    PORT=""
    shift
    while [ $# -gt 0 ]; do
        case "$1" in
            --port) PORT="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    if [ -z "$PORT" ]; then
        echo "[mock-opencode] serve called without --port" >&2
        exit 1
    fi

    exec python3 "$SCRIPT_DIR/mock_server.py" --port "$PORT"
else
    echo "[mock-opencode] ignoring: opencode $*" >&2
fi
