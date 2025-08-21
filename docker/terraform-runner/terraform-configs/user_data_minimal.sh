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

# Create log directories and ALL log files FIRST (before CloudWatch agent installation)
update_status "CREATING_LOG_DIRECTORIES"
mkdir -p /var/log/enclave
chmod 755 /var/log/enclave

# Pre-create ALL log files that CloudWatch agent will monitor
touch /var/log/enclave/application.log
touch /var/log/enclave/stdout.log
touch /var/log/enclave/stderr.log

# Create robust initial log content - this ensures CloudWatch agent finds populated files
cat > /var/log/enclave/application.log << EOF
$(date '+%Y-%m-%d %H:%M:%S') [INIT] Application log initialized for enclave $ENCLAVE_ID
$(date '+%Y-%m-%d %H:%M:%S') [INIT] Docker image: $DOCKER_IMAGE
$(date '+%Y-%m-%d %H:%M:%S') [INIT] All log files pre-created for CloudWatch agent
EOF

cat > /var/log/enclave/stdout.log << EOF
$(date '+%Y-%m-%d %H:%M:%S') [INIT] Stdout log ready for enclave $ENCLAVE_ID
EOF

cat > /var/log/enclave/stderr.log << EOF
$(date '+%Y-%m-%d %H:%M:%S') [INIT] Stderr log ready for enclave $ENCLAVE_ID
EOF

# Set initial permissions (before cwagent user exists)
chmod 644 /var/log/enclave/*.log

# Install CloudWatch agent
update_status "INSTALLING_CLOUDWATCH_AGENT"
wget -q https://amazoncloudwatch-agent.s3.amazonaws.com/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm
rpm -U ./amazon-cloudwatch-agent.rpm
rm -f ./amazon-cloudwatch-agent.rpm

# Create CloudWatch agent config with proper structure
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << EOF
{
  "agent": {
    "run_as_user": "cwagent"
  },
  "logs": {
    "force_flush_interval": 1,
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/enclave/application.log",
            "log_group_name": "/aws/nitro-enclave/$ENCLAVE_ID/application",
            "log_stream_name": "{instance_id}-application",
            "timezone": "UTC",
            "timestamp_format": "%Y-%m-%d %H:%M:%S",
            "retention_in_days": 30
          },
          {
            "file_path": "/var/log/enclave/stdout.log",
            "log_group_name": "/aws/nitro-enclave/$ENCLAVE_ID/stdout",
            "log_stream_name": "{instance_id}-stdout",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/enclave/stderr.log",
            "log_group_name": "/aws/nitro-enclave/$ENCLAVE_ID/stderr",
            "log_stream_name": "{instance_id}-stderr",
            "timezone": "UTC"
          }
        ]
      }
    }
  }
}
EOF

# Ensure proper ownership of config file
chown root:root /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
chmod 644 /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

# Ensure log directory and files have proper permissions for CloudWatch agent
chown -R cwagent:cwagent /var/log/enclave/ || true
chmod 755 /var/log/enclave
chmod 644 /var/log/enclave/application.log || true

# Start CloudWatch agent with explicit config
update_status "STARTING_CLOUDWATCH"
AGENT_CTL="/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl"

# Ensure cwagent user exists (created during agent installation)
id cwagent &>/dev/null || {
    update_status "CLOUDWATCH_USER_MISSING"
    echo "ERROR: cwagent user not found after CloudWatch agent installation" >> /var/log/enclave/application.log
}

# Stop any existing agent
$AGENT_CTL -a stop || true

# Fetch and start agent with new config
if $AGENT_CTL -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s; then
    update_status "CLOUDWATCH_AGENT_STARTED"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INIT] CloudWatch agent started successfully" >> /var/log/enclave/application.log
else
    update_status "CLOUDWATCH_AGENT_FAILED"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] CloudWatch agent failed to start" >> /var/log/enclave/application.log
    # Try alternative startup method
    systemctl enable amazon-cloudwatch-agent
    systemctl restart amazon-cloudwatch-agent
fi

# Give the agent time to initialize and fix permissions after startup
sleep 5
chown -R cwagent:cwagent /var/log/enclave/ || true
echo "$(date '+%Y-%m-%d %H:%M:%S') [INIT] CloudWatch agent initialization completed" >> /var/log/enclave/application.log

# Force a log line to trigger CloudWatch log stream creation
echo "$(date '+%Y-%m-%d %H:%M:%S') [TEST] CloudWatch agent test - application logging ready" >> /var/log/enclave/application.log
echo "$(date '+%Y-%m-%d %H:%M:%S') [TEST] Force log flush" >> /var/log/enclave/application.log

# Start Docker container and forward logs
update_status "STARTING_DOCKER_CONTAINER"
docker run -d --name enclave-app "$DOCKER_IMAGE" > /tmp/container_id

update_status "CONFIGURING_LOG_FORWARDING"

# Create all log files that CloudWatch agent expects
touch /var/log/enclave/stdout.log /var/log/enclave/stderr.log

# Get container ID
CONTAINER_ID=$(cat /tmp/container_id)
echo "$(date '+%Y-%m-%d %H:%M:%S') [INIT] Starting log forwarding for container: $CONTAINER_ID" >> /var/log/enclave/application.log

# Capture Docker container logs immediately
docker logs "$CONTAINER_ID" > /var/log/enclave/stdout.log 2> /var/log/enclave/stderr.log || true

# Create comprehensive application logs
echo "$(date '+%Y-%m-%d %H:%M:%S') [APP] Container started: $DOCKER_IMAGE" >> /var/log/enclave/application.log
echo "$(date '+%Y-%m-%d %H:%M:%S') [APP] Container ID: $CONTAINER_ID" >> /var/log/enclave/application.log

# Capture all container output to application log
docker logs "$CONTAINER_ID" 2>&1 | while IFS= read -r line; do
  echo "$(date '+%Y-%m-%d %H:%M:%S') [APP] $line" >> /var/log/enclave/application.log
done || true

echo "$(date '+%Y-%m-%d %H:%M:%S') [INIT] Container log capture completed" >> /var/log/enclave/application.log

# Add hello-world specific logs since it's a simple container
if [[ "$DOCKER_IMAGE" == "hello-world" ]]; then
  echo "$(date '+%Y-%m-%d %H:%M:%S') [APP] Hello-world container has completed execution" >> /var/log/enclave/application.log
  echo "$(date '+%Y-%m-%d %H:%M:%S') [APP] Container exit code: $(docker inspect $CONTAINER_ID --format='{{.State.ExitCode}}')" >> /var/log/enclave/application.log
fi

# Set proper permissions for CloudWatch agent
chown cwagent:cwagent /var/log/enclave/*.log || true
chmod 644 /var/log/enclave/*.log

# Verify log files were created and fix final permissions
ls -la /var/log/enclave/ || true
chown cwagent:cwagent /var/log/enclave/*.log || true
chmod 644 /var/log/enclave/*.log

echo "$(date '+%Y-%m-%d %H:%M:%S') [INIT] Log files created and ready for CloudWatch agent" >> /var/log/enclave/application.log
echo "$(date '+%Y-%m-%d %H:%M:%S') [INIT] Final log capture and permissions completed" >> /var/log/enclave/application.log

# Restart CloudWatch agent to ensure it picks up all our log files with fresh content
update_status "RESTARTING_CLOUDWATCH_AGENT"
echo "$(date '+%Y-%m-%d %H:%M:%S') [INIT] Restarting CloudWatch agent to pick up populated log files" >> /var/log/enclave/application.log
systemctl restart amazon-cloudwatch-agent || true
sleep 5

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

        ]
      }
    }
  }
}
EOF

# Ensure proper ownership of config file
chown root:root /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
chmod 644 /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

# Ensure log directory and files have proper permissions for CloudWatch agent
chown -R cwagent:cwagent /var/log/enclave/ || true
chmod 755 /var/log/enclave
chmod 644 /var/log/enclave/application.log || true

# Start CloudWatch agent with explicit config
update_status "STARTING_CLOUDWATCH"
AGENT_CTL="/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl"

# Ensure cwagent user exists (created during agent installation)
id cwagent &>/dev/null || {
    update_status "CLOUDWATCH_USER_MISSING"
    echo "ERROR: cwagent user not found after CloudWatch agent installation" >> /var/log/enclave/application.log
}

# Stop any existing agent
$AGENT_CTL -a stop || true

# Fetch and start agent with new config
if $AGENT_CTL -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s; then
    update_status "CLOUDWATCH_AGENT_STARTED"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INIT] CloudWatch agent started successfully" >> /var/log/enclave/application.log
else
    update_status "CLOUDWATCH_AGENT_FAILED"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] CloudWatch agent failed to start" >> /var/log/enclave/application.log
    # Try alternative startup method
    systemctl enable amazon-cloudwatch-agent
    systemctl restart amazon-cloudwatch-agent
fi

# Give the agent time to initialize and fix permissions after startup
sleep 5
chown -R cwagent:cwagent /var/log/enclave/ || true
echo "$(date '+%Y-%m-%d %H:%M:%S') [INIT] CloudWatch agent initialization completed" >> /var/log/enclave/application.log

# Force a log line to trigger CloudWatch log stream creation
echo "$(date '+%Y-%m-%d %H:%M:%S') [TEST] CloudWatch agent test - application logging ready" >> /var/log/enclave/application.log
echo "$(date '+%Y-%m-%d %H:%M:%S') [TEST] Force log flush" >> /var/log/enclave/application.log

# Start Docker container and forward logs
update_status "STARTING_DOCKER_CONTAINER"
docker run -d --name enclave-app "$DOCKER_IMAGE" > /tmp/container_id

update_status "CONFIGURING_LOG_FORWARDING"

# Create all log files that CloudWatch agent expects
touch /var/log/enclave/stdout.log /var/log/enclave/stderr.log

# Get container ID
CONTAINER_ID=$(cat /tmp/container_id)
echo "$(date '+%Y-%m-%d %H:%M:%S') [INIT] Starting log forwarding for container: $CONTAINER_ID" >> /var/log/enclave/application.log

# Capture Docker container logs immediately
docker logs "$CONTAINER_ID" > /var/log/enclave/stdout.log 2> /var/log/enclave/stderr.log || true

# Create comprehensive application logs
echo "$(date '+%Y-%m-%d %H:%M:%S') [APP] Container started: $DOCKER_IMAGE" >> /var/log/enclave/application.log
echo "$(date '+%Y-%m-%d %H:%M:%S') [APP] Container ID: $CONTAINER_ID" >> /var/log/enclave/application.log

# Capture all container output to application log
docker logs "$CONTAINER_ID" 2>&1 | while IFS= read -r line; do
  echo "$(date '+%Y-%m-%d %H:%M:%S') [APP] $line" >> /var/log/enclave/application.log
done || true

echo "$(date '+%Y-%m-%d %H:%M:%S') [INIT] Container log capture completed" >> /var/log/enclave/application.log

# Add hello-world specific logs since it's a simple container
if [[ "$DOCKER_IMAGE" == "hello-world" ]]; then
  echo "$(date '+%Y-%m-%d %H:%M:%S') [APP] Hello-world container has completed execution" >> /var/log/enclave/application.log
  echo "$(date '+%Y-%m-%d %H:%M:%S') [APP] Container exit code: $(docker inspect $CONTAINER_ID --format='{{.State.ExitCode}}')" >> /var/log/enclave/application.log
fi

# Set proper permissions for CloudWatch agent
chown cwagent:cwagent /var/log/enclave/*.log || true
chmod 644 /var/log/enclave/*.log

# Verify log files were created and fix final permissions
ls -la /var/log/enclave/ || true
chown cwagent:cwagent /var/log/enclave/*.log || true
chmod 644 /var/log/enclave/*.log

echo "$(date '+%Y-%m-%d %H:%M:%S') [INIT] Log files created and ready for CloudWatch agent" >> /var/log/enclave/application.log
echo "$(date '+%Y-%m-%d %H:%M:%S') [INIT] Final log capture and permissions completed" >> /var/log/enclave/application.log

# Restart CloudWatch agent to ensure it picks up all our log files with fresh content
update_status "RESTARTING_CLOUDWATCH_AGENT"
echo "$(date '+%Y-%m-%d %H:%M:%S') [INIT] Restarting CloudWatch agent to pick up populated log files" >> /var/log/enclave/application.log
systemctl restart amazon-cloudwatch-agent || true
sleep 5

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
