#!/bin/bash
set -e

# Set default values
ACTION=${ACTION:-"plan"}
ENCLAVE_ID=${ENCLAVE_ID:-""}
CONFIGURATION=${CONFIGURATION:-"{}"}
WALLET_ADDRESS=${WALLET_ADDRESS:-""}
VPC_ID=${VPC_ID:-""}
SUBNET_ID=${SUBNET_ID:-""}
TF_STATE_BUCKET=${TF_STATE_BUCKET:-""}
TF_STATE_DYNAMODB_TABLE=${TF_STATE_DYNAMODB_TABLE:-""}

echo "🚀🚀🚀 NEW TERRAFORM RUNNER VERSION 2.0 STARTED 🚀🚀🚀"
echo "🔥 THIS IS THE UPDATED SCRIPT - IF YOU SEE THIS, THE UPDATE WORKED! 🔥"
echo "Action: $ACTION"
echo "Enclave ID: $ENCLAVE_ID" 
echo "Wallet Address: $WALLET_ADDRESS"
echo "VPC ID: $VPC_ID"
echo "Subnet ID: $SUBNET_ID"
echo "State Bucket: $TF_STATE_BUCKET"
echo "State DynamoDB Table: $TF_STATE_DYNAMODB_TABLE"
echo "🎯 Updated script is now active! 🎯"

# Validate required environment variables
if [ -z "$ENCLAVE_ID" ]; then
    echo "ERROR: ENCLAVE_ID environment variable is required"
    exit 1
fi

if [ -z "$TF_STATE_BUCKET" ]; then
    echo "ERROR: TF_STATE_BUCKET environment variable is required"
    exit 1
fi

if [ -z "$TF_STATE_DYNAMODB_TABLE" ]; then
    echo "ERROR: TF_STATE_DYNAMODB_TABLE environment variable is required"
    exit 1
fi

if [ -z "$WALLET_ADDRESS" ]; then
    echo "WARNING: WALLET_ADDRESS environment variable is not set"
    # Set a default for backwards compatibility
    WALLET_ADDRESS="unknown"
fi

if [ -z "$VPC_ID" ]; then
    echo "ERROR: VPC_ID environment variable is required"
    exit 1
fi

if [ -z "$SUBNET_ID" ]; then
    echo "ERROR: SUBNET_ID environment variable is required"
    exit 1
fi

# Set up workspace
WORKSPACE_DIR="/workspace/${ENCLAVE_ID}"
mkdir -p "$WORKSPACE_DIR"
cd "$WORKSPACE_DIR"

# Copy base terraform configuration
cp -r /terraform-configs/* .

# Parse configuration and create terraform.tfvars
echo "Parsing enclave configuration..."
echo "Raw configuration: $CONFIGURATION"
if ! echo "$CONFIGURATION" | jq . > config.json; then
    echo "ERROR: Invalid JSON configuration"
    exit 1
fi
echo "✓ Configuration parsed successfully"

# Extract configuration values and create terraform.tfvars
cat > terraform.tfvars <<EOF
enclave_id = "$ENCLAVE_ID"
wallet_address = "$WALLET_ADDRESS"
vpc_id = "$VPC_ID"
subnet_id = "$SUBNET_ID"
aws_region = "${AWS_DEFAULT_REGION:-us-west-2}"
environment = "${ENVIRONMENT:-dev}"
instance_type = "$(echo "$CONFIGURATION" | jq -r '.instance_type // "m5.xlarge"')"
cpu_count = $(echo "$CONFIGURATION" | jq -r '.cpu_count // 2')
memory_mib = $(echo "$CONFIGURATION" | jq -r '.memory_mib // 512')
eif_path = "$(echo "$CONFIGURATION" | jq -r '.eif_path // "https://github.com/aws/aws-nitro-enclaves-samples/releases/download/v1.0.0/hello.eif"')"
docker_image = "$(echo "$CONFIGURATION" | jq -r '.dockerImage // "nginx:alpine"')"
debug_mode = $(echo "$CONFIGURATION" | jq -r '.debug_mode // false')
key_pair_name = ""
EOF

echo "✓ Created terraform.tfvars successfully"

# Configure Terraform backend
cat > backend.tf <<EOF
terraform {
  backend "s3" {
    bucket         = "$TF_STATE_BUCKET"
    key            = "enclaves/$ENCLAVE_ID/terraform.tfstate"
    dynamodb_table = "$TF_STATE_DYNAMODB_TABLE"
    encrypt        = true
  }
}
EOF

echo "✓ Created backend.tf successfully"

echo "=== Terraform Configuration ==="
echo "Working directory: $WORKSPACE_DIR"
cat terraform.tfvars
echo ""
cat backend.tf
echo ""

# Initialize Terraform
echo "=== Initializing Terraform ==="
echo "Current directory: $(pwd)"
echo "Files in current directory:"
ls -la
echo "Terraform version:"
terraform version
echo "✓ Terraform version check completed"

# Simple test - just try to create terraform.tfvars and see if that works
echo "Creating terraform.tfvars..."
cat > terraform.tfvars <<EOF
enclave_id = "$ENCLAVE_ID"
wallet_address = "$WALLET_ADDRESS"
vpc_id = "$VPC_ID"
subnet_id = "$SUBNET_ID"
aws_region = "${AWS_DEFAULT_REGION:-us-west-2}"
environment = "${ENVIRONMENT:-dev}"
instance_type = "m5.xlarge"
cpu_count = 2
memory_mib = 512
eif_path = "https://github.com/aws/aws-nitro-enclaves-samples/releases/download/v1.0.0/hello.eif"
docker_image = "nginx:alpine"
debug_mode = false
key_pair_name = ""
EOF

echo "✓ terraform.tfvars created"
echo "Testing file exists:"
ls terraform.tfvars && echo "File exists!" || echo "File missing!"

# Initialize Terraform
echo "=== Starting Terraform Initialization ==="
echo "Running: terraform init -no-color"
INIT_OUTPUT=$(terraform init -no-color 2>&1)
INIT_EXIT_CODE=$?
echo "--- Terraform Init Output ---"
echo "$INIT_OUTPUT"
echo "--- End Output ---"
if [ $INIT_EXIT_CODE -ne 0 ]; then
    echo "ERROR: Terraform initialization failed with exit code: $INIT_EXIT_CODE"
    exit 1
fi
echo "✅ Terraform initialization completed successfully"

# Validate configuration
echo "=== Starting Terraform Validation ==="
echo "Running: terraform validate -no-color"
VALIDATE_OUTPUT=$(terraform validate -no-color 2>&1)
VALIDATE_EXIT_CODE=$?
echo "--- Terraform Validate Output ---"
echo "$VALIDATE_OUTPUT"
echo "--- End Output ---"
if [ $VALIDATE_EXIT_CODE -ne 0 ]; then
    echo "ERROR: Terraform validation failed with exit code: $VALIDATE_EXIT_CODE"
    exit 1
fi
echo "✅ Terraform validation passed successfully"

# Execute the requested action
case "$ACTION" in
    "plan")
        echo "=== Running Terraform Plan ==="
        terraform plan -no-color -out=tfplan
        ;;
    "deploy")
        echo "=== Running Terraform Plan ==="
        PLAN_OUTPUT=$(terraform plan -no-color -out=tfplan 2>&1)
        PLAN_EXIT_CODE=$?
        echo "--- Terraform Plan Output ---"
        echo "$PLAN_OUTPUT"
        echo "--- End Output ---"
        if [ $PLAN_EXIT_CODE -ne 0 ]; then
            echo "ERROR: Terraform plan failed with exit code: $PLAN_EXIT_CODE"
            exit 1
        fi
        echo "✅ Terraform plan completed successfully"
        
        echo "=== Running Terraform Apply ==="
        APPLY_OUTPUT=$(terraform apply -no-color -auto-approve tfplan 2>&1)
        APPLY_EXIT_CODE=$?
        echo "--- Terraform Apply Output ---"
        echo "$APPLY_OUTPUT"
        echo "--- End Output ---"
        if [ $APPLY_EXIT_CODE -ne 0 ]; then
            echo "ERROR: Terraform apply failed with exit code: $APPLY_EXIT_CODE"
            exit 1
        fi
        echo "✅ Terraform apply completed successfully"
        ;;
    "destroy")
        echo "=== Running Terraform Destroy ==="
        DESTROY_OUTPUT=$(terraform destroy -no-color -auto-approve 2>&1)
        DESTROY_EXIT_CODE=$?
        echo "--- Terraform Destroy Output ---"
        echo "$DESTROY_OUTPUT"
        echo "--- End Output ---"
        if [ $DESTROY_EXIT_CODE -ne 0 ]; then
            echo "ERROR: Terraform destroy failed with exit code: $DESTROY_EXIT_CODE"
            exit 1
        fi
        echo "✅ Terraform destroy completed successfully"
        ;;
    *)
        echo "ERROR: Unknown action '$ACTION'. Supported actions: plan, deploy, destroy"
        exit 1
        ;;
esac

echo "=== 🎉 Terraform Runner Completed Successfully ==="