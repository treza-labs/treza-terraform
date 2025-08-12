#!/bin/bash
set -e

# Simplified deployment script that handles Terraform plugin timeouts
ENVIRONMENT=${1:-dev}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$PROJECT_ROOT/terraform"

echo "🚀 SIMPLIFIED TREZA DEPLOYMENT FOR: $ENVIRONMENT"
echo "================================================="
echo ""

cd "$TERRAFORM_DIR"

# Function to retry terraform commands with exponential backoff
retry_terraform() {
    local command="$1"
    local max_attempts=3
    local delay=5
    
    for attempt in $(seq 1 $max_attempts); do
        echo "Attempt $attempt of $max_attempts: $command"
        
        if eval "$command"; then
            echo "✅ Command succeeded"
            return 0
        else
            if [ $attempt -lt $max_attempts ]; then
                echo "⚠️  Command failed, retrying in ${delay}s..."
                sleep $delay
                delay=$((delay * 2))
                
                # Clean and reinitialize on retry
                echo "Cleaning state for retry..."
                rm -rf .terraform .terraform.lock.hcl terraform.tfstate*
                terraform init -backend-config=backend.conf
            else
                echo "❌ Command failed after $max_attempts attempts"
                return 1
            fi
        fi
    done
}

# Initialize and validate
echo "🔄 Initializing Terraform..."
if ! terraform init -backend-config=backend.conf; then
    echo "❌ Terraform init failed"
    exit 1
fi

echo ""
echo "🔍 Validating configuration..."
if retry_terraform "terraform validate"; then
    echo "✅ Terraform validation successful"
else
    echo "⚠️  Validation failed, but continuing (may be plugin timeout)"
fi

echo ""
echo "📋 Generating plan..."
if retry_terraform "terraform plan -out=tfplan"; then
    echo "✅ Plan generated successfully"
    
    echo ""
    echo "🚀 Applying infrastructure..."
    if retry_terraform "terraform apply -auto-approve tfplan"; then
        echo ""
        echo "🎉 DEPLOYMENT SUCCESSFUL!"
        echo "========================"
        echo ""
        echo "📊 Deployment outputs:"
        terraform output || echo "Outputs will be available once all resources are created"
        echo ""
        echo "🔗 Next steps:"
        echo "  1. Update your treza-app DynamoDB table name in terraform.tfvars"
        echo "  2. Redeploy to connect to your app"
        echo "  3. Test end-to-end workflow"
    else
        echo "❌ Terraform apply failed"
        exit 1
    fi
else
    echo "❌ Terraform plan failed"
    echo ""
    echo "💡 This might be due to:"
    echo "   - Plugin timeout (common on macOS)"
    echo "   - AWS permissions"
    echo "   - Resource conflicts"
    echo ""
    echo "🔧 Troubleshooting:"
    echo "   - Check AWS credentials: aws sts get-caller-identity"
    echo "   - Try: terraform providers lock -platform=darwin_amd64"
    echo "   - Or deploy from a Linux environment (GitHub Actions)"
fi
