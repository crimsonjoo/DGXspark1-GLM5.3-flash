#!/usr/bin/env python3
"""Small dependency-free OpenAI API gateway with validation and 503 errors."""
import http.client
import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

LISTEN = int(os.getenv("GATEWAY_PORT", "18080"))
BACKEND_HOST = os.getenv("BACKEND_HOST", "127.0.0.1")
BACKEND_PORT = int(os.getenv("BACKEND_PORT", "18081"))
MODEL = os.getenv("MODEL_NAME", "GLM-5.3-Flash-EXL3-2.05")
MAX_BODY = int(os.getenv("GATEWAY_MAX_BODY_BYTES", str(16 * 1024 * 1024)))
MAX_OUTPUT = int(os.getenv("SAFE_MAX_OUTPUT_TOKENS", "8192"))
BACKEND_TIMEOUT = int(os.getenv("GATEWAY_BACKEND_TIMEOUT", "1800"))

HOP = {"connection", "keep-alive", "proxy-authenticate", "proxy-authorization",
       "te", "trailers", "transfer-encoding", "upgrade", "content-length"}


class Gateway(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "glm53-gateway/1"

    def log_message(self, fmt, *args):
        print(f"{self.client_address[0]} {fmt % args}", flush=True)

    def json_error(self, status, message, code, retry=None):
        payload = json.dumps({"error": {"message": message,
            "type": "backend_unavailable" if status == 503 else "invalid_request_error",
            "code": code, **({"retry_after_seconds": retry} if retry else {})}}).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Connection", "close")
        if retry:
            self.send_header("Retry-After", str(retry))
        self.end_headers(); self.wfile.write(payload); self.close_connection = True

    def _request_body(self):
        try: length = int(self.headers.get("Content-Length", "0"))
        except ValueError: return None, "invalid_content_length"
        if length > MAX_BODY: return None, "request_body_too_large"
        return self.rfile.read(length) if length else b"", None

    def _validate(self, body):
        if self.command != "POST" or not self.path.startswith("/v1/"):
            return None
        try: data = json.loads(body)
        except (ValueError, UnicodeDecodeError): return (400, "Request body must be valid JSON", "invalid_json")
        if "model" in data and data["model"] != MODEL:
            return (400, f"Unknown model {data['model']!r}; use {MODEL}", "model_not_found")
        value = data.get("max_tokens", data.get("max_completion_tokens"))
        if value is not None and (not isinstance(value, int) or isinstance(value, bool) or value < 1):
            return (400, "max_tokens must be a positive integer", "invalid_max_tokens")
        if value is not None and value > MAX_OUTPUT:
            return (400, f"max_tokens={value} exceeds the safe limit {MAX_OUTPUT}", "max_tokens_exceeds_safe_limit")
        if self.path.startswith("/v1/chat/completions") and not isinstance(data.get("messages"), list):
            return (400, "messages must be an array", "invalid_messages")
        return None

    def _proxy(self):
        body, error = self._request_body()
        if error:
            return self.json_error(413 if error.endswith("large") else 400, error.replace("_", " "), error)
        invalid = self._validate(body)
        if invalid:
            return self.json_error(*invalid)
        headers = {k: v for k, v in self.headers.items() if k.lower() not in HOP}
        headers["Host"] = f"{BACKEND_HOST}:{BACKEND_PORT}"
        try:
            conn = http.client.HTTPConnection(BACKEND_HOST, BACKEND_PORT, timeout=BACKEND_TIMEOUT)
            conn.request(self.command, self.path, body=body, headers=headers)
            response = conn.getresponse()
        except (OSError, TimeoutError, http.client.HTTPException):
            return self.json_error(503, "GLM backend is loading or restarting after an engine failure", "model_restarting", 60)
        self.send_response(response.status, response.reason)
        for key, value in response.getheaders():
            if key.lower() not in HOP: self.send_header(key, value)
        self.send_header("Connection", "close"); self.end_headers()
        try:
            while True:
                chunk = response.read(64 * 1024)
                if not chunk: break
                self.wfile.write(chunk); self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError, http.client.HTTPException):
            pass
        finally:
            conn.close(); self.close_connection = True

    do_GET = do_POST = do_DELETE = do_PUT = do_PATCH = _proxy


if __name__ == "__main__":
    listen_host = os.getenv("GATEWAY_HOST", "0.0.0.0")
    print(f"glm53-gateway listening on {listen_host}:{LISTEN}, backend={BACKEND_HOST}:{BACKEND_PORT}", flush=True)
    ThreadingHTTPServer((listen_host, LISTEN), Gateway).serve_forever()
