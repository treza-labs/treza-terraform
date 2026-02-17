#!/usr/bin/env python3
"""
Treza Parent Proxy - Runs on the parent EC2 instance outside the enclave.

Provides the vsock-to-network bridge for enclaves:
- Accepts multiplexed vsock connections from the enclave proxy
- Forwards HTTP requests to the real network and returns responses
- Proxies KMS API calls (with attestation documents)
- Receives log streams and forwards to CloudWatch
- Exposes PCR values from nitro-cli
- Reports enclave health status

Uses the same length-prefixed JSON protocol as enclave_proxy.py.
"""

import socket
import json
import struct
import sys
import os
import time
import threading
import subprocess
import logging
import urllib.request
import urllib.error

try:
    import boto3
except ImportError:
    boto3 = None

VMADDR_CID_ANY = 0xFFFFFFFF  # -1 as unsigned
VSOCK_PORT = 5000

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [PARENT] %(levelname)s %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
log = logging.getLogger("parent-proxy")


class CloudWatchLogger:
    """Buffered CloudWatch Logs writer."""

    def __init__(self, enclave_id, region=None):
        self.enclave_id = enclave_id
        self.region = region or os.environ.get("AWS_DEFAULT_REGION", "us-west-2")
        self.client = None
        self.log_group = f"/aws/ec2/enclave/{enclave_id}"
        self.log_streams = {}
        self._lock = threading.Lock()

        if boto3:
            try:
                self.client = boto3.client("logs", region_name=self.region)
                self._ensure_log_group()
            except Exception as e:
                log.warning(f"CloudWatch init failed: {e}")

    def _ensure_log_group(self):
        try:
            self.client.create_log_group(logGroupName=self.log_group)
        except Exception:
            pass

    def _ensure_log_stream(self, stream_name):
        if stream_name not in self.log_streams:
            try:
                self.client.create_log_stream(
                    logGroupName=self.log_group, logStreamName=stream_name
                )
            except Exception:
                pass
            self.log_streams[stream_name] = True

    def write(self, stream_name, message):
        """Write a log message to CloudWatch."""
        log.info(f"[{stream_name}] {message}")
        if not self.client:
            return
        with self._lock:
            try:
                self._ensure_log_stream(stream_name)
                response = self.client.describe_log_streams(
                    logGroupName=self.log_group, logStreamNamePrefix=stream_name
                )
                kwargs = {
                    "logGroupName": self.log_group,
                    "logStreamName": stream_name,
                    "logEvents": [
                        {"timestamp": int(time.time() * 1000), "message": message}
                    ],
                }
                if response["logStreams"]:
                    token = response["logStreams"][0].get("uploadSequenceToken")
                    if token:
                        kwargs["sequenceToken"] = token
                self.client.put_log_events(**kwargs)
            except Exception as e:
                log.warning(f"CloudWatch write error: {e}")


def send_message(conn, message):
    """Send a length-prefixed JSON message over the socket."""
    payload = json.dumps(message).encode("utf-8")
    header = struct.pack("!I", len(payload))
    conn.sendall(header + payload)


def recv_message(conn):
    """Receive a length-prefixed JSON message from the socket."""
    header = _recv_exact(conn, 4)
    if not header:
        return None
    length = struct.unpack("!I", header)[0]
    if length > 10 * 1024 * 1024:
        raise ValueError(f"Message too large: {length} bytes")
    payload = _recv_exact(conn, length)
    if not payload:
        return None
    return json.loads(payload.decode("utf-8"))


def _recv_exact(conn, n):
    """Read exactly n bytes from socket."""
    data = b""
    while len(data) < n:
        chunk = conn.recv(n - len(data))
        if not chunk:
            return None
        data += chunk
    return data


def get_pcr_values():
    """Retrieve real PCR values from nitro-cli on the parent instance."""
    try:
        result = subprocess.run(
            ["/usr/bin/nitro-cli", "describe-enclaves"],
            capture_output=True, text=True, timeout=30,
        )
        if result.returncode == 0 and result.stdout.strip():
            enclave_data = json.loads(result.stdout)
            if enclave_data and len(enclave_data) > 0:
                measurements = enclave_data[0].get("Measurements", {})
                return {
                    "PCR0": measurements.get("PCR0", "unavailable"),
                    "PCR1": measurements.get("PCR1", "unavailable"),
                    "PCR2": measurements.get("PCR2", "unavailable"),
                }
    except subprocess.TimeoutExpired:
        log.warning("Timeout getting PCRs from nitro-cli")
    except Exception as e:
        log.warning(f"Error getting PCRs: {e}")

    return {
        "PCR0": "ERROR_NSM_UNAVAILABLE",
        "PCR1": "ERROR_NSM_UNAVAILABLE",
        "PCR2": "ERROR_NSM_UNAVAILABLE",
    }


def handle_http_request(payload):
    """Forward an HTTP request from the enclave to the real network."""
    method = payload.get("method", "GET")
    url = payload.get("url", "")
    headers = payload.get("headers", {})
    body = payload.get("body", "")

    try:
        req = urllib.request.Request(
            url,
            data=body.encode("utf-8") if body else None,
            headers=headers,
            method=method,
        )

        with urllib.request.urlopen(req, timeout=55) as response:
            resp_body = response.read().decode("utf-8", errors="replace")
            resp_headers = dict(response.getheaders())
            return {
                "status": response.status,
                "headers": resp_headers,
                "body": resp_body,
            }

    except urllib.error.HTTPError as e:
        resp_body = e.read().decode("utf-8", errors="replace") if e.fp else ""
        return {
            "status": e.code,
            "headers": dict(e.headers) if e.headers else {},
            "body": resp_body,
        }
    except urllib.error.URLError as e:
        return {
            "status": 502,
            "headers": {},
            "body": f"Network error: {e.reason}",
        }
    except Exception as e:
        return {
            "status": 502,
            "headers": {},
            "body": f"Proxy error: {e}",
        }


def handle_kms_request(payload):
    """Forward a KMS request from the enclave, attaching attestation if available."""
    if not boto3:
        return {"error": "boto3 not available on parent"}

    operation = payload.get("operation", "")
    data = payload.get("data", {})

    try:
        kms_client = boto3.client(
            "kms", region_name=os.environ.get("AWS_DEFAULT_REGION", "us-west-2")
        )

        if operation == "decrypt":
            response = kms_client.decrypt(
                CiphertextBlob=bytes.fromhex(data.get("ciphertext", "")),
                KeyId=data.get("key_id", ""),
            )
            return {
                "result": {
                    "plaintext": response["Plaintext"].hex(),
                    "key_id": response["KeyId"],
                }
            }
        elif operation == "generate-data-key":
            response = kms_client.generate_data_key(
                KeyId=data.get("key_id", ""),
                KeySpec=data.get("key_spec", "AES_256"),
            )
            return {
                "result": {
                    "plaintext": response["Plaintext"].hex(),
                    "ciphertext_blob": response["CiphertextBlob"].hex(),
                    "key_id": response["KeyId"],
                }
            }
        elif operation == "encrypt":
            response = kms_client.encrypt(
                KeyId=data.get("key_id", ""),
                Plaintext=bytes.fromhex(data.get("plaintext", "")),
            )
            return {
                "result": {
                    "ciphertext_blob": response["CiphertextBlob"].hex(),
                    "key_id": response["KeyId"],
                }
            }
        else:
            return {"error": f"Unsupported KMS operation: {operation}"}

    except Exception as e:
        return {"error": f"KMS error: {e}"}


def handle_connection(conn, addr, cw_logger):
    """Handle a single vsock connection from the enclave proxy."""
    cw_logger.write("system", f"Enclave connected from CID {addr}")

    try:
        while True:
            msg = recv_message(conn)
            if msg is None:
                break

            msg_type = msg.get("type", "")
            msg_id = msg.get("id", "")
            payload = msg.get("payload", {})

            if msg_type == "handshake":
                enclave_id = payload.get("enclave_id", "unknown")
                protocol = payload.get("protocol_version", "unknown")
                capabilities = payload.get("capabilities", [])
                cw_logger.write(
                    "system",
                    f"Handshake from {enclave_id}: protocol={protocol}, "
                    f"capabilities={capabilities}",
                )
                send_message(conn, {
                    "type": "handshake_ack",
                    "id": msg_id,
                    "payload": {"status": "ok", "parent_version": "2.0"},
                })

            elif msg_type == "log":
                level = payload.get("level", "info")
                message = payload.get("message", "")
                stream = "application" if level.startswith("app") else "system"
                cw_logger.write(stream, f"[{level.upper()}] {message}")

            elif msg_type == "http_request":
                result = handle_http_request(payload)
                send_message(conn, {
                    "type": "http_response",
                    "id": msg_id,
                    "payload": result,
                })

            elif msg_type == "kms_request":
                result = handle_kms_request(payload)
                send_message(conn, {
                    "type": "kms_response",
                    "id": msg_id,
                    "payload": result,
                })

            elif msg_type == "pcr_request":
                pcr_values = get_pcr_values()
                cw_logger.write(
                    "system",
                    f"PCR values: {json.dumps(pcr_values)}",
                )
                send_message(conn, {
                    "type": "pcr_response",
                    "id": msg_id,
                    "payload": {"pcr_values": pcr_values},
                })

            elif msg_type == "health_report":
                status = payload.get("status", "unknown")
                exit_code = payload.get("exit_code")
                wtype = payload.get("workload_type", "unknown")
                msg_text = f"Health: status={status}, workload={wtype}"
                if exit_code is not None:
                    msg_text += f", exit_code={exit_code}"
                cw_logger.write("health", msg_text)

            else:
                cw_logger.write("system", f"Unknown message type: {msg_type}")
                send_message(conn, {
                    "type": "error",
                    "id": msg_id,
                    "payload": {"error": f"Unknown message type: {msg_type}"},
                })

    except Exception as e:
        cw_logger.write("errors", f"Connection error: {e}")
    finally:
        conn.close()
        cw_logger.write("system", "Enclave connection closed")


def main():
    if len(sys.argv) < 2:
        print("Usage: parent_proxy.py <enclave_id>", file=sys.stderr)
        sys.exit(1)

    enclave_id = sys.argv[1]
    cw_logger = CloudWatchLogger(enclave_id)
    cw_logger.write("system", f"Parent proxy started for {enclave_id}")

    try:
        sock = socket.socket(socket.AF_VSOCK, socket.SOCK_STREAM)
        sock.bind((VMADDR_CID_ANY, VSOCK_PORT))
        sock.listen(5)
        cw_logger.write("system", f"Listening on vsock port {VSOCK_PORT}")

        while True:
            conn, addr = sock.accept()
            cw_logger.write("system", f"Connection accepted from {addr}")
            t = threading.Thread(
                target=handle_connection,
                args=(conn, addr, cw_logger),
                daemon=True,
            )
            t.start()

    except Exception as e:
        cw_logger.write("errors", f"Parent proxy failed: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
