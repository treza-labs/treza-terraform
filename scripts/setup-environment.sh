#!/bin/bash
set -e

# Environment setup script for Treza infrastructure
ENVIRONMENT=${1:-dev}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$PROJECT_ROOT/terraform"

echo "🔧 Setting up Treza infrastructure for: $ENVIRONMENT"
echo "================================================="
echo ""

# Validate environment
case "$ENVIRONMENT" in
    dev|staging|prod)
        echo "✅ Valid environment: $ENVIRONMENT"
        ;;
    *)
        echo "❌ Invalid environment '$ENVIRONMENT'"
        echo "Valid options: dev, staging, prod"
        exit 1
        ;;
esac

cd "$TERRAFORM_DIR"

# Copy environment-specific configurations
echo "📋 Configuring environment files..."

if [ -f "environments/${ENVIRONMENT}.tfvars" ]; then
    cp "environments/${ENVIRONMENT}.tfvars" terraform.tfvars
    echo "✅ Copied: environments/${ENVIRONMENT}.tfvars → terraform.tfvars"
else
    echo "❌ Environment config not found: environments/${ENVIRONMENT}.tfvars"
    exit 1
fi

if [ -f "environments/backend-${ENVIRONMENT}.conf" ]; then
    cp "environments/backend-${ENVIRONMENT}.conf" backend.conf
    echo "✅ Copied: environments/backend-${ENVIRONMENT}.conf → backend.conf"
else
    echo "❌ Backend config not found: environments/backend-${ENVIRONMENT}.conf"
    exit 1
fi

echo ""
echo "🎯 Environment Configuration Summary"
echo "===================================="
echo "Environment: $ENVIRONMENT"
echo ""
echo "Terraform Variables (terraform.tfvars):"
grep -E "^[a-z]" terraform.tfvars | head -10
echo ""
echo "Backend Configuration (backend.conf):"
cat backend.conf
echo ""
echo "✅ Environment setup complete!"
echo ""
# Validate security configuration
echo "🔒 Security Configuration Validation"
echo "===================================="
echo ""

# Check if security variables are configured
if grep -q "allowed_ssh_cidrs" terraform.tfvars; then
    SSH_CIDRS=$(grep "allowed_ssh_cidrs" terraform.tfvars | head -1)
    echo "✅ SSH Access: $SSH_CIDRS"
    
    # Warn if using default/broad CIDRs
    if echo "$SSH_CIDRS" | grep -q "0.0.0.0/0"; then
        echo "⚠️  WARNING: SSH access from 0.0.0.0/0 detected - this is insecure!"
        echo "   Please update allowed_ssh_cidrs with specific CIDR blocks"
    elif echo "$SSH_CIDRS" | grep -q "YOUR_OFFICE_IP"; then
        echo "⚠️  WARNING: Please replace YOUR_OFFICE_IP with your actual office IP address"
    fi
else
    echo "❌ Security variables not found in terraform.tfvars"
    echo "   This deployment will fail. Please ensure your .tfvars includes:"
    echo "   - allowed_ssh_cidrs"
    echo "   - security_group_rules"
fi

if grep -q "security_group_rules" terraform.tfvars; then
    echo "✅ Security group rules configured"
else
    echo "❌ security_group_rules not found in terraform.tfvars"
fi

echo ""
echo "🚀 Next steps:"
echo "   1. Review and customize terraform.tfvars security settings"
echo "   2. Ensure backend S3 bucket exists in AWS"
echo "   3. Update allowed_ssh_cidrs with your actual network CIDRs"
echo "   4. Run: ./scripts/deploy.sh $ENVIRONMENT"
echo ""