#!/usr/bin/env python3
"""
Mock OpenCode HTTP server for e2e testing.

Implements the minimal subset of the OpenCode server API:
  GET  /global/health     -> {"healthy": true, "version": "mock"}
  POST /session           -> {"id": "<uuid>"}
  POST /session/:id/prompt_async -> 204 (queues SSE events from fixture)
  GET  /event             -> SSE stream (text/event-stream)
  POST /session/:id/abort -> true

Fixture lookup:
  The user message text is hashed to produce a key.
  Looks for: e2e/fixtures/opencode/<key>.txt
  Fixture files contain SSE data lines (one per line):
    data: {"type":"message.part.updated","properties":{...}}

Usage:
  python3 e2e/mock_server.py --port 42070
"""

import hashlib
import json
import os
import queue
import re
import sys
import threading
import uuid
from http.server import HTTPServer, BaseHTTPRequestHandler
from socketserver import ThreadingMixIn

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
FIXTURE_DIR = os.path.join(SCRIPT_DIR, "fixtures", "opencode")

# Global event queues: each SSE client gets its own queue
sse_clients = []
sse_lock = threading.Lock()

# Track sessions
sessions = {}


def broadcast_event(event_line):
    """Send an SSE data line to all connected clients."""
    with sse_lock:
        for q in sse_clients:
            q.put(event_line)


def fixture_key(text):
    """Generate a fixture key from user message text (matches mock_opencode.sh)."""
    text = text.strip()
    slug = re.sub(r"[^a-zA-Z0-9 _-]", "_", text)
    slug = slug.replace(" ", "_")[:60].rstrip("_")
    h = hashlib.sha256(text.encode()).hexdigest()[:12]
    return f"{slug}_{h}"


def load_fixture(key):
    """Load fixture lines from file, or return None."""
    path = os.path.join(FIXTURE_DIR, f"{key}.txt")
    if not os.path.exists(path):
        return None
    with open(path) as f:
        return [line.rstrip("\n") for line in f if line.strip()]


def stream_fixture(session_id, lines):
    """Broadcast fixture lines as SSE events, replacing session IDs."""
    import time
    time.sleep(0.05)  # Give SSE clients time to connect
    for line in lines:
        # Replace any placeholder session ID with the actual one
        replaced = line.replace("SESSION_ID", session_id)
        broadcast_event(replaced)
    # Send session.idle
    idle_event = json.dumps({
        "type": "session.idle",
        "properties": {"sessionID": session_id}
    })
    broadcast_event(f"data: {idle_event}")


class MockHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):  # noqa: A002
        pass

    def do_GET(self):
        if self.path == "/global/health":
            self.send_json({"healthy": True, "version": "mock"})
        elif self.path == "/event":
            self.handle_sse()
        else:
            self.send_error(404)

    def do_POST(self):
        content_length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_length) if content_length else b""

        if self.path == "/session":
            sid = str(uuid.uuid4())
            sessions[sid] = {"id": sid}
            self.send_json({"id": sid})

        elif self.path.endswith("/prompt_async"):
            # Extract session ID from path: /session/<id>/prompt_async
            parts = self.path.split("/")
            sid = parts[2] if len(parts) >= 4 else None
            if not sid or sid not in sessions:
                self.send_error(404, "Session not found")
                return

            # Parse the message body
            try:
                data = json.loads(body)
            except json.JSONDecodeError:
                self.send_error(400, "Invalid JSON")
                return

            # Extract user text from parts
            user_text = ""
            for part in data.get("parts", []):
                if part.get("type") == "text":
                    user_text = part.get("text", "")
                    break

            # Look up fixture
            key = fixture_key(user_text)
            lines = load_fixture(key)
            if lines is None:
                # Send error event
                err = json.dumps({
                    "type": "session.error",
                    "properties": {
                        "sessionID": sid,
                        "error": f"NO_FIXTURE: {key}"
                    }
                })
                broadcast_event(f"data: {err}")
                self.send_response(204)
                self.end_headers()
                return

            # Send 204 and stream fixture in background
            self.send_response(204)
            self.end_headers()

            t = threading.Thread(target=stream_fixture, args=(sid, lines), daemon=True)
            t.start()

        elif self.path.endswith("/abort"):
            self.send_json(True)

        else:
            self.send_error(404)

    def send_json(self, data):
        body = json.dumps(data).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def handle_sse(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "keep-alive")
        self.end_headers()

        # Send initial connected event
        self.wfile.write(b"data: {\"type\":\"server.connected\"}\n\n")
        self.wfile.flush()

        # Register this client
        client_queue = queue.Queue()
        with sse_lock:
            sse_clients.append(client_queue)

        try:
            while True:
                try:
                    event_line = client_queue.get(timeout=1.0)
                    self.wfile.write(f"{event_line}\n\n".encode())
                    self.wfile.flush()
                except queue.Empty:
                    continue
        except (BrokenPipeError, ConnectionResetError):
            pass
        finally:
            with sse_lock:
                if client_queue in sse_clients:
                    sse_clients.remove(client_queue)


class ThreadingHTTPServer(ThreadingMixIn, HTTPServer):
    daemon_threads = True


def main():
    port = 42070
    for i, arg in enumerate(sys.argv):
        if arg == "--port" and i + 1 < len(sys.argv):
            port = int(sys.argv[i + 1])

    server = ThreadingHTTPServer(("127.0.0.1", port), MockHandler)
    print(f"[mock-server] listening on 127.0.0.1:{port}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    server.server_close()


if __name__ == "__main__":
    main()
