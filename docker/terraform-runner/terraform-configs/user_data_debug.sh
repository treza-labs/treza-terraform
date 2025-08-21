#!/bin/bash
# Simple debug version of user_data to test basic functionality

echo "=== DEBUG: User data script starting at $(date) ==="
echo "=== DEBUG: Enclave ID: ${enclave_id} ==="
echo "=== DEBUG: Docker Image: ${docker_image} ==="

# Test basic AWS CLI access
echo "=== DEBUG: Testing AWS CLI ==="
REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null || echo "unknown")
echo "=== DEBUG: Region: $REGION ==="

# Test basic package installation
echo "=== DEBUG: Updating system ==="
yum update -y 2>&1 | head -10

echo "=== DEBUG: Installing Docker ==="
yum install -y docker 2>&1 | head -10

echo "=== DEBUG: Starting Docker ==="
systemctl start docker
systemctl status docker --no-pager

# Test Docker functionality
echo "=== DEBUG: Testing Docker with ${docker_image} ==="
docker pull ${docker_image}
docker run --rm ${docker_image}

echo "=== DEBUG: Creating basic log file ==="
mkdir -p /var/log/enclave
echo "$(date) - Basic log test" > /var/log/enclave/basic.log
ls -la /var/log/enclave/

echo "=== DEBUG: User data script completed at $(date) ==="

# Simple debug version of user_data to test basic functionality

echo "=== DEBUG: User data script starting at $(date) ==="
echo "=== DEBUG: Enclave ID: ${enclave_id} ==="
echo "=== DEBUG: Docker Image: ${docker_image} ==="

# Test basic AWS CLI access
echo "=== DEBUG: Testing AWS CLI ==="
REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null || echo "unknown")
echo "=== DEBUG: Region: $REGION ==="

# Test basic package installation
echo "=== DEBUG: Updating system ==="
yum update -y 2>&1 | head -10

echo "=== DEBUG: Installing Docker ==="
yum install -y docker 2>&1 | head -10

echo "=== DEBUG: Starting Docker ==="
systemctl start docker
systemctl status docker --no-pager

# Test Docker functionality
echo "=== DEBUG: Testing Docker with ${docker_image} ==="
docker pull ${docker_image}
docker run --rm ${docker_image}

echo "=== DEBUG: Creating basic log file ==="
mkdir -p /var/log/enclave
echo "$(date) - Basic log test" > /var/log/enclave/basic.log
ls -la /var/log/enclave/

echo "=== DEBUG: User data script completed at $(date) ==="
