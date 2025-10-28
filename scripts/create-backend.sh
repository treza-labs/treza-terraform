#!/bin/bash
set -euo pipefail

# Backend creation script for Treza infrastructure with enhanced features
# Usage: ./create-backend.sh <environment> [--dry-run]

ENVIRONMENT=""
DRY_RUN=false
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$PROJECT_ROOT/terraform"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Logging functions
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

header() {
    echo -e "${BOLD}${CYAN}$*${NC}"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run|-n)
            DRY_RUN=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 <environment> [--dry-run]"
            echo ""
            echo "Arguments:"
            echo "  environment    Environment to create backend for (dev|staging|prod)"
            echo ""
            echo "Options:"
            echo "  --dry-run, -n  Show what would be created without making changes"
            echo "  --help, -h     Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 dev                # Create dev backend"
            echo "  $0 prod --dry-run     # Preview prod backend creation"
            exit 0
            ;;
        *)
            if [ -z "$ENVIRONMENT" ]; then
                ENVIRONMENT=$1
            else
                error "Unknown argument: $1"
                exit 1
            fi
            shift
            ;;
    esac
done

# Set default environment if not provided
ENVIRONMENT=${ENVIRONMENT:-dev}

header "╔════════════════════════════════════════════════════════════════╗"
if [ "$DRY_RUN" = true ]; then
    header "║       Treza Backend Creation (DRY-RUN MODE)                    ║"
else
    header "║       Treza Backend Creation                                   ║"
fi
header "║       Environment: $(printf '%-44s' "$ENVIRONMENT")║"
header "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Validate environment
case "$ENVIRONMENT" in
    dev|staging|prod)
        success "Valid environment: $ENVIRONMENT"
        ;;
    *)
        error "Invalid environment '$ENVIRONMENT'"
        echo "Valid options: dev, staging, prod"
        exit 1
        ;;
esac

# Change to terraform directory
cd "$TERRAFORM_DIR"

# Check backend config
BACKEND_FILE="environments/backend-${ENVIRONMENT}.conf"
if [ ! -f "$BACKEND_FILE" ]; then
    error "Backend configuration not found: $BACKEND_FILE"
    exit 1
fi

# Parse configuration
BUCKET=$(grep "bucket" "$BACKEND_FILE" | sed 's/.*=[[:space:]]*"\([^"]*\)".*/\1/' | tr -d ' ')
REGION=$(grep "region" "$BACKEND_FILE" | sed 's/.*=[[:space:]]*"\([^"]*\)".*/\1/' | tr -d ' ')
DYNAMODB_TABLE=$(grep "dynamodb_table" "$BACKEND_FILE" | sed 's/.*=[[:space:]]*"\([^"]*\)".*/\1/' | tr -d ' ')
ENCRYPT=$(grep "encrypt" "$BACKEND_FILE" | sed 's/.*=[[:space:]]*\([^[:space:]]*\).*/\1/' | tr -d ' ')

echo ""
header "═══════════════════════════════════════════════════════════════"
header "Backend Configuration Summary"
header "═══════════════════════════════════════════════════════════════"
echo ""
info "Resources to be created:"
echo "  ${BOLD}S3 Bucket:${NC}       $BUCKET"
echo "  ${BOLD}DynamoDB Table:${NC}  $DYNAMODB_TABLE"
echo "  ${BOLD}Region:${NC}          $REGION"
echo "  ${BOLD}Encryption:${NC}      $ENCRYPT"
echo ""

# Check AWS CLI and credentials
info "Validating prerequisites..."
if ! command -v aws &> /dev/null; then
    error "AWS CLI not found. Please install AWS CLI."
    exit 1
fi

if ! aws sts get-caller-identity &> /dev/null; then
    error "AWS credentials not configured. Please run: aws configure"
    exit 1
fi

AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
AWS_USER=$(aws sts get-caller-identity --query Arn --output text)
success "AWS credentials validated"
echo "  Account: $AWS_ACCOUNT"
echo "  User: $AWS_USER"
echo ""

# Cost estimation
header "═══════════════════════════════════════════════════════════════"
header "Estimated Monthly Costs"
header "═══════════════════════════════════════════════════════════════"
echo ""
info "Cost breakdown (based on typical Terraform state usage):"
echo "  ${BOLD}S3 Storage:${NC}          ~\$0.01 - \$0.05/month (< 1 GB state files)"
echo "  ${BOLD}S3 Requests:${NC}         ~\$0.00 - \$0.01/month (< 1000 requests)"
echo "  ${BOLD}DynamoDB:${NC}            ~\$0.00/month (pay-per-request, minimal locking)"
echo "  ${BOLD}Data Transfer:${NC}       ~\$0.00/month (within same region)"
echo ""
echo "  ${BOLD}${CYAN}Total Estimated:${NC}     ~\$0.01 - \$0.10/month"
echo ""
warning "Actual costs may vary based on usage patterns and state file sizes"
echo ""

# Check if resources already exist
S3_EXISTS=false
DYNAMODB_EXISTS=false

if aws s3api head-bucket --bucket "$BUCKET" --region "$REGION" 2>/dev/null; then
    S3_EXISTS=true
fi

if aws dynamodb describe-table --table-name "$DYNAMODB_TABLE" --region "$REGION" &>/dev/null; then
    DYNAMODB_EXISTS=true
fi

if [ "$DRY_RUN" = true ]; then
    header "═══════════════════════════════════════════════════════════════"
    header "Dry-Run Mode - Resources That Would Be Created/Updated"
    header "═══════════════════════════════════════════════════════════════"
    echo ""
    
    if [ "$S3_EXISTS" = false ]; then
        info "Would create S3 bucket:"
        echo "  - Bucket name: $BUCKET"
        echo "  - Region: $REGION"
        echo "  - Versioning: Enabled"
        echo "  - Encryption: AES256"
        echo "  - Public access: Blocked"
        echo "  - Tags: Environment=$ENVIRONMENT, Project=treza"
    else
        success "S3 bucket already exists: $BUCKET"
        info "Would update S3 bucket configuration:"
        echo "  - Ensure versioning is enabled"
        echo "  - Ensure encryption is enabled"
        echo "  - Ensure public access is blocked"
    fi
    
    echo ""
    
    if [ "$DYNAMODB_EXISTS" = false ]; then
        info "Would create DynamoDB table:"
        echo "  - Table name: $DYNAMODB_TABLE"
        echo "  - Hash key: LockID (String)"
        echo "  - Billing mode: PAY_PER_REQUEST"
        echo "  - Region: $REGION"
        echo "  - Tags: Environment=$ENVIRONMENT, Project=treza, Purpose=terraform-state-locking"
    else
        success "DynamoDB table already exists: $DYNAMODB_TABLE"
    fi
    
    echo ""
    header "═══════════════════════════════════════════════════════════════"
    warning "DRY-RUN MODE: No actual resources were created or modified"
    header "═══════════════════════════════════════════════════════════════"
    echo ""
    info "To create these resources, run without --dry-run flag:"
    echo "  ${CYAN}$0 $ENVIRONMENT${NC}"
    echo ""
    exit 0
fi

# Actual resource creation
header "═══════════════════════════════════════════════════════════════"
header "Creating Backend Resources"
header "═══════════════════════════════════════════════════════════════"
echo ""

# Create S3 bucket
info "🪣 Processing S3 bucket..."
if [ "$S3_EXISTS" = true ]; then
    success "S3 bucket already exists: $BUCKET"
else
    echo "  Creating S3 bucket: $BUCKET"
    aws s3 mb "s3://$BUCKET" --region "$REGION"
    success "S3 bucket created"
fi

# Enable versioning
echo "  Configuring bucket versioning..."
aws s3api put-bucket-versioning \
    --bucket "$BUCKET" \
    --versioning-configuration Status=Enabled
success "Bucket versioning enabled"

# Enable encryption
echo "  Configuring bucket encryption..."
aws s3api put-bucket-encryption \
    --bucket "$BUCKET" \
    --server-side-encryption-configuration '{
        "Rules": [{
            "ApplyServerSideEncryptionByDefault": {
                "SSEAlgorithm": "AES256"
            }
        }]
    }'
success "Bucket encryption enabled"

# Block public access
echo "  Configuring public access block..."
aws s3api put-public-access-block \
    --bucket "$BUCKET" \
    --public-access-block-configuration \
        BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
success "Public access blocked"

# Add tags to S3 bucket
echo "  Adding tags to S3 bucket..."
aws s3api put-bucket-tagging \
    --bucket "$BUCKET" \
    --tagging "TagSet=[{Key=Environment,Value=$ENVIRONMENT},{Key=Project,Value=treza},{Key=Purpose,Value=terraform-state-storage}]"
success "S3 bucket tags applied"

# Create DynamoDB table
echo ""
info "🗄️  Processing DynamoDB table..."
if [ "$DYNAMODB_EXISTS" = true ]; then
    success "DynamoDB table already exists: $DYNAMODB_TABLE"
else
    echo "  Creating DynamoDB table: $DYNAMODB_TABLE"
    aws dynamodb create-table \
        --table-name "$DYNAMODB_TABLE" \
        --attribute-definitions AttributeName=LockID,AttributeType=S \
        --key-schema AttributeName=LockID,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --region "$REGION" \
        --tags Key=Environment,Value="$ENVIRONMENT" Key=Project,Value=treza Key=Purpose,Value=terraform-state-locking \
        > /dev/null
    
    echo "  Waiting for table to be active..."
    aws dynamodb wait table-exists --table-name "$DYNAMODB_TABLE" --region "$REGION"
    success "DynamoDB table created and active"
fi

# Get resource details
echo ""
header "═══════════════════════════════════════════════════════════════"
header "Backend Resources Summary"
header "═══════════════════════════════════════════════════════════════"
echo ""

# S3 Bucket Details
info "S3 Bucket: $BUCKET"
VERSIONING_STATUS=$(aws s3api get-bucket-versioning --bucket "$BUCKET" --query Status --output text 2>/dev/null || echo "Disabled")
ENCRYPTION_STATUS=$(aws s3api get-bucket-encryption --bucket "$BUCKET" --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm' --output text 2>/dev/null || echo "None")
echo "  ├─ Region: $REGION"
echo "  ├─ Versioning: $VERSIONING_STATUS"
echo "  ├─ Encryption: $ENCRYPTION_STATUS"
echo "  ├─ Public Access: Blocked"
echo "  └─ ARN: arn:aws:s3:::$BUCKET"
echo ""

# DynamoDB Table Details
info "DynamoDB Table: $DYNAMODB_TABLE"
TABLE_STATUS=$(aws dynamodb describe-table --table-name "$DYNAMODB_TABLE" --region "$REGION" --query 'Table.TableStatus' --output text 2>/dev/null || echo "UNKNOWN")
TABLE_ARN=$(aws dynamodb describe-table --table-name "$DYNAMODB_TABLE" --region "$REGION" --query 'Table.TableArn' --output text 2>/dev/null || echo "N/A")
BILLING_MODE=$(aws dynamodb describe-table --table-name "$DYNAMODB_TABLE" --region "$REGION" --query 'Table.BillingModeSummary.BillingMode' --output text 2>/dev/null || echo "PAY_PER_REQUEST")
echo "  ├─ Region: $REGION"
echo "  ├─ Status: $TABLE_STATUS"
echo "  ├─ Billing Mode: $BILLING_MODE"
echo "  ├─ Hash Key: LockID (String)"
echo "  └─ ARN: $TABLE_ARN"
echo ""

# Final success message
header "═══════════════════════════════════════════════════════════════"
success "🎉 Backend Infrastructure Ready!"
header "═══════════════════════════════════════════════════════════════"
echo ""

info "Next Steps:"
echo ""
echo "  ${BOLD}1. Initialize Terraform:${NC}"
echo "     ${CYAN}cd terraform${NC}"
echo "     ${CYAN}terraform init -backend-config=$BACKEND_FILE${NC}"
echo ""
echo "  ${BOLD}2. Or use the Makefile:${NC}"
echo "     ${CYAN}make init ENV=$ENVIRONMENT${NC}"
echo "     ${CYAN}make plan ENV=$ENVIRONMENT${NC}"
echo ""
echo "  ${BOLD}3. Validate backend:${NC}"
echo "     ${CYAN}./scripts/validate-backend.sh $ENVIRONMENT${NC}"
echo ""
echo "  ${BOLD}4. Compare backends:${NC}"
echo "     ${CYAN}./scripts/compare-backends.sh${NC}"
echo ""

info "Backend Configuration File: $BACKEND_FILE"
info "Estimated Monthly Cost: ~\$0.01 - \$0.10"
echo ""
success "Backend creation completed successfully! 🚀"
echo ""