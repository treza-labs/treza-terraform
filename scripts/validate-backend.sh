#!/bin/bash
set -e

# Backend validation script for Treza infrastructure
ENVIRONMENT=${1:-dev}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$PROJECT_ROOT/terraform"

echo "🔍 Validating Backend Configuration for: $ENVIRONMENT"
echo "======================================================"
echo ""

# Change to terraform directory
cd "$TERRAFORM_DIR"

# Check if backend config exists
BACKEND_FILE="environments/backend-${ENVIRONMENT}.conf"
if [ ! -f "$BACKEND_FILE" ]; then
    echo "❌ Backend configuration not found: $BACKEND_FILE"
    exit 1
fi

echo "📋 Backend Configuration:"
cat "$BACKEND_FILE"
echo ""

# Parse backend configuration
BUCKET=$(grep "bucket" "$BACKEND_FILE" | cut -d'"' -f2)
REGION=$(grep "region" "$BACKEND_FILE" | cut -d'"' -f2)
DYNAMODB_TABLE=$(grep "dynamodb_table" "$BACKEND_FILE" | cut -d'"' -f2)

echo "🔧 Extracted Configuration:"
echo "  S3 Bucket: $BUCKET"
echo "  Region: $REGION"
echo "  DynamoDB Table: $DYNAMODB_TABLE"
echo ""

# Check AWS CLI availability
if ! command -v aws &> /dev/null; then
    echo "❌ AWS CLI not found. Please install AWS CLI to validate backend."
    exit 1
fi

# Check AWS credentials
echo "🔐 Checking AWS credentials..."
if ! aws sts get-caller-identity &> /dev/null; then
    echo "❌ AWS credentials not configured or invalid."
    echo "   Please run: aws configure"
    exit 1
fi

AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
AWS_USER=$(aws sts get-caller-identity --query Arn --output text)
echo "✅ AWS credentials valid"
echo "   Account: $AWS_ACCOUNT"
echo "   User: $AWS_USER"
echo ""

# Check S3 bucket
echo "🪣 Checking S3 bucket: $BUCKET"
if aws s3api head-bucket --bucket "$BUCKET" --region "$REGION" 2>/dev/null; then
    echo "✅ S3 bucket exists and accessible"
    
    # Check bucket versioning
    VERSIONING=$(aws s3api get-bucket-versioning --bucket "$BUCKET" --region "$REGION" --query Status --output text 2>/dev/null || echo "None")
    if [ "$VERSIONING" = "Enabled" ]; then
        echo "✅ Bucket versioning is enabled"
    else
        echo "⚠️  Bucket versioning is not enabled (recommended for state files)"
    fi
    
    # Check bucket encryption
    if aws s3api get-bucket-encryption --bucket "$BUCKET" --region "$REGION" &>/dev/null; then
        echo "✅ Bucket encryption is configured"
    else
        echo "⚠️  Bucket encryption is not configured (recommended for security)"
    fi
else
    echo "❌ S3 bucket does not exist or is not accessible"
    echo ""
    echo "To create the bucket:"
    echo "  aws s3 mb s3://$BUCKET --region $REGION"
    echo "  aws s3api put-bucket-versioning --bucket $BUCKET --versioning-configuration Status=Enabled"
    echo "  aws s3api put-bucket-encryption --bucket $BUCKET --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'"
    echo ""
fi

# Check DynamoDB table
echo "🗄️  Checking DynamoDB table: $DYNAMODB_TABLE"
if aws dynamodb describe-table --table-name "$DYNAMODB_TABLE" --region "$REGION" &>/dev/null; then
    echo "✅ DynamoDB table exists and accessible"
    
    # Check table configuration
    HASH_KEY=$(aws dynamodb describe-table --table-name "$DYNAMODB_TABLE" --region "$REGION" --query 'Table.KeySchema[0].AttributeName' --output text)
    if [ "$HASH_KEY" = "LockID" ]; then
        echo "✅ Table has correct hash key (LockID)"
    else
        echo "❌ Table hash key is '$HASH_KEY', should be 'LockID'"
    fi
else
    echo "❌ DynamoDB table does not exist or is not accessible"
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

echo "📊 Backend Validation Summary:"
echo "================================"
if aws s3api head-bucket --bucket "$BUCKET" --region "$REGION" 2>/dev/null && \
   aws dynamodb describe-table --table-name "$DYNAMODB_TABLE" --region "$REGION" &>/dev/null; then
    echo "✅ Backend is ready for Terraform!"
    echo ""
    echo "🚀 Next steps:"
    echo "   1. terraform init -backend-config=$BACKEND_FILE"
    echo "   2. terraform plan"
    echo "   3. terraform apply"
else
    echo "❌ Backend setup incomplete"
    echo ""
    echo "🔧 Please create missing resources using the commands above"
fi
echo ""