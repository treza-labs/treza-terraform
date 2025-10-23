#!/bin/bash
set -euo pipefail

# Backend validation script for Treza infrastructure
ENVIRONMENT=${1:-dev}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$PROJECT_ROOT/terraform"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Track errors and warnings
ERROR_COUNT=0
WARNING_COUNT=0

# Logging functions
log() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

success() {
    echo -e "${GREEN}✅ $*${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $*${NC}"
    ((WARNING_COUNT++))
}

error() {
    echo -e "${RED}❌ $*${NC}"
    ((ERROR_COUNT++))
}

info() {
    echo -e "${BLUE}ℹ️  $*${NC}"
}

log "🔍 Validating Backend Configuration for: $ENVIRONMENT"
echo "======================================================"
echo ""

# Change to terraform directory
cd "$TERRAFORM_DIR"

# Check if backend config exists
BACKEND_FILE="environments/backend-${ENVIRONMENT}.conf"
if [ ! -f "$BACKEND_FILE" ]; then
    error "Backend configuration not found: $BACKEND_FILE"
    exit 1
fi

info "Backend Configuration:"
cat "$BACKEND_FILE"
echo ""

# Parse backend configuration
BUCKET=$(grep "bucket" "$BACKEND_FILE" | cut -d'"' -f2)
REGION=$(grep "region" "$BACKEND_FILE" | cut -d'"' -f2)
DYNAMODB_TABLE=$(grep "dynamodb_table" "$BACKEND_FILE" | cut -d'"' -f2)

info "Extracted Configuration:"
echo "  S3 Bucket: $BUCKET"
echo "  Region: $REGION"
echo "  DynamoDB Table: $DYNAMODB_TABLE"
echo ""

# Check AWS CLI availability
if ! command -v aws &> /dev/null; then
    error "AWS CLI not found. Please install AWS CLI to validate backend."
    exit 1
fi

# Check AWS credentials
info "Checking AWS credentials..."
if ! aws sts get-caller-identity &> /dev/null; then
    error "AWS credentials not configured or invalid."
    echo "   Please run: aws configure"
    exit 1
fi

AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
AWS_USER=$(aws sts get-caller-identity --query Arn --output text)
success "AWS credentials valid"
echo "   Account: $AWS_ACCOUNT"
echo "   User: $AWS_USER"
echo ""

# Check S3 bucket
info "Checking S3 bucket: $BUCKET"
if aws s3api head-bucket --bucket "$BUCKET" --region "$REGION" 2>/dev/null; then
    success "S3 bucket exists and accessible"
    
    # Check bucket versioning
    VERSIONING=$(aws s3api get-bucket-versioning --bucket "$BUCKET" --region "$REGION" --query Status --output text 2>/dev/null || echo "None")
    if [ "$VERSIONING" = "Enabled" ]; then
        success "Bucket versioning is enabled"
    else
        warning "Bucket versioning is not enabled (recommended for state files)"
    fi
    
    # Check bucket encryption
    if aws s3api get-bucket-encryption --bucket "$BUCKET" --region "$REGION" &>/dev/null; then
        success "Bucket encryption is configured"
    else
        warning "Bucket encryption is not configured (recommended for security)"
    fi
else
    error "S3 bucket does not exist or is not accessible"
    echo ""
    echo "To create the bucket:"
    echo "  aws s3 mb s3://$BUCKET --region $REGION"
    echo "  aws s3api put-bucket-versioning --bucket $BUCKET --versioning-configuration Status=Enabled"
    echo "  aws s3api put-bucket-encryption --bucket $BUCKET --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'"
    echo ""
fi

# Check DynamoDB table
info "Checking DynamoDB table: $DYNAMODB_TABLE"
if aws dynamodb describe-table --table-name "$DYNAMODB_TABLE" --region "$REGION" &>/dev/null; then
    success "DynamoDB table exists and accessible"
    
    # Check table configuration
    HASH_KEY=$(aws dynamodb describe-table --table-name "$DYNAMODB_TABLE" --region "$REGION" --query 'Table.KeySchema[0].AttributeName' --output text)
    if [ "$HASH_KEY" = "LockID" ]; then
        success "Table has correct hash key (LockID)"
    else
        error "Table hash key is '$HASH_KEY', should be 'LockID'"
    fi
else
    error "DynamoDB table does not exist or is not accessible"
    echo ""
    echo "To create the table:"
    echo "  aws dynamodb create-table \\"
    echo "    --table-name $DYNAMODB_TABLE \\"
    echo "    --attribute-definitions AttributeName=LockID,AttributeType=S \\"
    echo "    --key-schema AttributeName=LockID,KeyType=HASH \\"
    echo "    --billing-mode PAY_PER_REQUEST \\"
    echo "    --region $REGION"
    echo ""
fi

echo ""
echo "================================================================="
log "Backend Validation Summary for $ENVIRONMENT"
echo ""

# Display summary based on error and warning counts
if aws s3api head-bucket --bucket "$BUCKET" --region "$REGION" 2>/dev/null && \
   aws dynamodb describe-table --table-name "$DYNAMODB_TABLE" --region "$REGION" &>/dev/null; then
    
    if [ $ERROR_COUNT -gt 0 ]; then
        error "Backend validation completed with $ERROR_COUNT error(s) and $WARNING_COUNT warning(s)"
        echo ""
        echo -e "${RED}Please resolve errors before proceeding${NC}"
        exit 1
    elif [ $WARNING_COUNT -gt 0 ]; then
        warning "Backend is functional but has $WARNING_COUNT warning(s)"
        echo ""
        echo -e "${YELLOW}Consider addressing warnings for production use${NC}"
        echo ""
        info "Next steps:"
        echo "   1. terraform init -backend-config=$BACKEND_FILE"
        echo "   2. terraform plan"
        echo "   3. terraform apply"
        exit 0
    else
        success "Backend is ready for Terraform!"
        echo -e "${GREEN}No errors or warnings detected${NC}"
        echo ""
        info "Next steps:"
        echo "   1. terraform init -backend-config=$BACKEND_FILE"
        echo "   2. terraform plan"
        echo "   3. terraform apply"
        exit 0
    fi
else
    error "Backend validation failed with $ERROR_COUNT error(s) and $WARNING_COUNT warning(s)"
    echo ""
    echo -e "${RED}Backend setup incomplete - please create missing resources using the commands above${NC}"
    exit 1
fi