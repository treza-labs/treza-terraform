#!/bin/bash
set -e

# Deployment script for Treza Terraform Infrastructure
ENVIRONMENT=${1:-dev}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "=== Deploying Treza Infrastructure to $ENVIRONMENT ==="

# Configuration
TERRAFORM_DIR="$PROJECT_ROOT/terraform"
DOCKER_DIR="$PROJECT_ROOT/docker"

# Validate environment
case "$ENVIRONMENT" in
    dev|staging|prod)
        echo "Deploying to $ENVIRONMENT environment"
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

if ! command -v docker &> /dev/null; then
    echo "Error: Docker is not installed"
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    echo "Error: AWS credentials not configured"
    exit 1
fi

echo "✓ Prerequisites check passed"

# Validate Terraform configuration
echo "=== Validating Terraform Configuration ==="
cd "$TERRAFORM_DIR"

# Security validation function
validate_security_config() {
    echo "🔒 Validating Security Configuration..."
    
    if [ ! -f "terraform.tfvars" ]; then
        echo "⚠️  terraform.tfvars not found, skipping security validation"
        return 0
    fi
    
    # Check for required security variables
    if ! grep -q "allowed_ssh_cidrs" terraform.tfvars; then
        echo "❌ ERROR: allowed_ssh_cidrs not found in terraform.tfvars"
        echo "   This is required for security. Please add it to your .tfvars file."
        return 1
    fi
    
    # Check for insecure SSH configuration
    if grep -q "0.0.0.0/0" terraform.tfvars; then
        echo "❌ ERROR: SSH access from 0.0.0.0/0 detected in terraform.tfvars"
        echo "   This is a security risk. Please use specific CIDR blocks."
        return 1
    fi
    
    # Check for placeholder values
    if grep -q "YOUR_OFFICE_IP" terraform.tfvars; then
        echo "❌ ERROR: Placeholder 'YOUR_OFFICE_IP' found in terraform.tfvars"
        echo "   Please replace with your actual office IP address."
        return 1
    fi
    
    echo "✅ Security configuration validation passed"
    return 0
}

# Check for required files or use environment-specific configs
if [ ! -f "terraform.tfvars" ]; then
    if [ -f "environments/${ENVIRONMENT}.tfvars" ]; then
        echo "Using environment-specific config: environments/${ENVIRONMENT}.tfvars"
        cp "environments/${ENVIRONMENT}.tfvars" terraform.tfvars
    else
        echo "Error: terraform.tfvars not found and no environment config available."
        echo "Available options:"
        echo "  1. Copy from terraform.tfvars.example and customize"
        echo "  2. Use: cp environments/${ENVIRONMENT}.tfvars terraform.tfvars"
        exit 1
    fi
fi

if [ ! -f "backend.conf" ]; then
    if [ -f "environments/backend-${ENVIRONMENT}.conf" ]; then
        echo "Using environment-specific backend: environments/backend-${ENVIRONMENT}.conf"
        cp "environments/backend-${ENVIRONMENT}.conf" backend.conf
    else
        echo "Error: backend.conf not found and no environment backend config available."
        echo "Available options:"
        echo "  1. Copy from backend.conf.example and customize"
        echo "  2. Use: cp environments/backend-${ENVIRONMENT}.conf backend.conf"
        exit 1
    fi
fi

# Run security validation
if ! validate_security_config; then
    echo ""
    echo "❌ Security validation failed!"
    echo "Please fix the security configuration issues above before deploying."
    exit 1
fi

# Validate backend configuration
echo "Validating backend configuration..."
if [ -f "$PROJECT_ROOT/scripts/validate-backend.sh" ]; then
    if ! "$PROJECT_ROOT/scripts/validate-backend.sh" "$ENVIRONMENT"; then
        echo ""
        echo "❌ Backend validation failed!"
        echo "💡 To create backend resources automatically:"
        echo "   $PROJECT_ROOT/scripts/create-backend.sh $ENVIRONMENT"
        echo ""
        read -p "Do you want to create backend resources now? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            "$PROJECT_ROOT/scripts/create-backend.sh" "$ENVIRONMENT"
        else
            echo "Please create backend resources manually and try again."
            exit 1
        fi
    fi
fi

# Initialize Terraform
echo "Initializing Terraform..."
terraform init -backend-config=backend.conf

# Validate configuration
echo "Validating Terraform configuration..."
if ! terraform validate; then
    echo "Warning: Terraform validation failed, but continuing (may be plugin timeout)"
fi

echo "✓ Terraform validation completed"

# Build and push Docker image
echo "=== Building Docker Image ==="
cd "$PROJECT_ROOT"

# Set environment variables for Docker build
export AWS_REGION=$(grep aws_region terraform/terraform.tfvars | cut -d'"' -f2)
export IMAGE_NAME="treza-$ENVIRONMENT-terraform-runner"

# Build and push Docker image
if [ -f "$DOCKER_DIR/scripts/build-and-push.sh" ]; then
    chmod +x "$DOCKER_DIR/scripts/build-and-push.sh"
    "$DOCKER_DIR/scripts/build-and-push.sh"
else
    echo "Warning: Docker build script not found, skipping Docker build"
fi

echo "✓ Docker image build completed"

# Build Lambda functions first
echo "=== Building Lambda Functions ==="
cd "$PROJECT_ROOT"
if [ -f "modules/lambda/build-functions.sh" ]; then
    ./modules/lambda/build-functions.sh
else
    echo "Warning: Lambda build script not found, skipping..."
fi

# Deploy infrastructure
echo "=== Deploying Infrastructure ==="
cd "$TERRAFORM_DIR"

# Show deployment plan
echo "Generating deployment plan..."
terraform plan -out=tfplan

# Prompt for confirmation in interactive mode
if [ -t 0 ]; then
    read -p "Do you want to apply this plan? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Deployment cancelled"
        exit 0
    fi
fi

# Apply the plan
echo "Applying Terraform configuration..."
terraform apply tfplan

echo "✓ Infrastructure deployment completed"

# Display outputs
echo "=== Deployment Outputs ==="
terraform output

echo ""
echo "🎉 Deployment to $ENVIRONMENT completed successfully!"
echo ""
echo "Next steps:"
echo "1. Check CloudWatch dashboard: $(terraform output -raw cloudwatch_dashboard_url 2>/dev/null || echo 'N/A')"
echo "2. Verify Lambda functions are deployed"
echo "3. Test the deployment workflow"
echo ""