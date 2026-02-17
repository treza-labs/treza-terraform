#!/bin/bash
set -e
exec > >(tee -a /var/log/cloud-init-output.log) 2>&1

# ── Terraform template variables ──────────────────────────────────────────────
enclave_id="${enclave_id}"
cpu_count="${cpu_count}"
memory_mib="${memory_mib}"
docker_image="${docker_image}"
workload_type="${workload_type}"
health_check_path="${health_check_path}"
health_check_interval="${health_check_interval}"
aws_services="${aws_services}"
expose_ports="${expose_ports}"
scripts_bucket="${scripts_bucket}"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $1"; }
log "Starting enclave deployment for $enclave_id"
log "  Image:          $docker_image"
log "  Workload type:  $workload_type"
log "  CPU:            $cpu_count"
log "  Memory (MiB):   $memory_mib"

# ── Install dependencies ──────────────────────────────────────────────────────
yum update -y
yum install -y docker python3 python3-pip curl jq
pip3 install boto3
systemctl start docker
systemctl enable docker
amazon-linux-extras install aws-nitro-enclaves-cli -y
yum install -y aws-nitro-enclaves-cli-devel

# ── Bring CPUs online ─────────────────────────────────────────────────────────
log "Bringing all CPUs online..."
for cpu in /sys/devices/system/cpu/cpu[1-9]*; do
  if [ -f "$cpu/online" ]; then echo 1 > "$cpu/online" 2>/dev/null || true; fi
done

cat > /etc/systemd/system/cpu-monitor.service << 'CPUEOF'
[Unit]
Description=CPU Monitor for Nitro Enclaves
After=multi-user.target
[Service]
Type=simple
ExecStart=/bin/bash -c 'while true; do for cpu in /sys/devices/system/cpu/cpu[1-9]*; do if [ -f "$cpu/online" ] && [ $(cat "$cpu/online") -eq 0 ]; then echo 1 > "$cpu/online" 2>/dev/null || true; fi; done; sleep 5; done'
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
CPUEOF
systemctl enable cpu-monitor.service
systemctl start cpu-monitor.service
log "CPUs online: $(cat /sys/devices/system/cpu/online)"

# ── Configure Nitro Enclaves allocator ────────────────────────────────────────
log "Configuring Nitro Enclaves allocator..."
mkdir -p /etc/nitro_enclaves
cat > /etc/nitro_enclaves/allocator.yaml << EOF
---
memory_mib: $memory_mib
cpu_count: $cpu_count
EOF
systemctl enable nitro-enclaves-allocator.service
systemctl start nitro-enclaves-allocator.service
sleep 5

# ── Pull the user's Docker image ─────────────────────────────────────────────
log "Pulling user image: $docker_image"
docker pull "$docker_image" || {
  log "ERROR: Failed to pull $docker_image"
  exit 1
}

# ── Inspect user image entrypoint and cmd ─────────────────────────────────────
log "Inspecting user image for entrypoint and cmd..."
USER_ENTRYPOINT=$(docker inspect --format='{{json .Config.Entrypoint}}' "$docker_image" 2>/dev/null || echo "null")
USER_CMD=$(docker inspect --format='{{json .Config.Cmd}}' "$docker_image" 2>/dev/null || echo "null")

if [ "$USER_ENTRYPOINT" = "null" ] || [ "$USER_ENTRYPOINT" = "" ]; then
  USER_ENTRYPOINT=""
else
  USER_ENTRYPOINT=$(echo "$USER_ENTRYPOINT" | jq -r 'join(" ")')
fi

if [ "$USER_CMD" = "null" ] || [ "$USER_CMD" = "" ]; then
  USER_CMD=""
else
  USER_CMD=$(echo "$USER_CMD" | jq -r 'join(" ")')
fi

# Build TREZA_USER_CMD from the inspected entrypoint + cmd
TREZA_USER_CMD=""
if [ -n "$USER_ENTRYPOINT" ] && [ -n "$USER_CMD" ]; then
  TREZA_USER_CMD="$USER_ENTRYPOINT $USER_CMD"
elif [ -n "$USER_ENTRYPOINT" ]; then
  TREZA_USER_CMD="$USER_ENTRYPOINT"
elif [ -n "$USER_CMD" ]; then
  TREZA_USER_CMD="$USER_CMD"
fi

log "User entrypoint: $USER_ENTRYPOINT"
log "User cmd:        $USER_CMD"
log "Combined:        $TREZA_USER_CMD"

# ── Download proxy scripts from S3 ────────────────────────────────────────────
log "Downloading proxy scripts from S3 bucket: $scripts_bucket"
aws s3 cp "s3://$scripts_bucket/parent_proxy.py" /tmp/parent_proxy.py
aws s3 cp "s3://$scripts_bucket/enclave-proxy" /tmp/enclave-proxy
chmod +x /tmp/enclave-proxy
log "Proxy scripts downloaded successfully"

# ── Build the composite enclave image ─────────────────────────────────────────
log "Building composite enclave image (Rust proxy, no Python dependency)..."

cat > /tmp/Dockerfile.composite << DEOF
FROM $docker_image
COPY enclave-proxy /opt/enclave-proxy/enclave-proxy
ENV ENCLAVE_ID=$enclave_id
ENV TREZA_WORKLOAD_TYPE=$workload_type
ENV TREZA_USER_CMD="$TREZA_USER_CMD"
ENV TREZA_USER_ENTRYPOINT="$USER_ENTRYPOINT"
ENV TREZA_USER_CMD_ARGS="$USER_CMD"
ENV TREZA_HEALTH_PATH=$health_check_path
ENV TREZA_HEALTH_INTERVAL=$health_check_interval
ENV TREZA_AWS_SERVICES=$aws_services
ENV TREZA_EXPOSE_PORTS=$expose_ports
ENTRYPOINT ["/opt/enclave-proxy/enclave-proxy"]
CMD []
DEOF

cd /tmp
docker build -t treza-enclave:latest -f Dockerfile.composite .

# ── Build the EIF ────────────────────────────────────────────────────────────
log "Building Enclave Image File (EIF)..."
export NITRO_CLI_ARTIFACTS=/tmp/nitro_artifacts
mkdir -p $NITRO_CLI_ARTIFACTS
nitro-cli build-enclave --docker-uri treza-enclave:latest --output-file /tmp/treza-enclave.eif

# ── Start the parent proxy ───────────────────────────────────────────────────
log "Starting parent proxy v2.0..."
python3 /tmp/parent_proxy.py "$enclave_id" &
PARENT_PID=$!
sleep 15

# ── Ensure CPUs and restart allocator ─────────────────────────────────────────
log "Ensuring CPUs are online before starting enclave..."
for i in {1..5}; do
  for cpu in /sys/devices/system/cpu/cpu[1-9]*; do
    if [ -f "$cpu/online" ]; then echo 1 > "$cpu/online" 2>/dev/null || true; fi
  done
  sleep 2
done
log "Restarting allocator to recognize all CPUs..."
systemctl restart nitro-enclaves-allocator
sleep 10

# ── Launch the enclave ───────────────────────────────────────────────────────
log "Starting enclave (cpu=$cpu_count, mem=$memory_mib, workload=$workload_type)..."
ENCLAVE_OUTPUT=$(nitro-cli run-enclave \
  --cpu-count "$cpu_count" \
  --memory "$memory_mib" \
  --eif-path /tmp/treza-enclave.eif \
  --enclave-name treza-enclave \
  --debug-mode 2>&1)
ENCLAVE_STATUS=$?

log "Enclave start output: $ENCLAVE_OUTPUT"
log "Enclave start status: $ENCLAVE_STATUS"

if [ $ENCLAVE_STATUS -eq 0 ]; then
  log "Enclave started successfully"
  ACTUAL_ENCLAVE_ID=$(echo "$ENCLAVE_OUTPUT" | grep -o '"EnclaveId": "[^"]*"' | cut -d'"' -f4)
  log "Nitro Enclave ID: $ACTUAL_ENCLAVE_ID"

  # Monitor the enclave
  for i in {1..12}; do
    ENCLAVE_DESC=$(nitro-cli describe-enclaves 2>/dev/null)
    log "Enclave status check $i: $ENCLAVE_DESC"
    sleep 10
  done
else
  log "ERROR: Enclave failed to start"
fi

log "Deployment completed - user workload running inside the enclave"
log "Check CloudWatch logs at /aws/ec2/enclave/$enclave_id"
