#!/bin/bash
set -e

# Variables from template
ENCLAVE_ID="${enclave_id}"
CPU_COUNT="${cpu_count}"
MEMORY_MIB="${memory_mib}"
EIF_PATH="${eif_path}"
DEBUG_MODE="${debug_mode}"

# Log everything
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "=== Starting Nitro Enclave Setup ==="
echo "Enclave ID: $ENCLAVE_ID"
echo "CPU Count: $CPU_COUNT"
echo "Memory: $MEMORY_MIB MiB"
echo "EIF Path: $EIF_PATH"
echo "Debug Mode: $DEBUG_MODE"

# Update system
yum update -y

# Install required packages
yum install -y \
    aws-nitro-enclaves-cli \
    aws-nitro-enclaves-cli-devel \
    docker \
    aws-cli \
    jq

# Configure Nitro Enclaves
echo "=== Configuring Nitro Enclaves ==="

# Enable and start services
systemctl enable docker
systemctl start docker
systemctl enable nitro-enclaves-allocator
systemctl start nitro-enclaves-allocator

# Configure enclave resources
echo "cpu_count: $CPU_COUNT" > /etc/nitro_enclaves/allocator.yaml
echo "memory_mib: $MEMORY_MIB" >> /etc/nitro_enclaves/allocator.yaml

# Restart allocator with new configuration
systemctl restart nitro-enclaves-allocator

# Add ec2-user to docker and ne groups
usermod -a -G docker ec2-user
usermod -a -G ne ec2-user

# Create enclave directory
mkdir -p "/opt/nitro-enclaves/$ENCLAVE_ID"
cd "/opt/nitro-enclaves/$ENCLAVE_ID"

# Download EIF if path is provided
if [ -n "$EIF_PATH" ] && [ "$EIF_PATH" != "null" ]; then
    echo "=== Downloading EIF ==="
    if [[ "$EIF_PATH" == s3://* ]]; then
        aws s3 cp "$EIF_PATH" ./enclave.eif
    elif [[ "$EIF_PATH" == http* ]]; then
        curl -L -o ./enclave.eif "$EIF_PATH"
    else
        echo "Unsupported EIF path format: $EIF_PATH"
        exit 1
    fi
    
    # Verify EIF file
    if [ ! -f ./enclave.eif ]; then
        echo "Failed to download EIF file"
        exit 1
    fi
    
    echo "EIF downloaded successfully"
    ls -la ./enclave.eif
fi

# Create enclave configuration
cat > enclave-config.json <<EOF
{
    "enclave_id": "$ENCLAVE_ID",
    "cpu_count": $CPU_COUNT,
    "memory_mib": $MEMORY_MIB,
    "eif_path": "$(pwd)/enclave.eif",
    "debug_mode": $DEBUG_MODE,
    "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

# Create systemd service for the enclave
cat > /etc/systemd/system/nitro-enclave-$ENCLAVE_ID.service <<EOF
[Unit]
Description=Nitro Enclave for $ENCLAVE_ID
After=nitro-enclaves-allocator.service
Requires=nitro-enclaves-allocator.service

[Service]
Type=forking
User=root
WorkingDirectory=/opt/nitro-enclaves/$ENCLAVE_ID
ExecStart=/usr/bin/nitro-cli run-enclave \\
    --cpu-count $CPU_COUNT \\
    --memory $MEMORY_MIB \\
    --eif-path ./enclave.eif \\
    --enclave-cid 16 \\
    $(if [ "$DEBUG_MODE" = "true" ]; then echo "--debug-mode"; fi)
ExecStop=/usr/bin/nitro-cli terminate-enclave --enclave-name $ENCLAVE_ID
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Configure CloudWatch agent for enclave logs
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<EOF
{
    "logs": {
        "logs_collected": {
            "files": {
                "collect_list": [
                    {
                        "file_path": "/var/log/nitro_enclaves/nitro_enclaves.log",
                        "log_group_name": "/aws/ec2/treza/$ENCLAVE_ID",
                        "log_stream_name": "nitro-enclaves",
                        "timezone": "UTC"
                    },
                    {
                        "file_path": "/var/log/user-data.log",
                        "log_group_name": "/aws/ec2/treza/$ENCLAVE_ID",
                        "log_stream_name": "user-data",
                        "timezone": "UTC"
                    }
                ]
            }
        }
    }
}
EOF

# Start CloudWatch agent
systemctl enable amazon-cloudwatch-agent
systemctl start amazon-cloudwatch-agent

echo "=== Nitro Enclave Setup Complete ==="

# Save status to SSM Parameter
aws ssm put-parameter \
    --name "/treza/$ENCLAVE_ID/status" \
    --value "PROVISIONED" \
    --type "String" \
    --overwrite \
    --region $(curl -s http://169.254.169.254/latest/meta-data/placement/region)

echo "=== User Data Script Completed ==="