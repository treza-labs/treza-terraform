#!/bin/bash
set -e

# Backend creation script for Treza infrastructure
ENVIRONMENT=${1:-dev}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$PROJECT_ROOT/terraform"

echo "🏗️  Creating Backend Infrastructure for: $ENVIRONMENT"
echo "======================================================"
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

# Change to terraform directory
cd "$TERRAFORM_DIR"

# Check backend config
BACKEND_FILE="environments/backend-${ENVIRONMENT}.conf"
if [ ! -f "$BACKEND_FILE" ]; then
    echo "❌ Backend configuration not found: $BACKEND_FILE"
    exit 1
fi

# Parse configuration
BUCKET=$(grep "bucket" "$BACKEND_FILE" | cut -d'"' -f2)
REGION=$(grep "region" "$BACKEND_FILE" | cut -d'"' -f2)
DYNAMODB_TABLE=$(grep "dynamodb_table" "$BACKEND_FILE" | cut -d'"' -f2)

echo "📋 Creating backend resources:"
echo "  S3 Bucket: $BUCKET"
echo "  DynamoDB Table: $DYNAMODB_TABLE"
echo "  Region: $REGION"
echo ""

# Check AWS CLI and credentials
if ! command -v aws &> /dev/null; then
    echo "❌ AWS CLI not found. Please install AWS CLI."
    exit 1
fi

if ! aws sts get-caller-identity &> /dev/null; then
    echo "❌ AWS credentials not configured. Please run: aws configure"
    exit 1
fi

# Create S3 bucket
echo "🪣 Creating S3 bucket..."
if aws s3api head-bucket --bucket "$BUCKET" --region "$REGION" 2>/dev/null; then
    echo "✅ S3 bucket already exists: $BUCKET"
else
    echo "Creating S3 bucket: $BUCKET"
    aws s3 mb "s3://$BUCKET" --region "$REGION"
    echo "✅ S3 bucket created"
fi

# Enable versioning
echo "Enabling bucket versioning..."
aws s3api put-bucket-versioning \
    --bucket "$BUCKET" \
    --versioning-configuration Status=Enabled
echo "✅ Bucket versioning enabled"

# Enable encryption
echo "Enabling bucket encryption..."
aws s3api put-bucket-encryption \
    --bucket "$BUCKET" \
    --server-side-encryption-configuration '{
        "Rules": [{
            "ApplyServerSideEncryptionByDefault": {
                "SSEAlgorithm": "AES256"
            }
        }]
    }'
echo "✅ Bucket encryption enabled"

# Block public access
echo "Blocking public access..."
aws s3api put-public-access-block \
    --bucket "$BUCKET" \
    --public-access-block-configuration \
        BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
echo "✅ Public access blocked"

# Create DynamoDB table
echo ""
echo "🗄️  Creating DynamoDB table..."
if aws dynamodb describe-table --table-name "$DYNAMODB_TABLE" --region "$REGION" &>/dev/null; then
    echo "✅ DynamoDB table already exists: $DYNAMODB_TABLE"
else
    echo "Creating DynamoDB table: $DYNAMODB_TABLE"
    aws dynamodb create-table \
        --table-name "$DYNAMODB_TABLE" \
        --attribute-definitions AttributeName=LockID,AttributeType=S \
        --key-schema AttributeName=LockID,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --region "$REGION" \
        --tags Key=Environment,Value="$ENVIRONMENT" Key=Project,Value=treza Key=Purpose,Value=terraform-state-locking
    
    echo "Waiting for table to be active..."
    aws dynamodb wait table-exists --table-name "$DYNAMODB_TABLE" --region "$REGION"
    echo "✅ DynamoDB table created and active"
fi

echo ""
echo "🎉 Backend Infrastructure Created Successfully!"
echo "=============================================="
echo ""
echo "📋 Resources created:"
echo "  ✅ S3 Bucket: $BUCKET (versioned, encrypted, public access blocked)"
echo "  ✅ DynamoDB Table: $DYNAMODB_TABLE (pay-per-request billing)"
echo ""
echo "🚀 Ready for Terraform initialization:"
echo "   terraform init -backend-config=$BACKEND_FILE"
echo ""