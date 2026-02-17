#!/bin/bash
# Treza Enclave Entrypoint - Supervisor
#
# Runs inside the Nitro Enclave as PID 1. Starts the vsock proxy first,
# then launches the user's application with HTTP_PROXY configured.
#
# Environment variables (set during composite image build or at runtime):
#   ENCLAVE_ID              - Unique enclave identifier
#   TREZA_WORKLOAD_TYPE     - "batch", "service", or "daemon"
#   TREZA_USER_CMD          - Full command to run the user's application
#   TREZA_USER_ENTRYPOINT   - Original ENTRYPOINT from the user's Docker image
#   TREZA_USER_CMD_ARGS     - Original CMD from the user's Docker image
#   TREZA_HEALTH_PATH       - Health check path for service workloads (default: /health)
#   TREZA_HEALTH_INTERVAL   - Health check interval in seconds (default: 30)
#   TREZA_AWS_SERVICES      - Comma-separated AWS services to proxy (e.g., "kms,s3")

set -euo pipefail

echo "[TREZA-ENTRYPOINT] Starting Treza enclave supervisor"
echo "[TREZA-ENTRYPOINT] Enclave ID: ${ENCLAVE_ID:-unknown}"
echo "[TREZA-ENTRYPOINT] Workload type: ${TREZA_WORKLOAD_TYPE:-batch}"
echo "[TREZA-ENTRYPOINT] User command: ${TREZA_USER_CMD:-${TREZA_USER_ENTRYPOINT:-none}}"

# Ensure the proxy script is available
if [ ! -f /opt/enclave-proxy/enclave_proxy.py ]; then
    echo "[TREZA-ENTRYPOINT] ERROR: enclave_proxy.py not found"
    exit 1
fi

# Check if Python 3 is available
if ! command -v python3 &>/dev/null; then
    echo "[TREZA-ENTRYPOINT] ERROR: python3 not found in enclave image"
    echo "[TREZA-ENTRYPOINT] The user's Docker image must include Python 3"
    exit 1
fi

# Run the enclave proxy (it handles launching the user app internally)
exec python3 /opt/enclave-proxy/enclave_proxy.py
