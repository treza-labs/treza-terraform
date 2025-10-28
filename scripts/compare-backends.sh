#!/bin/bash
set -euo pipefail

# Backend comparison script for Treza infrastructure
# Compares backend configurations across environments and validates resources
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

# Function to parse backend config
parse_backend_config() {
    local env=$1
    local backend_file="$TERRAFORM_DIR/environments/backend-${env}.conf"
    
    if [ ! -f "$backend_file" ]; then
        echo "NOT_FOUND"
        return 1
    fi
    
    local bucket=$(grep "^[[:space:]]*bucket" "$backend_file" | sed 's/.*=[[:space:]]*"\([^"]*\)".*/\1/' | tr -d ' ')
    local key=$(grep "^[[:space:]]*key" "$backend_file" | sed 's/.*=[[:space:]]*"\([^"]*\)".*/\1/' | tr -d ' ')
    local region=$(grep "^[[:space:]]*region" "$backend_file" | sed 's/.*=[[:space:]]*"\([^"]*\)".*/\1/' | tr -d ' ')
    local dynamodb_table=$(grep "^[[:space:]]*dynamodb_table" "$backend_file" | sed 's/.*=[[:space:]]*"\([^"]*\)".*/\1/' | tr -d ' ')
    local encrypt=$(grep "^[[:space:]]*encrypt" "$backend_file" | sed 's/.*=[[:space:]]*\([^[:space:]]*\).*/\1/' | tr -d ' ')
    
    echo "$bucket|$key|$region|$dynamodb_table|$encrypt"
}

# Function to check if AWS resource exists
check_s3_bucket() {
    local bucket=$1
    local region=$2
    if aws s3api head-bucket --bucket "$bucket" --region "$region" 2>/dev/null; then
        echo "EXISTS"
    else
        echo "NOT_FOUND"
    fi
}

check_dynamodb_table() {
    local table=$1
    local region=$2
    if aws dynamodb describe-table --table-name "$table" --region "$region" 2>/dev/null >/dev/null; then
        echo "EXISTS"
    else
        echo "NOT_FOUND"
    fi
}

check_bucket_versioning() {
    local bucket=$1
    local region=$2
    local versioning=$(aws s3api get-bucket-versioning --bucket "$bucket" --region "$region" --query Status --output text 2>/dev/null || echo "None")
    echo "$versioning"
}

check_bucket_encryption() {
    local bucket=$1
    local region=$2
    if aws s3api get-bucket-encryption --bucket "$bucket" --region "$region" &>/dev/null; then
        echo "ENABLED"
    else
        echo "DISABLED"
    fi
}

# Main script
clear
header "╔════════════════════════════════════════════════════════════════╗"
header "║     Treza Backend Configuration Comparison Tool                ║"
header "╚════════════════════════════════════════════════════════════════╝"
echo ""

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

# Parse all backend configurations
ENVIRONMENTS=("dev" "staging" "prod")
declare -A CONFIGS

for env in "${ENVIRONMENTS[@]}"; do
    CONFIGS[$env]=$(parse_backend_config "$env")
done

# Display comparison table
header "═══════════════════════════════════════════════════════════════"
header "Backend Configuration Comparison"
header "═══════════════════════════════════════════════════════════════"
echo ""

# Print table header
printf "${BOLD}%-20s${NC} | ${CYAN}%-30s${NC} | ${MAGENTA}%-30s${NC} | ${YELLOW}%-30s${NC}\n" \
    "Setting" "Development" "Staging" "Production"
echo "$(printf '%.0s─' {1..120})"

# Parse and display each configuration item
for item in "bucket" "key" "region" "dynamodb_table" "encrypt"; do
    # Determine field number for cut
    field_num=1
    case $item in
        bucket) field_num=1;;
        key) field_num=2;;
        region) field_num=3;;
        dynamodb_table) field_num=4;;
        encrypt) field_num=5;;
    esac
    
    dev_value=$(echo "${CONFIGS[dev]}" | cut -d'|' -f$field_num)
    staging_value=$(echo "${CONFIGS[staging]}" | cut -d'|' -f$field_num)
    prod_value=$(echo "${CONFIGS[prod]}" | cut -d'|' -f$field_num)
    
    printf "%-20s | %-30s | %-30s | %-30s\n" \
        "$item" "$dev_value" "$staging_value" "$prod_value"
done

echo ""
echo ""

# Resource validation section
header "═══════════════════════════════════════════════════════════════"
header "Resource Validation"
header "═══════════════════════════════════════════════════════════════"
echo ""

for env in "${ENVIRONMENTS[@]}"; do
    config="${CONFIGS[$env]}"
    
    if [ "$config" = "NOT_FOUND" ]; then
        warning "Backend configuration for $env not found"
        continue
    fi
    
    bucket=$(echo "$config" | cut -d'|' -f1)
    region=$(echo "$config" | cut -d'|' -f3)
    dynamodb_table=$(echo "$config" | cut -d'|' -f4)
    
    echo -e "${BOLD}${BLUE}$env Environment:${NC}"
    
    # Check S3 bucket
    s3_status=$(check_s3_bucket "$bucket" "$region")
    if [ "$s3_status" = "EXISTS" ]; then
        success "S3 Bucket: $bucket"
        
        # Check versioning
        versioning=$(check_bucket_versioning "$bucket" "$region")
        if [ "$versioning" = "Enabled" ]; then
            echo -e "   ${GREEN}├─ Versioning: Enabled${NC}"
        else
            echo -e "   ${YELLOW}├─ Versioning: $versioning (recommended: Enabled)${NC}"
        fi
        
        # Check encryption
        encryption=$(check_bucket_encryption "$bucket" "$region")
        if [ "$encryption" = "ENABLED" ]; then
            echo -e "   ${GREEN}└─ Encryption: Enabled${NC}"
        else
            echo -e "   ${YELLOW}└─ Encryption: Disabled (recommended: Enabled)${NC}"
        fi
    else
        error "S3 Bucket: $bucket (NOT FOUND)"
        echo -e "   ${YELLOW}Create with: ./scripts/create-backend.sh $env${NC}"
    fi
    
    # Check DynamoDB table
    dynamodb_status=$(check_dynamodb_table "$dynamodb_table" "$region")
    if [ "$dynamodb_status" = "EXISTS" ]; then
        success "DynamoDB Table: $dynamodb_table"
    else
        error "DynamoDB Table: $dynamodb_table (NOT FOUND)"
        echo -e "   ${YELLOW}Create with: ./scripts/create-backend.sh $env${NC}"
    fi
    
    echo ""
done

# Best practices recommendations
header "═══════════════════════════════════════════════════════════════"
header "Best Practices & Recommendations"
header "═══════════════════════════════════════════════════════════════"
echo ""

recommendations=()

# Check for region diversity
dev_region=$(echo "${CONFIGS[dev]}" | cut -d'|' -f3)
staging_region=$(echo "${CONFIGS[staging]}" | cut -d'|' -f3)
prod_region=$(echo "${CONFIGS[prod]}" | cut -d'|' -f3)

if [ "$dev_region" = "$staging_region" ] && [ "$staging_region" = "$prod_region" ]; then
    recommendations+=("${YELLOW}⚠️  All environments use the same region ($dev_region). Consider using different regions for production isolation.${NC}")
fi

# Check for bucket naming patterns
dev_bucket=$(echo "${CONFIGS[dev]}" | cut -d'|' -f1)
staging_bucket=$(echo "${CONFIGS[staging]}" | cut -d'|' -f1)
prod_bucket=$(echo "${CONFIGS[prod]}" | cut -d'|' -f1)

if [[ "$prod_bucket" == *"prod"* ]]; then
    recommendations+=("${GREEN}✅ Production bucket naming follows best practices (includes 'prod' identifier)${NC}")
fi

# Check encryption
for env in "${ENVIRONMENTS[@]}"; do
    encrypt=$(echo "${CONFIGS[$env]}" | cut -d'|' -f5)
    if [ "$encrypt" != "true" ]; then
        recommendations+=("${RED}❌ Encryption not enabled for $env environment backend${NC}")
    fi
done

# Display recommendations
if [ ${#recommendations[@]} -eq 0 ]; then
    success "All backend configurations follow best practices! 🎉"
else
    for rec in "${recommendations[@]}"; do
        echo -e "$rec"
    done
fi

echo ""

# Summary and next steps
header "═══════════════════════════════════════════════════════════════"
header "Summary & Next Steps"
header "═══════════════════════════════════════════════════════════════"
echo ""

info "Quick Commands:"
echo ""
echo "  ${CYAN}# Validate specific backend${NC}"
echo "  ./scripts/validate-backend.sh dev"
echo ""
echo "  ${CYAN}# Create missing backend resources${NC}"
echo "  ./scripts/create-backend.sh <environment>"
echo ""
echo "  ${CYAN}# Switch to an environment${NC}"
echo "  make switch-env ENV=staging"
echo ""
echo "  ${CYAN}# Initialize Terraform with backend${NC}"
echo "  make init ENV=prod"
echo ""

success "Backend comparison complete!"
echo ""

