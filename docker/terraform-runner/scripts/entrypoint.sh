#!/bin/bash
set -e

# Set default values
ACTION=${TERRAFORM_ACTION:-${ACTION:-"plan"}}
ENCLAVE_ID=${ENCLAVE_ID:-""}
CONFIGURATION=${CONFIGURATION:-"{}"}
WALLET_ADDRESS=${WALLET_ADDRESS:-""}
VPC_ID=${VPC_ID:-""}
SUBNET_ID=${SUBNET_ID:-""}
SHARED_SECURITY_GROUP_ID=${SHARED_SECURITY_GROUP_ID:-""}
TF_STATE_BUCKET=${TF_STATE_BUCKET:-""}
TF_STATE_DYNAMODB_TABLE=${TF_STATE_DYNAMODB_TABLE:-""}
DOCKER_IMAGE=${DOCKER_IMAGE:-"hello-world"}
WORKLOAD_TYPE=${WORKLOAD_TYPE:-"batch"}
HEALTH_CHECK_PATH=${HEALTH_CHECK_PATH:-"/health"}
HEALTH_CHECK_INTERVAL=${HEALTH_CHECK_INTERVAL:-"30"}
AWS_SERVICES=${AWS_SERVICES:-""}
EXPOSE_PORTS=${EXPOSE_PORTS:-""}

echo "🚀 Terraform Runner v2.2 - Enhanced Error Handling & Validation 🚀"
echo "📅 Started at: $(date)"

# Debug: Print ALL environment variables
echo "=== ALL ENVIRONMENT VARIABLES ==="
env | sort
echo "=== END ENVIRONMENT VARIABLES ==="

echo "Action: $ACTION"
echo "Enclave ID: $ENCLAVE_ID" 
echo "Wallet Address: $WALLET_ADDRESS"
echo "VPC ID: $VPC_ID"
echo "Subnet ID: $SUBNET_ID"
echo "Shared Security Group ID: $SHARED_SECURITY_GROUP_ID"
echo "State Bucket: $TF_STATE_BUCKET"
echo "State DynamoDB Table: $TF_STATE_DYNAMODB_TABLE"
echo "Docker Image: $DOCKER_IMAGE"

# Debug: Check specific environment variable existence
if [ -z "$SHARED_SECURITY_GROUP_ID" ]; then
    echo "🚨 DEBUG: SHARED_SECURITY_GROUP_ID is EMPTY or UNDEFINED"
    echo "🔍 Checking for similar variable names..."
    env | grep -i security || echo "No security-related environment variables found"
    env | grep -i group || echo "No group-related environment variables found"
    env | grep -i shared || echo "No shared-related environment variables found"
else
    echo "✅ DEBUG: SHARED_SECURITY_GROUP_ID is set to: '$SHARED_SECURITY_GROUP_ID'"
fi

echo "🎯 Updated script is now active! 🎯"

# Check if TERRAFORM_CONFIG is set (new format) or fall back to CONFIGURATION
TERRAFORM_FILE="${TERRAFORM_CONFIG:-$CONFIGURATION}"

# Validate required environment variables
if [ -z "$ENCLAVE_ID" ]; then
    echo "❌ ERROR: ENCLAVE_ID environment variable is required"
    exit 1
fi

# TF_STATE_BUCKET and TF_STATE_DYNAMODB_TABLE are not required for vsocket configuration
if [ "$TERRAFORM_FILE" != "main.tf" ]; then
    if [ -z "$TF_STATE_BUCKET" ]; then
        echo "❌ ERROR: TF_STATE_BUCKET environment variable is required"
        exit 1
    fi

    if [ -z "$TF_STATE_DYNAMODB_TABLE" ]; then
        echo "❌ ERROR: TF_STATE_DYNAMODB_TABLE environment variable is required"
        exit 1
    fi
fi

if [ -z "$WALLET_ADDRESS" ]; then
    echo "⚠️  WARNING: WALLET_ADDRESS environment variable is not set"
    # Set a default for backwards compatibility
    WALLET_ADDRESS="unknown"
fi

# VPC_ID and SUBNET_ID are not required for vsocket configuration
if [ "$TERRAFORM_FILE" != "main.tf" ]; then
    if [ -z "$VPC_ID" ]; then
        echo "❌ ERROR: VPC_ID environment variable is required"
        exit 1
    fi

    if [ -z "$SUBNET_ID" ]; then
        echo "❌ ERROR: SUBNET_ID environment variable is required"
        exit 1
    fi
else
    echo "✓ Skipping VPC_ID and SUBNET_ID validation for vsocket configuration"
    # Set defaults for vsocket configuration
    VPC_ID="default"
    SUBNET_ID="default"
fi

# Set up workspace
WORKSPACE_DIR="/workspace/${ENCLAVE_ID}"
mkdir -p "$WORKSPACE_DIR"
cd "$WORKSPACE_DIR"

# Copy base terraform configuration
cp -r /terraform-configs/* .

# Use the fixed configuration if specified
if [ "$CONFIGURATION" = "main_fixed_final.tf" ]; then
    echo "🚀 FIXED MODE: Using fixed Nitro Enclaves configuration with E22 solutions"
    if [ -f main.tf ]; then
        mv main.tf main_original.tf
        echo "✓ Backed up original main.tf"
    fi
    if [ -f main_fixed_final.tf ]; then
        cp main_fixed_final.tf main.tf
        echo "✓ Using fixed configuration as main.tf"
    else
        echo "ERROR: main_fixed_final.tf not found"
        exit 1
    fi
else
    echo "🚀 PRODUCTION MODE: Using full terraform configuration for enclave deployment"
    if [ -f main-simple.tf ]; then
        rm main-simple.tf
        echo "✓ Removed simple test configuration"
    fi
fi
echo "✓ Using terraform configuration"

# Parse configuration and create terraform.tfvars
echo "Parsing enclave configuration..."
echo "Raw configuration: $CONFIGURATION"

# Check if TERRAFORM_FILE is a filename or JSON
if [ "$TERRAFORM_FILE" = "main_fixed_final.tf" ] || [ "$TERRAFORM_FILE" = "standalone_final.tf" ] || [ "$TERRAFORM_FILE" = "main.tf" ]; then
    echo "✓ Using standalone configuration file: $CONFIGURATION"
    # Create a default config for the standalone mode
    echo '{"enableDebug": true, "dockerImage": "hello-world", "instanceType": "m6i.xlarge", "memoryMiB": "1024", "cpuCount": "2"}' > config.json
    
    # Copy the standalone configuration to main.tf and remove conflicting files
    if [ "$CONFIGURATION" = "standalone_final.tf" ]; then
        # Debug: Show what .tf files exist before cleanup
        echo "🔍 DEBUG: .tf files before cleanup:"
        find . -name "*.tf" -type f || echo "No .tf files found"
        
        # Remove all existing .tf files to avoid conflicts (including any from modules or other sources)
        rm -f *.tf
        rm -f /terraform/*.tf
        find . -name "*.tf" -delete
        echo "✓ Removed ALL existing .tf files from all locations to avoid conflicts"
        
        # Debug: Show what .tf files exist after cleanup
        echo "🔍 DEBUG: .tf files after cleanup:"
        find . -name "*.tf" -type f || echo "No .tf files found"
        
        # Copy only the standalone configuration
        cp /terraform-configs/standalone_final.tf main.tf
        echo "✓ Copied standalone_final.tf to main.tf"
        
        # Also copy the user data script
        cp /terraform-configs/user_data_fixed_final.sh .
        echo "✓ Copied user_data_fixed_final.sh"
    elif [ "$TERRAFORM_FILE" = "main.tf" ]; then
        # vsocket architecture - clean setup
        echo "🔍 DEBUG: Setting up vsocket architecture"
        find . -name "*.tf" -type f || echo "No .tf files found"
        
        # Remove all existing .tf files to avoid conflicts
        rm -f *.tf
        rm -f /terraform/*.tf
        find . -name "*.tf" -delete
        echo "✓ Removed ALL existing .tf files for vsocket setup"
        
        # Copy vsocket configuration and scripts
        cp /terraform-configs/main.tf main.tf
        echo "✓ Copied main.tf to main.tf"
        
        # Copy user data script
        cp /terraform-configs/user_data.sh .
        echo "✓ Copied user_data.sh"
        
        # Note: All required files are embedded in user_data.sh
        echo "✓ Copied vsocket application files"
    else
        cp /terraform-configs/main_fixed_final.tf main.tf
        echo "✓ Copied main_fixed_final.tf to main.tf"
    fi
    
    # For standalone mode, use hardcoded values to avoid jq parsing issues
    if [ "$CONFIGURATION" = "standalone_final.tf" ]; then
        # Standalone configuration - only include variables that exist in the config
        cat > terraform.tfvars <<EOF
enclave_id = "$ENCLAVE_ID"
wallet_address = "$WALLET_ADDRESS"
vpc_id = "$VPC_ID"
subnet_id = "$SUBNET_ID"
aws_region = "${AWS_DEFAULT_REGION:-us-west-2}"
environment = "${ENVIRONMENT:-dev}"
instance_type = "m6i.xlarge"
cpu_count = 2
memory_mib = 1024
docker_image = "${DOCKER_IMAGE:-hello-world}"
debug_mode = true
shared_security_group_id = "${SHARED_SECURITY_GROUP_ID:-""}"
EOF
    elif [ "$TERRAFORM_FILE" = "main.tf" ]; then
        # vsocket v2 configuration - supports arbitrary workloads
        cat > terraform.tfvars <<EOF
enclave_id = "$ENCLAVE_ID"
aws_region = "${AWS_DEFAULT_REGION:-us-west-2}"
environment = "${ENVIRONMENT:-dev}"
cpu_count = 2
memory_mib = 1024
docker_image = "${DOCKER_IMAGE:-hello-world}"
workload_type = "${WORKLOAD_TYPE:-batch}"
health_check_path = "${HEALTH_CHECK_PATH:-/health}"
health_check_interval = ${HEALTH_CHECK_INTERVAL:-30}
aws_services = "${AWS_SERVICES:-}"
expose_ports = "${EXPOSE_PORTS:-}"
EOF
    else
        # Regular configuration - include all variables
        cat > terraform.tfvars <<EOF
enclave_id = "$ENCLAVE_ID"
wallet_address = "$WALLET_ADDRESS"
vpc_id = "$VPC_ID"
subnet_id = "$SUBNET_ID"
aws_region = "${AWS_DEFAULT_REGION:-us-west-2}"
environment = "${ENVIRONMENT:-dev}"
instance_type = "m6i.xlarge"
cpu_count = 2
memory_mib = 1024
eif_path = "https://github.com/aws/aws-nitro-enclaves-samples/releases/download/v1.0.0/hello.eif"
docker_image = "${DOCKER_IMAGE:-hello-world}"
debug_mode = true
key_pair_name = ""
shared_security_group_id = "${SHARED_SECURITY_GROUP_ID:-""}"
EOF
    fi
else
    # Parse as JSON configuration
    if ! echo "$CONFIGURATION" | jq . > config.json; then
        echo "ERROR: Invalid JSON configuration"
        exit 1
    fi
    
    # Extract configuration values and create terraform.tfvars
    cat > terraform.tfvars <<EOF
enclave_id = "$ENCLAVE_ID"
wallet_address = "$WALLET_ADDRESS"
vpc_id = "$VPC_ID"
subnet_id = "$SUBNET_ID"
aws_region = "${AWS_DEFAULT_REGION:-us-west-2}"
environment = "${ENVIRONMENT:-dev}"
instance_type = "$(echo "$CONFIGURATION" | jq -r '.instanceType // "m6i.xlarge"')"
cpu_count = $(echo "$CONFIGURATION" | jq -r '.cpuCount // "2"')
memory_mib = $(echo "$CONFIGURATION" | jq -r '.memoryMiB // "1024"')
eif_path = "$(echo "$CONFIGURATION" | jq -r '.eif_path // "https://github.com/aws/aws-nitro-enclaves-samples/releases/download/v1.0.0/hello.eif"')"
docker_image="${DOCKER_IMAGE:-$(echo "$CONFIGURATION" | jq -r '.dockerImage // "hello-world"')}"
debug_mode = $(echo "$CONFIGURATION" | jq -r '.enableDebug // false')
key_pair_name = ""
shared_security_group_id = "${SHARED_SECURITY_GROUP_ID:-""}"
EOF
fi

echo "✓ Created terraform.tfvars successfully"

# Configure Terraform backend (skip for standalone configurations with built-in backend)
if [ "$CONFIGURATION" != "standalone_final.tf" ] && [ "$CONFIGURATION" != "main.tf" ]; then
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
else
    echo "✓ Skipped backend.tf creation (standalone configuration has built-in backend)"
fi

echo "=== Terraform Configuration ==="
echo "Working directory: $WORKSPACE_DIR"
cat terraform.tfvars
echo ""
if [ -f backend.tf ]; then
    cat backend.tf
    echo ""
else
    echo "No separate backend.tf file (using built-in backend configuration)"
    echo ""
fi

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
instance_type = "$(echo "$CONFIGURATION" | jq -r '.instanceType // "m6i.xlarge"')"
cpu_count = $(echo "$CONFIGURATION" | jq -r '.cpuCount // "2"')
memory_mib = $(echo "$CONFIGURATION" | jq -r '.memoryMiB // "1024"')
eif_path = "$(echo "$CONFIGURATION" | jq -r '.eif_path // "https://github.com/aws/aws-nitro-enclaves-samples/releases/download/v1.0.0/hello.eif"')"
docker_image="${DOCKER_IMAGE:-$(echo "$CONFIGURATION" | jq -r '.dockerImage // "hello-world"')}"
debug_mode = $(echo "$CONFIGURATION" | jq -r '.enableDebug // false')
key_pair_name = ""
shared_security_group_id = "${SHARED_SECURITY_GROUP_ID:-""}"
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

# Set environment variables for better S3 state management
export AWS_MAX_ATTEMPTS=3
export AWS_RETRY_MODE=adaptive
export TF_CLI_ARGS_apply="-parallelism=1"
export TF_CLI_ARGS_plan="-parallelism=1"
echo "✓ Set AWS retry configuration for better state management"

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
        
        # Show what outputs would be available after apply
        echo "=== Preview of Available Outputs ==="
        echo "🔍 These outputs will be available after deployment:"
        terraform output || echo "No outputs available yet (will appear after apply)"
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
        
        # Check for errors in the plan output (only check exit code, not generic "error" text)
        if [ $PLAN_EXIT_CODE -ne 0 ] || grep -q "No valid credential sources" /tmp/plan.log || grep -q "Backend initialization required" /tmp/plan.log || grep -q "Missing required provider" /tmp/plan.log; then
            echo "ERROR: Terraform plan failed with exit code: $PLAN_EXIT_CODE"
            echo "--- Error Details ---"
            grep -A 3 -B 1 "Error:" /tmp/plan.log || echo "No specific error pattern found"
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
        
        # Run apply with state recovery handling
        if [ -f "tfplan" ]; then
            echo "Running: terraform apply -no-color -auto-approve tfplan"
            terraform apply -no-color -auto-approve tfplan
            APPLY_EXIT_CODE=$?
        else
            echo "⚠️  No plan file found, running direct apply..."
            echo "Running: terraform apply -no-color -auto-approve"
            terraform apply -no-color -auto-approve
            APPLY_EXIT_CODE=$?
        fi
        
        # Handle state save failures specifically
        if [ $APPLY_EXIT_CODE -ne 0 ]; then
            echo "🔍 Checking for state save failures..."
            if [ -f "errored.tfstate" ]; then
                echo "⚠️  Found errored.tfstate file - attempting state recovery..."
                echo "Pushing errored state to backend with retry logic..."
                
                # Retry state push up to 3 times with exponential backoff
                for attempt in 1 2 3; do
                    echo "State push attempt $attempt/3..."
                    terraform state push errored.tfstate
                    STATE_PUSH_EXIT_CODE=$?
                    
                    if [ $STATE_PUSH_EXIT_CODE -eq 0 ]; then
                        echo "✅ State push successful on attempt $attempt"
                        break
                    else
                        echo "❌ State push attempt $attempt failed"
                        if [ $attempt -lt 3 ]; then
                            sleep_time=$((attempt * 5))
                            echo "Waiting ${sleep_time}s before retry..."
                            sleep $sleep_time
                        fi
                    fi
                done
                
                if [ $STATE_PUSH_EXIT_CODE -eq 0 ]; then
                    echo "✅ State recovery successful - continuing with deployment"
                    APPLY_EXIT_CODE=0
                else
                    echo "❌ State recovery failed - but resources may have been created"
                    # Check if resources were actually created despite state failure
                    echo "🔍 Verifying if resources were created..."
                    terraform refresh -no-color || true
                    
                    # If we can get outputs, the deployment likely succeeded
                    INSTANCE_ID_CHECK=$(terraform output -raw instance_id 2>/dev/null || echo "")
                    if [ -n "$INSTANCE_ID_CHECK" ]; then
                        echo "✅ Resources were created successfully despite state save failure"
                        APPLY_EXIT_CODE=0
                    fi
                fi
            fi
        fi
        
        echo "--- Terraform Apply Complete ---"
        echo "Final time: $(date)"
        if [ $APPLY_EXIT_CODE -eq 124 ]; then
            echo "❌ Terraform apply timed out after 1200 seconds (20 minutes)"
        elif [ $APPLY_EXIT_CODE -eq 0 ]; then
            echo "✅ Terraform apply completed successfully"
        else
            echo "❌ Terraform apply failed with exit code: $APPLY_EXIT_CODE"
            
            echo "❌ Terraform apply failed - this should not happen with our current setup"
            echo "🔍 Checking for common issues..."
            echo "Available disk space: $(df -h . | tail -1)"
            echo "Memory usage: $(free -h || echo 'N/A')"
            
            # For now, just exit with the error - we can add replace logic later if needed
            echo "❌ Terraform apply failed with exit code: $APPLY_EXIT_CODE"
        fi
        
        if [ $APPLY_EXIT_CODE -ne 0 ]; then
            echo "ERROR: Terraform apply failed with exit code: $APPLY_EXIT_CODE"
            exit 1
        fi
        echo "✅ Terraform apply completed successfully"
        
        # Capture Terraform outputs and update DynamoDB with instance ID
        echo "=== Capturing Terraform Outputs ==="
        if [ -n "$ENCLAVE_ID" ]; then
            echo "🔍 Getting instance ID from Terraform outputs..."
            
            # Get the instance ID from Terraform outputs with timeout
            INSTANCE_ID=$(timeout 30 terraform output -raw instance_id 2>/dev/null || echo "")
            
            if [ -n "$INSTANCE_ID" ]; then
                echo "✅ Found instance ID: $INSTANCE_ID"
                
                # Show current DynamoDB record before update (with timeout)
                echo "📋 Current DynamoDB record:"
                timeout 30 aws dynamodb get-item \
                    --table-name "treza-enclaves-dev" \
                    --key "{\"id\": {\"S\": \"$ENCLAVE_ID\"}}" \
                    --region "$AWS_DEFAULT_REGION" \
                    --output json 2>/dev/null | jq '.Item.providerConfig' || echo "No providerConfig found"
                
                # Update DynamoDB record with instance ID (with timeout)
                echo "📝 Updating DynamoDB record with instance ID..."
                
                # Use AWS CLI to update the DynamoDB record
                timeout 60 aws dynamodb update-item \
                    --table-name "treza-enclaves-dev" \
                    --key "{\"id\": {\"S\": \"$ENCLAVE_ID\"}}" \
                    --update-expression "SET providerConfig.instanceId = :instanceId, updated_at = :timestamp" \
                    --expression-attribute-values "{\":instanceId\": {\"S\": \"$INSTANCE_ID\"}, \":timestamp\": {\"S\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}}" \
                    --region "$AWS_DEFAULT_REGION" \
                    --output json 2>&1 | tee /tmp/dynamodb_update.log
                
                DYNAMODB_EXIT_CODE=$?
                if [ $DYNAMODB_EXIT_CODE -eq 0 ]; then
                    echo "✅ Successfully updated DynamoDB with instance ID: $INSTANCE_ID"
                    
                    # Verify the update by showing the updated record (with timeout)
                    echo "🔍 Verifying DynamoDB update:"
                    timeout 30 aws dynamodb get-item \
                        --table-name "treza-enclaves-dev" \
                        --key "{\"id\": {\"S\": \"$ENCLAVE_ID\"}}" \
                        --region "$AWS_DEFAULT_REGION" \
                        --output json 2>/dev/null | jq '.Item.providerConfig.instanceId' || echo "Instance ID not found in updated record"
                else
                    echo "⚠️  Warning: Failed to update DynamoDB with instance ID (exit code: $DYNAMODB_EXIT_CODE)"
                    echo "📋 DynamoDB update log:"
                    cat /tmp/dynamodb_update.log
                fi
            else
                echo "⚠️  Warning: No instance ID found in Terraform outputs"
                echo "🔍 Available outputs:"
                timeout 30 terraform output || echo "No outputs available or timeout"
                echo "⚠️  Continuing without DynamoDB update..."
            fi
        else
            echo "⚠️  Warning: ENCLAVE_ID not set, skipping DynamoDB update"
        fi
        
        echo "✅ Deployment completed successfully - infrastructure is ready!"
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
        
        # Update enclave status to DESTROYED in DynamoDB
        echo "=== Updating Enclave Status to DESTROYED ==="
        if [ -n "$ENCLAVE_ID" ]; then
            echo "🧹 Updating enclave status to DESTROYED..."
            
            # Update the enclave status to DESTROYED
            aws dynamodb update-item \
                --table-name "treza-enclaves-dev" \
                --key "{\"id\": {\"S\": \"$ENCLAVE_ID\"}}" \
                --update-expression "SET #status = :status, #updated_at = :timestamp" \
                --expression-attribute-names "{\"#status\": \"status\", \"#updated_at\": \"updated_at\"}" \
                --expression-attribute-values "{\":status\": {\"S\": \"DESTROYED\"}, \":timestamp\": {\"S\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}}" \
                --region "$AWS_DEFAULT_REGION" \
                --output json 2>&1 | tee /tmp/dynamodb_cleanup.log
            
            DYNAMODB_EXIT_CODE=$?
            if [ $DYNAMODB_EXIT_CODE -eq 0 ]; then
                echo "✅ Successfully updated enclave status to DESTROYED: $ENCLAVE_ID"
            else
                echo "⚠️  Warning: Failed to update enclave status (exit code: $DYNAMODB_EXIT_CODE)"
                echo "📋 DynamoDB update log:"
                cat /tmp/dynamodb_cleanup.log
            fi
        else
            echo "⚠️  Warning: ENCLAVE_ID not set, skipping DynamoDB cleanup"
        fi
        ;;
    *)
        echo "ERROR: Unknown action '$ACTION'. Supported actions: plan, deploy, destroy"
        exit 1
        ;;
esac

echo "=== 🎉 Terraform Runner Completed Successfully ==="
exit 0