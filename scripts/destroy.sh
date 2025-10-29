#!/bin/bash
set -euo pipefail

# Enhanced teardown script for Treza Terraform Infrastructure
# Usage: ./destroy.sh <environment> [--dry-run]

ENVIRONMENT=""
DRY_RUN=false
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

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

danger() {
    echo -e "${BOLD}${RED}$*${NC}"
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
            echo "  environment    Environment to destroy (dev|staging|prod)"
            echo ""
            echo "Options:"
            echo "  --dry-run, -n  Show what would be destroyed without making changes"
            echo "  --help, -h     Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 dev --dry-run     # Preview destruction"
            echo "  $0 dev               # Actually destroy dev environment"
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

# Configuration
TERRAFORM_DIR="$PROJECT_ROOT/terraform"

header "╔════════════════════════════════════════════════════════════════╗"
if [ "$DRY_RUN" = true ]; then
    header "║       Treza Infrastructure Destruction (DRY-RUN)              ║"
else
    danger "║       Treza Infrastructure Destruction (LIVE MODE)            ║"
fi
header "║       Environment: $(printf '%-44s' "$ENVIRONMENT")║"
header "╚════════════════════════════════════════════════════════════════╝"
echo ""

if [ "$DRY_RUN" = false ]; then
    danger "⚠️  WARNING: This will permanently destroy all infrastructure resources!"
    danger "⚠️  This action cannot be undone!"
    echo ""
fi

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

# Check prerequisites
header "═══════════════════════════════════════════════════════════════"
header "Prerequisites Validation"
header "═══════════════════════════════════════════════════════════════"
echo ""

info "Checking required tools..."
if ! command -v terraform &> /dev/null; then
    error "Terraform is not installed"
    exit 1
fi
success "Terraform found: $(terraform version -json 2>/dev/null | grep -o '"terraform_version":"[^"]*"' | cut -d'"' -f4 || terraform version | head -1)"

if ! command -v aws &> /dev/null; then
    error "AWS CLI is not installed"
    exit 1
fi
success "AWS CLI found: $(aws --version | cut -d' ' -f1 | cut -d'/' -f2)"

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    error "AWS credentials not configured"
    exit 1
fi

AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
AWS_USER=$(aws sts get-caller-identity --query Arn --output text)
AWS_REGION=$(aws configure get region || echo "us-west-2")
success "AWS credentials validated"
echo "  Account: $AWS_ACCOUNT"
echo "  User: $AWS_USER"
echo "  Region: $AWS_REGION"
echo ""

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
header "═══════════════════════════════════════════════════════════════"
header "Terraform Initialization"
header "═══════════════════════════════════════════════════════════════"
echo ""

info "Initializing Terraform..."
if terraform init -backend-config=backend.conf > /dev/null 2>&1; then
    success "Terraform initialized successfully"
else
    error "Failed to initialize Terraform"
    exit 1
fi
echo ""

# Get current resource inventory before generating destruction plan
header "═══════════════════════════════════════════════════════════════"
header "Current Infrastructure Inventory"
header "═══════════════════════════════════════════════════════════════"
echo ""

info "Analyzing deployed resources..."
RESOURCE_COUNT=$(terraform state list 2>/dev/null | wc -l | tr -d ' ')

if [ "$RESOURCE_COUNT" -eq 0 ]; then
    warning "No resources found in Terraform state"
    echo ""
    echo "This could mean:"
    echo "  • No infrastructure is currently deployed"
    echo "  • State file is empty or not accessible"
    echo "  • You're targeting the wrong environment"
    echo ""
    exit 0
fi

success "Found $RESOURCE_COUNT resources in Terraform state"
echo ""

# Count resources by type
info "Resource breakdown:"
terraform state list 2>/dev/null | sed 's/\[.*\]$//' | cut -d'.' -f1-2 | sort | uniq -c | sort -rn | head -10 | while read count resource; do
    echo "  • $count x $resource"
done
echo ""

# Show key resources
info "Key infrastructure components:"
if terraform state list 2>/dev/null | grep -q "aws_vpc\."; then
    VPC_ID=$(terraform output -raw vpc_id 2>/dev/null || echo "N/A")
    echo "  🌐 VPC: $VPC_ID"
fi
if terraform state list 2>/dev/null | grep -q "aws_ecs_cluster\."; then
    ECS_CLUSTER=$(terraform output -raw ecs_cluster_arn 2>/dev/null | xargs basename || echo "N/A")
    echo "  🐳 ECS Cluster: $ECS_CLUSTER"
fi
if terraform state list 2>/dev/null | grep -q "aws_lambda_function\."; then
    LAMBDA_COUNT=$(terraform state list 2>/dev/null | grep -c "aws_lambda_function\." || echo "0")
    echo "  λ  Lambda Functions: $LAMBDA_COUNT"
fi
if terraform state list 2>/dev/null | grep -q "aws_sfn_state_machine\."; then
    SF_COUNT=$(terraform state list 2>/dev/null | grep -c "aws_sfn_state_machine\." || echo "0")
    echo "  🔄 Step Functions: $SF_COUNT"
fi
if terraform state list 2>/dev/null | grep -q "aws_dynamodb_table\."; then
    DDB_COUNT=$(terraform state list 2>/dev/null | grep -c "aws_dynamodb_table\." || echo "0")
    echo "  🗄️  DynamoDB Tables: $DDB_COUNT"
fi
if terraform state list 2>/dev/null | grep -q "aws_cloudwatch_log_group\."; then
    LOG_COUNT=$(terraform state list 2>/dev/null | grep -c "aws_cloudwatch_log_group\." || echo "0")
    echo "  📊 CloudWatch Log Groups: $LOG_COUNT"
fi
echo ""

# Estimated cost savings
header "═══════════════════════════════════════════════════════════════"
header "Estimated Monthly Cost Savings"
header "═══════════════════════════════════════════════════════════════"
echo ""

info "Approximate costs being eliminated:"

# Calculate rough estimates based on resource counts
ECS_COST=0
if terraform state list 2>/dev/null | grep -q "aws_ecs_"; then
    ECS_COST=50
    echo "  • ECS Fargate tasks: ~\$$ECS_COST/month"
fi

LAMBDA_COST=0
LAMBDA_COUNT=$(terraform state list 2>/dev/null | grep -c "aws_lambda_function\." || echo "0")
if [ "$LAMBDA_COUNT" -gt 0 ]; then
    LAMBDA_COST=$((LAMBDA_COUNT * 5))
    echo "  • Lambda functions ($LAMBDA_COUNT): ~\$$LAMBDA_COST/month"
fi

SF_COST=0
if terraform state list 2>/dev/null | grep -q "aws_sfn_state_machine\."; then
    SF_COST=10
    echo "  • Step Functions: ~\$$SF_COST/month"
fi

LOGS_COST=5
if terraform state list 2>/dev/null | grep -q "aws_cloudwatch_log_group\."; then
    echo "  • CloudWatch Logs: ~\$$LOGS_COST/month"
fi

VPC_COST=10
if terraform state list 2>/dev/null | grep -q "aws_vpc\."; then
    echo "  • VPC & Networking: ~\$$VPC_COST/month"
fi

TOTAL_COST=$((ECS_COST + LAMBDA_COST + SF_COST + LOGS_COST + VPC_COST))
echo ""
echo "  ${BOLD}${GREEN}Total Estimated Savings: ~\$$TOTAL_COST/month${NC}"
echo ""
warning "These are rough estimates. Actual costs may vary based on usage patterns."
echo ""

# Show what will be destroyed
header "═══════════════════════════════════════════════════════════════"
header "Generating Destruction Plan"
header "═══════════════════════════════════════════════════════════════"
echo ""

info "Analyzing destruction plan..."
echo ""

if ! terraform plan -destroy -out=destroy.tfplan 2>&1; then
    error "Failed to generate destruction plan"
    echo ""
    echo "This might mean:"
    echo "  • State file is not accessible"
    echo "  • There are configuration issues"
    echo "  • Dependencies exist that need manual intervention"
    echo ""
    exit 1
fi

echo ""
danger "📋 The above shows what will be DESTROYED."
echo ""

# Handle dry-run mode
if [ "$DRY_RUN" = true ]; then
    header "═══════════════════════════════════════════════════════════════"
    warning "DRY-RUN MODE: No resources will be destroyed"
    header "═══════════════════════════════════════════════════════════════"
    echo ""
    
    info "Summary of what would be destroyed:"
    echo "  • Total resources: $RESOURCE_COUNT"
    echo "  • Estimated cost savings: ~\$$TOTAL_COST/month"
    echo ""
    
    success "Dry-run completed successfully!"
    echo ""
    info "To actually destroy these resources, run without --dry-run:"
    echo "  ${CYAN}$0 $ENVIRONMENT${NC}"
    echo ""
    
    # Clean up plan file
    rm -f destroy.tfplan
    exit 0
fi

# Final confirmation for actual destruction
header "═══════════════════════════════════════════════════════════════"
danger "FINAL CONFIRMATION REQUIRED"
header "═══════════════════════════════════════════════════════════════"
echo ""

if [ -t 0 ]; then
    danger "🔴 This will permanently delete all $RESOURCE_COUNT resources!"
    echo ""
    echo "Resources to be destroyed include:"
    echo "  • VPC, subnets, and networking components"
    echo "  • ECS clusters and task definitions"
    echo "  • Lambda functions"
    echo "  • Step Functions"
    echo "  • IAM roles and policies"
    echo "  • CloudWatch logs and monitoring"
    echo ""
    echo "  ${BOLD}Estimated monthly savings: ~\$$TOTAL_COST${NC}"
    echo ""
    danger "⚠️  This action CANNOT be undone!"
    echo ""
    read -p "Are you absolutely sure? Type 'destroy' to confirm: " -r
    echo
    if [[ ! $REPLY == "destroy" ]]; then
        warning "Destruction cancelled - you must type 'destroy' exactly"
        rm -f destroy.tfplan
        exit 0
    fi
    
    # Double confirmation for production
    if [ "$ENVIRONMENT" = "prod" ]; then
        echo ""
        danger "🚨 PRODUCTION ENVIRONMENT DETECTED!"
        echo ""
        read -p "Last chance! Type 'YES' in uppercase to destroy production: " -r
        echo
        if [[ ! $REPLY == "YES" ]]; then
            warning "Production destruction cancelled"
            rm -f destroy.tfplan
            exit 0
        fi
    fi
fi

# Apply the destruction plan
header "═══════════════════════════════════════════════════════════════"
header "Destroying Infrastructure"
header "═══════════════════════════════════════════════════════════════"
echo ""

danger "🔥 Starting destruction process..."
echo ""

if terraform apply destroy.tfplan; then
    echo ""
    header "═══════════════════════════════════════════════════════════════"
    success "🎉 Infrastructure Destruction Completed!"
    header "═══════════════════════════════════════════════════════════════"
    echo ""
    
    # Clean up plan file
    rm -f destroy.tfplan
    
    info "Destruction Summary:"
    echo "  • Resources destroyed: $RESOURCE_COUNT"
    echo "  • Monthly cost savings: ~\$$TOTAL_COST"
    echo "  • Environment: $ENVIRONMENT"
    echo ""
    
    success "What was destroyed:"
    echo "  ✓ All compute resources (ECS, Lambda)"
    echo "  ✓ All networking resources (VPC, subnets, security groups)"
    echo "  ✓ All orchestration resources (Step Functions)"
    echo "  ✓ All monitoring and logging resources"
    echo "  ✓ All IAM roles and policies (managed by Terraform)"
    echo ""
    
    # Optional: Clean up local state cache (but keep backend state for audit)
    if [ -t 0 ]; then
        echo ""
        read -p "Do you want to clean up local Terraform cache? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf .terraform/
            rm -f .terraform.lock.hcl
            rm -f terraform.tfvars
            rm -f backend.conf
            success "Local Terraform cache cleaned"
        fi
    fi
    
    echo ""
    warning "Backend Resources Preserved:"
    echo "  • S3 state bucket (for audit trail)"
    echo "  • DynamoDB locks table"
    echo ""
    echo "These can be removed with:"
    echo "  ${CYAN}# Be careful - this deletes state history!${NC}"
    echo "  ${CYAN}aws s3 rb s3://\$(grep bucket environments/backend-$ENVIRONMENT.conf | cut -d'\"' -f2) --force${NC}"
    echo "  ${CYAN}aws dynamodb delete-table --table-name \$(grep dynamodb_table environments/backend-$ENVIRONMENT.conf | cut -d'\"' -f2)${NC}"
    echo ""
    
    success "Destruction completed successfully! 🚀"
    echo ""
else
    echo ""
    header "═══════════════════════════════════════════════════════════════"
    error "Infrastructure Destruction Failed!"
    header "═══════════════════════════════════════════════════════════════"
    echo ""
    
    warning "Possible causes:"
    echo "  • Resource dependencies preventing deletion"
    echo "  • Insufficient IAM permissions"
    echo "  • Resources modified outside of Terraform"
    echo "  • Network connectivity issues"
    echo ""
    
    info "Troubleshooting steps:"
    echo "  1. Check the error messages above for specific resources"
    echo "  2. Review AWS Console for manual changes or dependencies"
    echo "  3. Use: ${CYAN}terraform state list${NC} to see remaining resources"
    echo "  4. Try: ${CYAN}terraform destroy -target=<resource>${NC} for specific resources"
    echo "  5. Re-run: ${CYAN}$0 $ENVIRONMENT${NC} to retry"
    echo ""
    
    exit 1
fi




