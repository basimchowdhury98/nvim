#!/usr/bin/env python3
"""
Mock SSE server for e2e testing AI providers.

Serves canned SSE responses from fixture files.

Fixture lookup:
  POST body is parsed as JSON. The last user message content is hashed
  to produce a fixture key. The server looks for:
    fixtures/alt/<key>.txt

  If no fixture exists, returns a JSON error:
    {"error": {"message": "NO_FIXTURE: <key> - capture a real response and save to fixtures/alt/<key>.txt"}}

Fixture file format:
  Raw SSE stream exactly as the real API would send it, e.g.:
    data: {"choices":[{"delta":{"content":"Hello"}}]}
    data: {"choices":[{"delta":{"content":" world"}}]}
    data: [DONE]

Usage:
  python3 e2e/mock_server.py [port]  (default: 9871)
"""

import hashlib
import json
import os
import sys
import time
from http.server import HTTPServer, BaseHTTPRequestHandler

FIXTURE_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures", "alt")


def fixture_key(body_str):
    """Derive a fixture key from the request body.

    Uses the content of the last user message as the key source.
    This means the same user question always maps to the same fixture,
    regardless of system prompt or prior conversation.
    """
    try:
        body = json.loads(body_str)
        messages = body.get("messages", [])
        # Find the last user message
        for msg in reversed(messages):
            if msg.get("role") == "user":
                content = msg.get("content", "")
                # Use first 80 chars + hash for readability + uniqueness
                slug = content[:80].strip()
                # Sanitize for filename
                slug = "".join(c if c.isalnum() or c in " -_" else "_" for c in slug)
                slug = slug.strip().replace(" ", "_")[:60]
                h = hashlib.sha256(content.encode()).hexdigest()[:12]
                return f"{slug}_{h}"
        return "no_user_message"
    except (json.JSONDecodeError, KeyError):
        return "invalid_request"


class MockSSEHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        content_length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_length).decode("utf-8")

        key = fixture_key(body)
        fixture_path = os.path.join(FIXTURE_DIR, f"{key}.txt")

        if not os.path.exists(fixture_path):
            # Return a clear error indicating the fixture needs to be captured
            error_msg = f"NO_FIXTURE: {key} - capture a real response and save to fixtures/alt/{key}.txt"
            error_json = json.dumps({"error": {"message": error_msg}})
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(error_json.encode())
            self.wfile.flush()
            print(f"[mock] No fixture for key: {key}")
            return

        print(f"[mock] Serving fixture: {key}")
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()

        with open(fixture_path, "r") as f:
            for line in f:
                self.wfile.write(line.encode())
                self.wfile.flush()
                # Small delay between chunks to simulate streaming
                time.sleep(0.005)

    def log_message(self, format, *args):
        # Suppress default request logging, we do our own
        pass


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 9871
    server = HTTPServer(("127.0.0.1", port), MockSSEHandler)
    print(f"[mock] Alt SSE server listening on http://127.0.0.1:{port}")
    print(f"[mock] Fixture dir: {FIXTURE_DIR}")
    sys.stdout.flush()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    server.server_close()


if __name__ == "__main__":
    main()
