#!/bin/bash
set -e

# Teardown script for Treza Terraform Infrastructure
ENVIRONMENT=${1:-dev}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "=== Tearing Down Treza Infrastructure from $ENVIRONMENT ==="
echo "⚠️  WARNING: This will permanently destroy all infrastructure resources!"
echo "⚠️  This action cannot be undone!"
echo ""

# Configuration
TERRAFORM_DIR="$PROJECT_ROOT/terraform"

# Validate environment
case "$ENVIRONMENT" in
    dev|staging|prod)
        echo "Targeting $ENVIRONMENT environment for destruction"
        ;;
    *)
        echo "Error: Invalid environment '$ENVIRONMENT'. Use: dev, staging, or prod"
        exit 1
        ;;
esac

# Check prerequisites
echo "=== Checking Prerequisites ==="

if ! command -v terraform &> /dev/null; then
    echo "Error: Terraform is not installed"
    exit 1
fi

if ! command -v aws &> /dev/null; then
    echo "Error: AWS CLI is not installed"
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    echo "Error: AWS credentials not configured"
    exit 1
fi

echo "✓ Prerequisites check passed"

# Change to terraform directory
cd "$TERRAFORM_DIR"

# Check for required files or use environment-specific configs
if [ ! -f "terraform.tfvars" ]; then
    if [ -f "environments/${ENVIRONMENT}.tfvars" ]; then
        echo "Using environment-specific config: environments/${ENVIRONMENT}.tfvars"
        cp "environments/${ENVIRONMENT}.tfvars" terraform.tfvars
    else
        echo "Error: terraform.tfvars not found and no environment config available."
        exit 1
    fi
fi

if [ ! -f "backend.conf" ]; then
    if [ -f "environments/backend-${ENVIRONMENT}.conf" ]; then
        echo "Using environment-specific backend: environments/backend-${ENVIRONMENT}.conf"
        cp "environments/backend-${ENVIRONMENT}.conf" backend.conf
    else
        echo "Error: backend.conf not found and no environment backend config available."
        exit 1
    fi
fi

# Initialize Terraform to ensure we can access the state
echo "=== Initializing Terraform ==="
terraform init -backend-config=backend.conf

# Show what will be destroyed
echo "=== Generating Destruction Plan ==="
echo "Analyzing current infrastructure..."

if ! terraform plan -destroy -out=destroy.tfplan; then
    echo "Error: Failed to generate destruction plan"
    echo "This might mean:"
    echo "  1. No infrastructure is currently deployed"
    echo "  2. State file is not accessible"
    echo "  3. There are configuration issues"
    exit 1
fi

echo ""
echo "📋 The above shows what will be DESTROYED."
echo ""

# Final confirmation
if [ -t 0 ]; then
    echo "🔴 FINAL WARNING: This will permanently delete all infrastructure!"
    echo "This includes:"
    echo "  • VPC, subnets, and networking components"
    echo "  • ECS clusters and task definitions"
    echo "  • Lambda functions"
    echo "  • Step Functions"
    echo "  • IAM roles and policies"
    echo "  • CloudWatch logs and monitoring"
    echo "  • S3 state bucket (if created by this deployment)"
    echo ""
    read -p "Are you absolutely sure you want to destroy everything? Type 'destroy' to confirm: " -r
    echo
    if [[ ! $REPLY == "destroy" ]]; then
        echo "Destruction cancelled - you must type 'destroy' exactly"
        rm -f destroy.tfplan
        exit 0
    fi
    
    # Double confirmation
    echo ""
    read -p "Last chance! Type 'YES' to proceed with destruction: " -r
    echo
    if [[ ! $REPLY == "YES" ]]; then
        echo "Destruction cancelled"
        rm -f destroy.tfplan
        exit 0
    fi
fi

# Apply the destruction plan
echo "=== Destroying Infrastructure ==="
echo "🔥 Starting destruction process..."

if terraform apply destroy.tfplan; then
    echo ""
    echo "✅ Infrastructure destruction completed successfully!"
    
    # Clean up plan file
    rm -f destroy.tfplan
    
    # Optional: Clean up local state cache (but keep backend state for audit)
    echo ""
    read -p "Do you want to clean up local Terraform cache? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf .terraform/
        rm -f .terraform.lock.hcl
        echo "✅ Local Terraform cache cleaned"
    fi
    
    echo ""
    echo "🎉 Infrastructure teardown completed!"
    echo ""
    echo "What was destroyed:"
    echo "✓ All compute resources (ECS, Lambda)"
    echo "✓ All networking resources (VPC, subnets, security groups)"
    echo "✓ All monitoring and logging resources"
    echo "✓ All IAM roles and policies (except account-level permissions)"
    echo ""
    echo "Note: The S3 state bucket and DynamoDB locks table may still exist"
    echo "for audit purposes. These can be manually deleted if needed."
    echo ""
else
    echo ""
    echo "❌ Infrastructure destruction failed!"
    echo "Please check the error messages above."
    echo "You may need to:"
    echo "  1. Fix any resource dependencies manually in AWS console"
    echo "  2. Re-run this script"
    echo "  3. Use 'terraform state' commands to troubleshoot"
    exit 1
fi




