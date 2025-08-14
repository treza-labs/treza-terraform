#!/bin/bash
# Enclave Logging Setup Script
# This script sets up CloudWatch logging for Docker containers running inside Nitro Enclaves

set -e

# Variables
ENCLAVE_ID="${1:-unknown}"
DOCKER_IMAGE="${2:-hello-world}"
CONTAINER_NAME="${3:-enclave-app}"

echo "🔧 Setting up application logging for enclave: $ENCLAVE_ID"

# Create log directories
mkdir -p /var/log/enclave
chmod 755 /var/log/enclave

# Install CloudWatch agent if not present
if ! command -v /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent &> /dev/null; then
    echo "📦 Installing CloudWatch agent..."
    wget -q https://amazoncloudwatch-agent.s3.amazonaws.com/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm
    rpm -U ./amazon-cloudwatch-agent.rpm
    rm -f ./amazon-cloudwatch-agent.rpm
fi

# Create CloudWatch agent configuration
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << EOF
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "root"
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/enclave/application.log",
            "log_group_name": "/aws/nitro-enclave/${ENCLAVE_ID}/application",
            "log_stream_name": "{instance_id}-application",
            "timezone": "UTC",
            "timestamp_format": "%Y-%m-%d %H:%M:%S"
          },
          {
            "file_path": "/var/log/enclave/stdout.log",
            "log_group_name": "/aws/nitro-enclave/${ENCLAVE_ID}/stdout",
            "log_stream_name": "{instance_id}-stdout",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/enclave/stderr.log",
            "log_group_name": "/aws/nitro-enclave/${ENCLAVE_ID}/stderr",
            "log_stream_name": "{instance_id}-stderr",
            "timezone": "UTC"
          }
        ]
      }
    }
  }
}
EOF

echo "🚀 Starting CloudWatch agent..."
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
    -a fetch-config \
    -m ec2 \
    -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
    -s

# Function to run Docker container with logging
run_container_with_logging() {
    local image="$1"
    local container_name="$2"
    
    echo "🐳 Starting Docker container with logging: $image"
    
    # Remove container if it exists
    docker rm -f "$container_name" 2>/dev/null || true
    
    # Run container with log forwarding
    docker run -d \
        --name "$container_name" \
        --log-driver=json-file \
        --log-opt max-size=10m \
        --log-opt max-file=3 \
        "$image" > /tmp/container_id
    
    local container_id=$(cat /tmp/container_id)
    echo "📋 Container started with ID: $container_id"
    
    # Set up log forwarding in background
    {
        # Forward stdout
        docker logs -f "$container_name" 2>/dev/null | while IFS= read -r line; do
            echo "$(date '+%Y-%m-%d %H:%M:%S') $line" >> /var/log/enclave/stdout.log
        done &
        
        # Forward stderr  
        docker logs -f "$container_name" --since=1s 2>&1 >/dev/null | while IFS= read -r line; do
            echo "$(date '+%Y-%m-%d %H:%M:%S') $line" >> /var/log/enclave/stderr.log
        done &
        
        # Monitor container and forward application logs if they exist
        while docker ps -q --filter "id=$container_id" | grep -q .; do
            # Check if container has application logs
            if docker exec "$container_name" test -f /app/logs/application.log 2>/dev/null; then
                docker exec "$container_name" tail -f /app/logs/application.log 2>/dev/null | while IFS= read -r line; do
                    echo "$(date '+%Y-%m-%d %H:%M:%S') $line" >> /var/log/enclave/application.log
                done &
            fi
            sleep 10
        done
    } &
    
    echo "✅ Container logging setup complete"
    return 0
}

# Create systemd service for container management
create_container_service() {
    local image="$1"
    local container_name="$2"
    
    cat > /etc/systemd/system/enclave-container.service << EOF
[Unit]
Description=Enclave Docker Container
After=docker.service
Requires=docker.service

[Service]
Type=forking
ExecStart=/bin/bash -c 'source /opt/enclave-logging-setup.sh && run_container_with_logging "$image" "$container_name"'
ExecStop=/usr/bin/docker stop $container_name
ExecStopPost=/usr/bin/docker rm -f $container_name
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable enclave-container.service
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "🎯 Starting enclave application with logging..."
    
    # Run the container with logging
    run_container_with_logging "$DOCKER_IMAGE" "$CONTAINER_NAME"
    
    # Create service for automatic restart
    create_container_service "$DOCKER_IMAGE" "$CONTAINER_NAME"
    
    echo "🎉 Enclave application logging setup complete!"
    echo "📊 Logs will be available in CloudWatch under:"
    echo "   - /aws/nitro-enclave/${ENCLAVE_ID}/application"
    echo "   - /aws/nitro-enclave/${ENCLAVE_ID}/stdout" 
    echo "   - /aws/nitro-enclave/${ENCLAVE_ID}/stderr"
    
    # Keep the script running to maintain log forwarding
    wait
fi
