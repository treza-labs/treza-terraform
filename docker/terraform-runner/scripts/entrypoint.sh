#!/bin/bash
set -e

# Set default values
ACTION=${ACTION:-"plan"}
ENCLAVE_ID=${ENCLAVE_ID:-""}
CONFIGURATION=${CONFIGURATION:-"{}"}
TF_STATE_BUCKET=${TF_STATE_BUCKET:-""}
TF_STATE_DYNAMODB_TABLE=${TF_STATE_DYNAMODB_TABLE:-""}

echo "=== Terraform Runner Started ==="
echo "Action: $ACTION"
echo "Enclave ID: $ENCLAVE_ID"
echo "State Bucket: $TF_STATE_BUCKET"
echo "State DynamoDB Table: $TF_STATE_DYNAMODB_TABLE"

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

# Set up workspace
WORKSPACE_DIR="/workspace/${ENCLAVE_ID}"
mkdir -p "$WORKSPACE_DIR"
cd "$WORKSPACE_DIR"

# Copy base terraform configuration
cp -r /terraform-configs/* .

# Parse configuration and create terraform.tfvars
echo "Parsing enclave configuration..."
echo "$CONFIGURATION" | jq . > config.json

# Extract configuration values and create terraform.tfvars
cat > terraform.tfvars <<EOF
enclave_id = "$ENCLAVE_ID"
instance_type = $(echo "$CONFIGURATION" | jq -r '.instance_type // "m5.large"')
cpu_count = $(echo "$CONFIGURATION" | jq -r '.cpu_count // 2')
memory_mib = $(echo "$CONFIGURATION" | jq -r '.memory_mib // 512')
eif_path = "$(echo "$CONFIGURATION" | jq -r '.eif_path // "https://github.com/aws/aws-nitro-enclaves-samples/releases/download/v1.0.0/hello.eif"')"
debug_mode = $(echo "$CONFIGURATION" | jq -r '.debug_mode // false')
EOF

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

echo "=== Terraform Configuration ==="
echo "Working directory: $WORKSPACE_DIR"
cat terraform.tfvars
echo ""
cat backend.tf
echo ""

# Initialize Terraform
echo "=== Initializing Terraform ==="
terraform init -no-color

# Validate configuration
echo "=== Validating Terraform Configuration ==="
terraform validate -no-color

# Execute the requested action
case "$ACTION" in
    "plan")
        echo "=== Running Terraform Plan ==="
        terraform plan -no-color -out=tfplan
        ;;
    "deploy")
        echo "=== Running Terraform Apply ==="
        terraform plan -no-color -out=tfplan
        terraform apply -no-color -auto-approve tfplan
        echo "=== Terraform Apply Completed Successfully ==="
        ;;
    "destroy")
        echo "=== Running Terraform Destroy ==="
        terraform destroy -no-color -auto-approve
        echo "=== Terraform Destroy Completed Successfully ==="
        ;;
    *)
        echo "ERROR: Unknown action '$ACTION'. Supported actions: plan, deploy, destroy"
        exit 1
        ;;
esac

echo "=== Terraform Runner Completed ==="