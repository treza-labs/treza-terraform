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

# Use full terraform configuration
echo "🚀 PRODUCTION MODE: Using full terraform configuration for enclave deployment"
if [ -f main-simple.tf ]; then
    rm main-simple.tf
    echo "✓ Removed simple test configuration"
fi
echo "✓ Using full terraform configuration"

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
instance_type = "$(echo "$CONFIGURATION" | jq -r '.instanceType // "m5.xlarge"')"
cpu_count = $(echo "$CONFIGURATION" | jq -r '.cpuCount // 2')
memory_mib = $(echo "$CONFIGURATION" | jq -r '.memoryMiB // 1024')
eif_path = "$(echo "$CONFIGURATION" | jq -r '.eif_path // "https://github.com/aws/aws-nitro-enclaves-samples/releases/download/v1.0.0/hello.eif"')"
docker_image="$(echo "$CONFIGURATION" | jq -r '.dockerImage // "hello-world"')"
debug_mode = $(echo "$CONFIGURATION" | jq -r '.enableDebug // false')
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

# Create symlink to modules for Terraform
ln -sf /modules modules

# Initialize Terraform
echo "=== Initializing Terraform ==="
echo "Current directory: $(pwd)"
echo "Files in current directory:"
ls -la
echo "Terraform version:"
terraform version
echo "✓ Terraform version check completed"

# Simple test - just try to create terraform.tfvars and see if that works
# Verify terraform.tfvars was created correctly
echo "Verifying terraform.tfvars..."
if [ ! -f terraform.tfvars ] || [ ! -s terraform.tfvars ]; then
    echo "⚠️  terraform.tfvars is missing or empty, creating backup version..."
    cat > terraform.tfvars <<EOF
enclave_id = "$ENCLAVE_ID"
wallet_address = "$WALLET_ADDRESS"
vpc_id = "$VPC_ID"
subnet_id = "$SUBNET_ID"
aws_region = "${AWS_DEFAULT_REGION:-us-west-2}"
environment = "${ENVIRONMENT:-dev}"
instance_type = "$(echo "$CONFIGURATION" | jq -r '.instanceType // "m5.xlarge"')"
cpu_count = $(echo "$CONFIGURATION" | jq -r '.cpuCount // 2')
memory_mib = $(echo "$CONFIGURATION" | jq -r '.memoryMiB // 1024')
eif_path = "$(echo "$CONFIGURATION" | jq -r '.eif_path // "https://github.com/aws/aws-nitro-enclaves-samples/releases/download/v1.0.0/hello.eif"')"
docker_image="$(echo "$CONFIGURATION" | jq -r '.dockerImage // "hello-world"')"
debug_mode = $(echo "$CONFIGURATION" | jq -r '.enableDebug // false')
key_pair_name = ""
EOF
    echo "✓ Backup terraform.tfvars created"
else
    echo "✓ terraform.tfvars exists and is valid"
fi

echo "Current terraform.tfvars content:"
cat terraform.tfvars
echo ""
echo "✓ terraform.tfvars verified"

# Initialize Terraform
echo "=== Starting Terraform Initialization ==="
echo "Testing AWS connectivity first..."
echo "AWS CLI version: $(aws --version)"
echo "AWS identity: $(aws sts get-caller-identity 2>&1 || echo 'FAILED')"
echo "S3 bucket test: $(aws s3 ls s3://$TF_STATE_BUCKET/ --region us-west-2 2>&1 | head -3 || echo 'FAILED')"
echo "DynamoDB table test: $(aws dynamodb describe-table --table-name $TF_STATE_DYNAMODB_TABLE --region us-west-2 --query 'Table.TableStatus' 2>&1 || echo 'FAILED')"

echo "🌐 TESTING TERRAFORM REGISTRY CONNECTIVITY..."
echo "Terraform registry test: $(curl -s --connect-timeout 10 --max-time 30 https://registry.terraform.io/.well-known/terraform.json | head -100 || echo 'FAILED')"
echo "GitHub releases test: $(curl -s --connect-timeout 10 --max-time 30 https://releases.hashicorp.com/terraform/ | head -100 || echo 'FAILED')"
echo "DNS resolution test: $(nslookup registry.terraform.io || echo 'FAILED')"

echo "Running: terraform init -no-color"
echo "🔍 REAL-TIME TERRAFORM INIT OUTPUT:"

# Run terraform init with real-time output AND capture to log
terraform init -no-color 2>&1 | tee /tmp/init.log &
INIT_PID=$!
echo "Terraform init started with PID: $INIT_PID"

# Wait for terraform init with progress updates (10 minutes total)
for i in {1..120}; do
    if kill -0 $INIT_PID 2>/dev/null; then
        echo "⏳ Terraform init still running... ($i/120) - $(date)"
        echo "📊 Process status: $(ps aux | grep $INIT_PID | grep -v grep || echo 'Process not found')"
        sleep 5
    else
        echo "✅ Terraform init process completed at iteration $i"
        break
    fi
done

wait $INIT_PID
INIT_EXIT_CODE=$?

echo "--- Final Terraform Init Log ---"
cat /tmp/init.log
echo "--- End Log ---"

if [ $INIT_EXIT_CODE -ne 0 ]; then
    echo "ERROR: Terraform initialization failed with exit code: $INIT_EXIT_CODE"
    echo "--- Debug Info ---"
    echo "Working directory contents:"
    ls -la
    echo "Network connectivity test:"
    ping -c 3 s3.us-west-2.amazonaws.com || echo "Cannot reach S3"
    exit 1
fi
echo "✅ Terraform initialization completed successfully"

# Validate configuration
echo "=== Starting Terraform Validation ==="
echo "Running: terraform validate -no-color"
echo "🔍 REAL-TIME TERRAFORM VALIDATE OUTPUT:"

# Run terraform validate with real-time output AND capture to log
terraform validate -no-color 2>&1 | tee /tmp/validate.log &
VALIDATE_PID=$!
echo "Terraform validate started with PID: $VALIDATE_PID"

# Wait for terraform validate with progress updates (5 minutes total)
for i in {1..60}; do
    if kill -0 $VALIDATE_PID 2>/dev/null; then
        echo "⏳ Terraform validate still running... ($i/60) - $(date)"
        echo "📊 Process status: $(ps aux | grep $VALIDATE_PID | grep -v grep || echo 'Process not found')"
        sleep 5
    else
        echo "✅ Terraform validate process completed at iteration $i"
        break
    fi
done

wait $VALIDATE_PID
VALIDATE_EXIT_CODE=$?

echo "--- Final Terraform Validate Log ---"
cat /tmp/validate.log
echo "--- End Validate Log ---"

if [ $VALIDATE_EXIT_CODE -ne 0 ]; then
    echo "ERROR: Terraform validation failed with exit code: $VALIDATE_EXIT_CODE"
    echo "--- Debug Info ---"
    echo "Working directory contents:"
    ls -la
    echo "Terraform files:"
    find . -name "*.tf" -exec echo "=== {} ===" \; -exec cat {} \;
    exit 1
fi
echo "✅ Terraform validation passed successfully"

# Execute the requested action
case "$ACTION" in
    "plan")
        echo "=== Running Terraform Plan ==="
        echo "🔍 REAL-TIME TERRAFORM PLAN OUTPUT:"
        
        # Run terraform plan with real-time output AND capture to log
        terraform plan -no-color 2>&1 | tee /tmp/plan.log &
        PLAN_PID=$!
        echo "Terraform plan started with PID: $PLAN_PID"
        
        # Wait for terraform plan with progress updates (10 minutes total)
        for i in {1..120}; do
            if kill -0 $PLAN_PID 2>/dev/null; then
                echo "⏳ Terraform plan still running... ($i/120) - $(date)"
                echo "📊 Process status: $(ps aux | grep $PLAN_PID | grep -v grep || echo 'Process not found')"
                sleep 5
            else
                echo "✅ Terraform plan process completed at iteration $i"
                break
            fi
        done
        
        wait $PLAN_PID
        PLAN_EXIT_CODE=$?
        
        echo "--- Final Terraform Plan Log ---"
        cat /tmp/plan.log
        echo "--- End Plan Log ---"
        
        if [ $PLAN_EXIT_CODE -ne 0 ]; then
            echo "ERROR: Terraform plan failed with exit code: $PLAN_EXIT_CODE"
            echo "--- Debug Info ---"
            echo "Working directory contents:"
            ls -la
            exit 1
        fi
        echo "✅ Terraform plan completed successfully"
        terraform plan -no-color -out=tfplan
        ;;
    "deploy")
        echo "=== Running Terraform Plan ==="
        echo "🔍 REAL-TIME TERRAFORM PLAN OUTPUT:"
        
        # Run terraform plan with real-time output AND capture to log
        terraform plan -no-color -out=tfplan 2>&1 | tee /tmp/plan.log &
        PLAN_PID=$!
        echo "Terraform plan started with PID: $PLAN_PID"
        
        # Wait for terraform plan with progress updates (10 minutes total)
        for i in {1..120}; do
            if kill -0 $PLAN_PID 2>/dev/null; then
                echo "⏳ Terraform plan still running... ($i/120) - $(date)"
                echo "📊 Process status: $(ps aux | grep $PLAN_PID | grep -v grep || echo 'Process not found')"
                sleep 5
            else
                echo "✅ Terraform plan process completed at iteration $i"
                break
            fi
        done
        
        wait $PLAN_PID
        PLAN_EXIT_CODE=$?
        
        echo "--- Final Terraform Plan Log ---"
        cat /tmp/plan.log
        echo "--- End Plan Log ---"
        
        if [ $PLAN_EXIT_CODE -ne 0 ]; then
            echo "ERROR: Terraform plan failed with exit code: $PLAN_EXIT_CODE"
            echo "--- Debug Info ---"
            echo "Working directory contents:"
            ls -la
            exit 1
        fi
        echo "✅ Terraform plan completed successfully"
        
        echo "=== Running Terraform Apply ==="
        # Add timeout and enhanced debugging for Terraform apply
        echo "🔍 Starting Terraform apply with enhanced monitoring..."
        echo "Terraform version: $(terraform version | head -1)"
        echo "Current time: $(date)"
        echo "Available disk space: $(df -h . | tail -1)"
        echo "Memory usage: $(free -h || echo 'N/A')"
        
        # Run apply with real-time output and timeout
        timeout 1200 bash -c '
            terraform apply -no-color -auto-approve tfplan 2>&1 | while IFS= read -r line; do
                echo "$(date "+%H:%M:%S") [APPLY] $line"
                if echo "$line" | grep -q "Error\|Failed\|Timeout"; then
                    echo "🚨 ERROR DETECTED: $line"
                fi
            done
            exit ${PIPESTATUS[0]}
        '
        APPLY_EXIT_CODE=$?
        echo "--- Terraform Apply Complete ---"
        echo "Final time: $(date)"
        if [ $APPLY_EXIT_CODE -eq 124 ]; then
            echo "❌ Terraform apply timed out after 1200 seconds (20 minutes)"
        elif [ $APPLY_EXIT_CODE -eq 0 ]; then
            echo "✅ Terraform apply completed successfully"
        else
            echo "❌ Terraform apply failed with exit code: $APPLY_EXIT_CODE"
        fi
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
exit 0
        if [ $APPLY_EXIT_CODE -eq 124 ]; then
            echo "❌ Terraform apply timed out after 1200 seconds (20 minutes)"
        elif [ $APPLY_EXIT_CODE -eq 0 ]; then
            echo "✅ Terraform apply completed successfully"
        else
            echo "❌ Terraform apply failed with exit code: $APPLY_EXIT_CODE"
        fi
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
echo "=== 🎉 Terraform Runner Completed Successfully ==="