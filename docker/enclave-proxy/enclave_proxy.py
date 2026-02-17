#!/usr/bin/env python3
"""
Treza Enclave Proxy - Runs inside the Nitro Enclave alongside the user's application.

Provides:
- HTTP forward proxy on localhost:3128 (tunnels requests through vsock to parent)
- KMS proxy on localhost:8000 (for attestation-gated KMS operations)
- Stdout/stderr streaming to parent via vsock for CloudWatch logging
- Health check reporting for the user application
- PCR value retrieval from parent

All external communication is multiplexed over a single vsock connection to the
parent instance using a length-prefixed JSON protocol.

Protocol frame format:
  [4 bytes: big-endian uint32 payload length][JSON payload]

Message types:
  enclave -> parent: log, http_request, kms_request, pcr_request, health_report
  parent -> enclave: http_response, kms_response, pcr_response, error
"""

import socket
import json
import struct
import sys
import os
import time
import signal
import subprocess
import threading
import traceback
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse

VMADDR_CID_HOST = 3
VSOCK_PORT = 5000
HTTP_PROXY_PORT = 3128
KMS_PROXY_PORT = 8000
HEALTH_CHECK_PORT = 8888

# Global vsock connection shared by all proxy threads
_vsock_lock = threading.Lock()
_vsock_conn = None
_request_id_counter = 0
_pending_responses = {}
_pending_lock = threading.Lock()
_shutdown_event = threading.Event()


def next_request_id():
    global _request_id_counter
    with _vsock_lock:
        _request_id_counter += 1
        return f"req-{_request_id_counter}"


def send_message(sock, message):
    """Send a length-prefixed JSON message over the socket."""
    payload = json.dumps(message).encode("utf-8")
    header = struct.pack("!I", len(payload))
    with _vsock_lock:
        sock.sendall(header + payload)


def recv_message(sock):
    """Receive a length-prefixed JSON message from the socket."""
    header = _recv_exact(sock, 4)
    if not header:
        return None
    length = struct.unpack("!I", header)[0]
    if length > 10 * 1024 * 1024:  # 10 MB safety limit
        raise ValueError(f"Message too large: {length} bytes")
    payload = _recv_exact(sock, length)
    if not payload:
        return None
    return json.loads(payload.decode("utf-8"))


def _recv_exact(sock, n):
    """Read exactly n bytes from socket."""
    data = b""
    while len(data) < n:
        chunk = sock.recv(n - len(data))
        if not chunk:
            return None
        data += chunk
    return data


def send_log(level, message):
    """Send a log message to the parent for CloudWatch."""
    global _vsock_conn
    if _vsock_conn:
        try:
            send_message(_vsock_conn, {
                "type": "log",
                "id": next_request_id(),
                "payload": {
                    "level": level,
                    "message": message,
                    "timestamp": time.time(),
                }
            })
        except Exception:
            pass
    print(f"[ENCLAVE-PROXY] [{level.upper()}] {message}", flush=True)


def send_request_and_wait(msg_type, payload, timeout=30):
    """Send a request to the parent and wait for the response."""
    global _vsock_conn
    req_id = next_request_id()
    event = threading.Event()
    with _pending_lock:
        _pending_responses[req_id] = {"event": event, "response": None}

    send_message(_vsock_conn, {
        "type": msg_type,
        "id": req_id,
        "payload": payload,
    })

    if not event.wait(timeout=timeout):
        with _pending_lock:
            _pending_responses.pop(req_id, None)
        raise TimeoutError(f"Request {req_id} timed out after {timeout}s")

    with _pending_lock:
        result = _pending_responses.pop(req_id)
    return result["response"]


def response_dispatcher():
    """Background thread that reads responses from the parent and dispatches them."""
    global _vsock_conn
    while not _shutdown_event.is_set():
        try:
            msg = recv_message(_vsock_conn)
            if msg is None:
                send_log("error", "Parent connection lost")
                _shutdown_event.set()
                break
            req_id = msg.get("id")
            if req_id:
                with _pending_lock:
                    if req_id in _pending_responses:
                        _pending_responses[req_id]["response"] = msg
                        _pending_responses[req_id]["event"].set()
                    else:
                        send_log("warn", f"Unexpected response for {req_id}")
        except Exception as e:
            if not _shutdown_event.is_set():
                send_log("error", f"Dispatcher error: {e}")
                time.sleep(1)


class HTTPProxyHandler(BaseHTTPRequestHandler):
    """HTTP forward proxy that tunnels requests through vsock to the parent."""

    def do_GET(self):
        self._proxy_request("GET")

    def do_POST(self):
        self._proxy_request("POST")

    def do_PUT(self):
        self._proxy_request("PUT")

    def do_DELETE(self):
        self._proxy_request("DELETE")

    def do_PATCH(self):
        self._proxy_request("PATCH")

    def do_HEAD(self):
        self._proxy_request("HEAD")

    def do_OPTIONS(self):
        self._proxy_request("OPTIONS")

    def _proxy_request(self, method):
        try:
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length) if content_length > 0 else b""

            headers = {}
            for key, value in self.headers.items():
                if key.lower() not in ("host", "proxy-connection", "proxy-authorization"):
                    headers[key] = value

            response = send_request_and_wait("http_request", {
                "method": method,
                "url": self.path,
                "headers": headers,
                "body": body.decode("utf-8", errors="replace") if body else "",
            }, timeout=60)

            resp_payload = response.get("payload", {})
            status = resp_payload.get("status", 502)
            resp_headers = resp_payload.get("headers", {})
            resp_body = resp_payload.get("body", "").encode("utf-8")

            self.send_response(status)
            for k, v in resp_headers.items():
                if k.lower() not in ("transfer-encoding", "content-length"):
                    self.send_header(k, v)
            self.send_header("Content-Length", str(len(resp_body)))
            self.end_headers()
            self.wfile.write(resp_body)

        except TimeoutError:
            self.send_error(504, "Gateway Timeout: parent proxy did not respond")
        except Exception as e:
            self.send_error(502, f"Bad Gateway: {e}")

    def log_message(self, format, *args):
        send_log("debug", f"HTTP Proxy: {format % args}")


class KMSProxyHandler(BaseHTTPRequestHandler):
    """Local KMS proxy that forwards decrypt/encrypt requests through vsock with attestation."""

    def do_POST(self):
        try:
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length) if content_length > 0 else b""
            request_data = json.loads(body.decode("utf-8")) if body else {}

            path = urlparse(self.path).path
            operation = path.strip("/")

            response = send_request_and_wait("kms_request", {
                "operation": operation,
                "data": request_data,
            }, timeout=30)

            resp_payload = response.get("payload", {})
            if resp_payload.get("error"):
                self.send_response(400)
                resp_body = json.dumps({"error": resp_payload["error"]}).encode("utf-8")
            else:
                self.send_response(200)
                resp_body = json.dumps(resp_payload.get("result", {})).encode("utf-8")

            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(resp_body)))
            self.end_headers()
            self.wfile.write(resp_body)

        except Exception as e:
            self.send_error(500, f"KMS proxy error: {e}")

    def log_message(self, format, *args):
        send_log("debug", f"KMS Proxy: {format % args}")


class HealthCheckHandler(BaseHTTPRequestHandler):
    """Simple health check endpoint for the supervisor."""

    def do_GET(self):
        health = {
            "status": "healthy",
            "proxy": "running",
            "vsock": "connected" if _vsock_conn else "disconnected",
            "timestamp": time.time(),
        }
        body = json.dumps(health).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        pass  # Suppress health check logging


def run_http_proxy():
    """Start the HTTP forward proxy server."""
    server = HTTPServer(("127.0.0.1", HTTP_PROXY_PORT), HTTPProxyHandler)
    server.timeout = 1
    send_log("info", f"HTTP proxy listening on 127.0.0.1:{HTTP_PROXY_PORT}")
    while not _shutdown_event.is_set():
        server.handle_request()
    server.server_close()


def run_kms_proxy():
    """Start the KMS proxy server."""
    server = HTTPServer(("127.0.0.1", KMS_PROXY_PORT), KMSProxyHandler)
    server.timeout = 1
    send_log("info", f"KMS proxy listening on 127.0.0.1:{KMS_PROXY_PORT}")
    while not _shutdown_event.is_set():
        server.handle_request()
    server.server_close()


def run_health_check():
    """Start the health check server."""
    server = HTTPServer(("127.0.0.1", HEALTH_CHECK_PORT), HealthCheckHandler)
    server.timeout = 1
    while not _shutdown_event.is_set():
        server.handle_request()
    server.server_close()


def stream_process_output(proc, stream_name):
    """Read lines from a subprocess stream and send them as log messages."""
    stream = proc.stdout if stream_name == "stdout" else proc.stderr
    if stream is None:
        return
    for line in iter(stream.readline, b""):
        if _shutdown_event.is_set():
            break
        decoded = line.decode("utf-8", errors="replace").rstrip("\n")
        if decoded:
            send_log("app" if stream_name == "stdout" else "app_err", decoded)


def connect_to_parent(max_retries=30, retry_delay=10):
    """Establish vsock connection to the parent instance."""
    global _vsock_conn
    send_log("info", "Waiting for parent proxy to be ready...")
    time.sleep(5)

    for attempt in range(1, max_retries + 1):
        try:
            sock = socket.socket(socket.AF_VSOCK, socket.SOCK_STREAM)
            sock.settimeout(120)
            sock.connect((VMADDR_CID_HOST, VSOCK_PORT))
            _vsock_conn = sock

            send_message(sock, {
                "type": "handshake",
                "id": next_request_id(),
                "payload": {
                    "enclave_id": os.environ.get("ENCLAVE_ID", "unknown"),
                    "protocol_version": "2.0",
                    "capabilities": ["http_proxy", "kms_proxy", "log_stream", "health"],
                }
            })

            send_log("info", f"Connected to parent on attempt {attempt}")
            return True

        except Exception as e:
            print(f"[ENCLAVE-PROXY] Connection attempt {attempt}/{max_retries} failed: {e}",
                  flush=True)
            if attempt < max_retries:
                time.sleep(retry_delay)

    return False


def request_pcr_values():
    """Request PCR values from the parent."""
    try:
        response = send_request_and_wait("pcr_request", {}, timeout=30)
        pcr_values = response.get("payload", {}).get("pcr_values", {})
        send_log("info", f"PCR values received: {json.dumps(pcr_values)}")
        return pcr_values
    except Exception as e:
        send_log("error", f"Failed to get PCR values: {e}")
        return {}


def run_user_application():
    """Launch the user's application with proxy environment variables set."""
    user_cmd = os.environ.get("TREZA_USER_CMD", "")
    if not user_cmd:
        user_entrypoint = os.environ.get("TREZA_USER_ENTRYPOINT", "")
        user_cmd_args = os.environ.get("TREZA_USER_CMD_ARGS", "")
        if user_entrypoint:
            user_cmd = user_entrypoint
            if user_cmd_args:
                user_cmd = f"{user_entrypoint} {user_cmd_args}"

    if not user_cmd:
        send_log("warn", "No user command configured. Enclave proxy running in standalone mode.")
        return None

    env = os.environ.copy()
    env["HTTP_PROXY"] = f"http://127.0.0.1:{HTTP_PROXY_PORT}"
    env["HTTPS_PROXY"] = f"http://127.0.0.1:{HTTP_PROXY_PORT}"
    env["http_proxy"] = f"http://127.0.0.1:{HTTP_PROXY_PORT}"
    env["https_proxy"] = f"http://127.0.0.1:{HTTP_PROXY_PORT}"
    env["TREZA_KMS_ENDPOINT"] = f"http://127.0.0.1:{KMS_PROXY_PORT}"
    env["NO_PROXY"] = "127.0.0.1,localhost"
    env["no_proxy"] = "127.0.0.1,localhost"

    send_log("info", f"Starting user application: {user_cmd}")

    proc = subprocess.Popen(
        user_cmd,
        shell=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
    )

    stdout_thread = threading.Thread(
        target=stream_process_output, args=(proc, "stdout"), daemon=True
    )
    stderr_thread = threading.Thread(
        target=stream_process_output, args=(proc, "stderr"), daemon=True
    )
    stdout_thread.start()
    stderr_thread.start()

    return proc


def main():
    enclave_id = os.environ.get("ENCLAVE_ID", "unknown")
    workload_type = os.environ.get("TREZA_WORKLOAD_TYPE", "batch")
    print(f"[ENCLAVE-PROXY] Starting for enclave {enclave_id} (workload: {workload_type})",
          flush=True)

    if not connect_to_parent():
        print("[ENCLAVE-PROXY] FATAL: Could not connect to parent", flush=True)
        sys.exit(1)

    dispatcher_thread = threading.Thread(target=response_dispatcher, daemon=True)
    dispatcher_thread.start()

    send_log("info", f"Enclave proxy started for {enclave_id}")

    pcr_values = request_pcr_values()
    send_log("info", f"Enclave PCR0: {pcr_values.get('PCR0', 'N/A')}")

    proxy_threads = []
    for target in [run_http_proxy, run_kms_proxy, run_health_check]:
        t = threading.Thread(target=target, daemon=True)
        t.start()
        proxy_threads.append(t)

    time.sleep(1)

    user_proc = run_user_application()

    def handle_signal(signum, frame):
        send_log("info", f"Received signal {signum}, shutting down...")
        _shutdown_event.set()
        if user_proc and user_proc.poll() is None:
            user_proc.terminate()

    signal.signal(signal.SIGTERM, handle_signal)
    signal.signal(signal.SIGINT, handle_signal)

    if user_proc:
        if workload_type == "batch":
            exit_code = user_proc.wait()
            send_log("info", f"User application exited with code {exit_code}")

            send_message(_vsock_conn, {
                "type": "health_report",
                "id": next_request_id(),
                "payload": {
                    "status": "completed",
                    "exit_code": exit_code,
                    "workload_type": workload_type,
                }
            })
            time.sleep(5)
            _shutdown_event.set()

        elif workload_type in ("service", "daemon"):
            health_path = os.environ.get("TREZA_HEALTH_PATH", "/health")
            health_interval = int(os.environ.get("TREZA_HEALTH_INTERVAL", "30"))

            while not _shutdown_event.is_set():
                if user_proc.poll() is not None:
                    exit_code = user_proc.returncode
                    send_log("error",
                             f"Service process exited unexpectedly with code {exit_code}")
                    send_message(_vsock_conn, {
                        "type": "health_report",
                        "id": next_request_id(),
                        "payload": {
                            "status": "crashed",
                            "exit_code": exit_code,
                            "workload_type": workload_type,
                        }
                    })
                    break

                try:
                    send_message(_vsock_conn, {
                        "type": "health_report",
                        "id": next_request_id(),
                        "payload": {
                            "status": "running",
                            "workload_type": workload_type,
                        }
                    })
                except Exception:
                    pass

                _shutdown_event.wait(timeout=health_interval)
    else:
        send_log("info", "No user application; proxy running in standalone mode")
        while not _shutdown_event.is_set():
            _shutdown_event.wait(timeout=30)

    send_log("info", "Enclave proxy shutting down")


if __name__ == "__main__":
    main()
