#!/bin/bash
set -e

# Test configuration
IMAGE_NAME=${IMAGE_NAME:-treza-dev-terraform-runner}
TAG=${TAG:-latest}
TEST_ENCLAVE_ID=${TEST_ENCLAVE_ID:-test-enclave-$(date +%s)}

echo "=== Testing Terraform Runner Locally ==="
echo "Image: $IMAGE_NAME:$TAG"
echo "Test Enclave ID: $TEST_ENCLAVE_ID"

# Build the image first
cd "$(dirname "$0")/../terraform-runner"
docker build -t $IMAGE_NAME:$TAG .

# Test with plan action
echo "=== Testing with 'plan' action ==="
docker run --rm \
    -e ACTION=plan \
    -e ENCLAVE_ID=$TEST_ENCLAVE_ID \
    -e CONFIGURATION='{"instance_type":"m5.large","cpu_count":2,"memory_mib":512,"eif_path":"s3://test-bucket/test.eif"}' \
    -e TF_STATE_BUCKET=test-terraform-state-bucket \
    -e TF_STATE_DYNAMODB_TABLE=test-terraform-locks \
    -e AWS_DEFAULT_REGION=us-west-2 \
    $IMAGE_NAME:$TAG

echo "=== Local Test Complete ==="