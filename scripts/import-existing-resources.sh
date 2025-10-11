#!/bin/bash
set -euo pipefail

# Helper script to import existing AWS resources into Terraform state
# Useful when you have existing resources that need to be managed by Terraform

ENVIRONMENT=${1:-dev}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

success() {
    echo -e "${GREEN}✅ $*${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $*${NC}"
}

error() {
    echo -e "${RED}❌ $*${NC}"
}

info() {
    echo -e "${BLUE}ℹ️  $*${NC}"
}

log "📥 Import Existing Resources - Environment: $ENVIRONMENT"
echo "======================================================="

# Validate environment
case "$ENVIRONMENT" in
    dev|staging|prod)
        success "Valid environment: $ENVIRONMENT"
        ;;
    *)
        error "Invalid environment '$ENVIRONMENT'. Use: dev, staging, or prod"
        exit 1
        ;;
esac

cd "$PROJECT_ROOT/terraform"

# Check if terraform is initialized
if [ ! -d ".terraform" ]; then
    error "Terraform not initialized. Run: make init ENV=$ENVIRONMENT"
    exit 1
fi

info "This script helps import existing AWS resources into Terraform state."
info "Common resources to import:"
echo "  - Existing DynamoDB tables"
echo "  - Existing S3 buckets"
echo "  - Existing VPCs (if not creating new ones)"
echo "  - Existing security groups"
echo ""

# Function to import a resource
import_resource() {
    local resource_type="$1"
    local resource_name="$2"
    local resource_id="$3"
    
    info "Importing $resource_type: $resource_name"
    
    if terraform import "$resource_name" "$resource_id"; then
        success "Successfully imported $resource_type: $resource_id"
    else
        error "Failed to import $resource_type: $resource_id"
        return 1
    fi
}

# Example imports - uncomment and modify as needed
warning "The following are examples. Uncomment and modify as needed:"

echo "# Example: Import existing DynamoDB table"
echo "# import_resource 'DynamoDB Table' 'module.dynamodb_streams.aws_dynamodb_table.enclaves' 'treza-enclaves-$ENVIRONMENT'"

echo ""
echo "# Example: Import existing S3 bucket"
echo "# import_resource 'S3 Bucket' 'module.state_backend.aws_s3_bucket.terraform_state' 'my-existing-terraform-state-bucket'"

echo ""
echo "# Example: Import existing VPC"
echo "# import_resource 'VPC' 'module.networking.aws_vpc.main' 'vpc-1234567890abcdef0'"

echo ""
echo "# Example: Import existing security group"
echo "# import_resource 'Security Group' 'module.networking.aws_security_group.shared_enclave' 'sg-1234567890abcdef0'"

echo ""
info "To use this script:"
echo "1. Uncomment the import_resource lines above"
echo "2. Replace the resource IDs with your actual AWS resource IDs"
echo "3. Run the script again"

echo ""
warning "Important notes:"
echo "- Make sure the Terraform configuration matches the existing resource"
echo "- Run 'terraform plan' after importing to check for differences"
echo "- Some resources may require additional configuration updates"

echo ""
info "After importing, run:"
echo "  terraform plan    # Check for any configuration drift"
echo "  terraform apply   # Apply any necessary changes"

log "📥 Import script completed"
