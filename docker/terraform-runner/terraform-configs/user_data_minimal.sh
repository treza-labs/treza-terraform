#!/bin/bash
set -e

# Variables from template
ENCLAVE_ID="${enclave_id}"
CPU_COUNT="${cpu_count}"
MEMORY_MIB="${memory_mib}"
DOCKER_IMAGE="${docker_image}"

# Function to update status
update_status() {
    local status="$1"
    REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
    aws ssm put-parameter --name "/treza/$ENCLAVE_ID/status" --value "$status" --type "String" --overwrite --region $REGION 2>/dev/null || true
}

# Set initial status
update_status "BOOTING"

# Update system and install packages
update_status "INSTALLING_PACKAGES"
yum update -y
yum install -y docker aws-cli wget jq

# Install AWS Nitro Enclaves CLI
update_status "INSTALLING_NITRO_CLI"
amazon-linux-extras install -y aws-nitro-enclaves-cli

# Start services
update_status "STARTING_SERVICES"
systemctl enable docker
systemctl start docker
systemctl enable nitro-enclaves-allocator
systemctl start nitro-enclaves-allocator

# Configure Nitro allocator
update_status "CONFIGURING_NITRO"
mkdir -p /etc/nitro_enclaves

update_status "CREATING_ALLOCATOR_CONFIG"
echo "cpu_count: $CPU_COUNT" > /etc/nitro_enclaves/allocator.yaml
echo "memory_mib: $MEMORY_MIB" >> /etc/nitro_enclaves/allocator.yaml

update_status "CHECKING_NITRO_MODULES"
# Load required kernel modules
modprobe nitro_enclaves || true
modprobe vhost_vsock || true

update_status "CHECKING_ALLOCATOR_STATUS"
# Check current allocator status
systemctl status nitro-enclaves-allocator || true

update_status "RESTARTING_NITRO_ALLOCATOR"
# Restart with timeout to prevent hanging
timeout 60 systemctl restart nitro-enclaves-allocator || {
    update_status "ALLOCATOR_RESTART_FAILED"
    # Try to continue without full restart
    systemctl start nitro-enclaves-allocator || true
}

update_status "VALIDATING_ALLOCATOR"
# Validate allocator is running properly
if systemctl is-active --quiet nitro-enclaves-allocator; then
    update_status "ALLOCATOR_RUNNING"
else
    update_status "ALLOCATOR_NOT_RUNNING"
    # Try one more time to start it
    systemctl start nitro-enclaves-allocator || true
fi

update_status "CONFIGURING_USER_GROUPS"
usermod -a -G docker ec2-user
usermod -a -G ne ec2-user

# Install CloudWatch agent
update_status "INSTALLING_CLOUDWATCH_AGENT"
wget -q https://amazoncloudwatch-agent.s3.amazonaws.com/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm
rpm -U ./amazon-cloudwatch-agent.rpm
rm -f ./amazon-cloudwatch-agent.rpm

# Create log directories
update_status "CREATING_LOG_DIRECTORIES"
mkdir -p /var/log/enclave
chmod 755 /var/log/enclave

# Create CloudWatch agent config
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << EOF
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/enclave/application.log",
            "log_group_name": "/aws/nitro-enclave/$ENCLAVE_ID/application",
            "log_stream_name": "{instance_id}-application",
            "timezone": "UTC"
          }
        ]
      }
    }
  }
}
EOF

# Start CloudWatch agent
update_status "STARTING_CLOUDWATCH"
systemctl enable amazon-cloudwatch-agent
systemctl start amazon-cloudwatch-agent

# Start Docker container and forward logs
update_status "STARTING_DOCKER_CONTAINER"
docker run -d --name enclave-app "$DOCKER_IMAGE" > /tmp/container_id

update_status "CONFIGURING_LOG_FORWARDING"

# Forward container logs to application log file
{
  while docker ps -q --filter name=enclave-app | grep -q .; do
    docker logs -f enclave-app 2>&1 | while IFS= read -r line; do
      echo "$(date '+%Y-%m-%d %H:%M:%S') [APP] $line" >> /var/log/enclave/application.log
    done &
    sleep 10
  done
} &

# Generate test logs for nginx
if [[ "$DOCKER_IMAGE" == *"nginx"* ]]; then
  sleep 5
  docker exec enclave-app sh -c "curl -s http://localhost >/dev/null || true" 2>/dev/null || true
  echo "$(date '+%Y-%m-%d %H:%M:%S') [INIT] Nginx container started and accessible" >> /var/log/enclave/application.log
fi

# Update SSM status
REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
aws ssm put-parameter --name "/treza/$ENCLAVE_ID/status" --value "READY" --type "String" --overwrite --region $REGION 2>/dev/null || true

echo "=== Enclave $ENCLAVE_ID setup completed ==="
