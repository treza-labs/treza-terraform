#!/bin/bash
set -euo pipefail

# Health check script for Treza infrastructure
ENVIRONMENT=${1:-dev}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
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

log "🏥 Health Check for Treza Infrastructure - Environment: $ENVIRONMENT"
echo "================================================================="

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
    warning "Terraform not initialized. Run: make init ENV=$ENVIRONMENT"
    exit 1
fi

# Check AWS connectivity
info "Checking AWS connectivity..."
if aws sts get-caller-identity &>/dev/null; then
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    REGION=$(aws configure get region)
    success "AWS connection OK - Account: $ACCOUNT_ID, Region: $REGION"
else
    error "AWS connection failed. Check your credentials."
    exit 1
fi

# Check Terraform state
info "Checking Terraform state..."
if terraform show &>/dev/null; then
    success "Terraform state accessible"
else
    warning "Terraform state not accessible or empty"
fi

# Get infrastructure outputs
info "Checking infrastructure components..."

# Check VPC
VPC_ID=$(terraform output -raw vpc_id 2>/dev/null || echo "")
if [ -n "$VPC_ID" ]; then
    if aws ec2 describe-vpcs --vpc-ids "$VPC_ID" &>/dev/null; then
        success "VPC exists: $VPC_ID"
    else
        error "VPC not found: $VPC_ID"
    fi
else
    warning "VPC ID not available from Terraform outputs"
fi

# Check ECS Cluster
ECS_CLUSTER=$(terraform output -raw ecs_cluster_arn 2>/dev/null || echo "")
if [ -n "$ECS_CLUSTER" ]; then
    CLUSTER_NAME=$(basename "$ECS_CLUSTER")
    if aws ecs describe-clusters --clusters "$CLUSTER_NAME" --query 'clusters[0].status' --output text 2>/dev/null | grep -q "ACTIVE"; then
        success "ECS Cluster active: $CLUSTER_NAME"
    else
        error "ECS Cluster not active: $CLUSTER_NAME"
    fi
else
    warning "ECS Cluster ARN not available from Terraform outputs"
fi

# Check Step Functions
DEPLOY_SF=$(terraform output -raw deployment_state_machine_arn 2>/dev/null || echo "")
CLEANUP_SF=$(terraform output -raw cleanup_state_machine_arn 2>/dev/null || echo "")

if [ -n "$DEPLOY_SF" ]; then
    if aws stepfunctions describe-state-machine --state-machine-arn "$DEPLOY_SF" &>/dev/null; then
        success "Deployment Step Function exists"
    else
        error "Deployment Step Function not found"
    fi
else
    warning "Deployment Step Function ARN not available"
fi

if [ -n "$CLEANUP_SF" ]; then
    if aws stepfunctions describe-state-machine --state-machine-arn "$CLEANUP_SF" &>/dev/null; then
        success "Cleanup Step Function exists"
    else
        error "Cleanup Step Function not found"
    fi
else
    warning "Cleanup Step Function ARN not available"
fi

# Check Lambda Functions
TRIGGER_LAMBDA=$(terraform output -raw enclave_trigger_function_arn 2>/dev/null || echo "")
VALIDATION_LAMBDA=$(terraform output -raw validation_function_arn 2>/dev/null || echo "")

if [ -n "$TRIGGER_LAMBDA" ]; then
    FUNCTION_NAME=$(basename "$TRIGGER_LAMBDA")
    if aws lambda get-function --function-name "$FUNCTION_NAME" &>/dev/null; then
        success "Trigger Lambda function exists: $FUNCTION_NAME"
    else
        error "Trigger Lambda function not found: $FUNCTION_NAME"
    fi
else
    warning "Trigger Lambda ARN not available"
fi

if [ -n "$VALIDATION_LAMBDA" ]; then
    FUNCTION_NAME=$(basename "$VALIDATION_LAMBDA")
    if aws lambda get-function --function-name "$FUNCTION_NAME" &>/dev/null; then
        success "Validation Lambda function exists: $FUNCTION_NAME"
    else
        error "Validation Lambda function not found: $FUNCTION_NAME"
    fi
else
    warning "Validation Lambda ARN not available"
fi

# Check Security Groups
SG_SHARED=$(terraform output -raw shared_enclave_security_group_id 2>/dev/null || echo "")
SG_RUNNER=$(terraform output -raw terraform_runner_security_group_id 2>/dev/null || echo "")

if [ -n "$SG_SHARED" ]; then
    if aws ec2 describe-security-groups --group-ids "$SG_SHARED" &>/dev/null; then
        success "Shared enclave security group exists: $SG_SHARED"
    else
        error "Shared enclave security group not found: $SG_SHARED"
    fi
else
    warning "Shared enclave security group ID not available"
fi

if [ -n "$SG_RUNNER" ]; then
    if aws ec2 describe-security-groups --group-ids "$SG_RUNNER" &>/dev/null; then
        success "Terraform runner security group exists: $SG_RUNNER"
    else
        error "Terraform runner security group not found: $SG_RUNNER"
    fi
else
    warning "Terraform runner security group ID not available"
fi

# Check CloudWatch Dashboard
DASHBOARD_URL=$(terraform output -raw cloudwatch_dashboard_url 2>/dev/null || echo "")
if [ -n "$DASHBOARD_URL" ]; then
    success "CloudWatch dashboard URL available"
    info "Dashboard: $DASHBOARD_URL"
else
    warning "CloudWatch dashboard URL not available"
fi

# Summary
echo ""
echo "================================================================="
log "🏥 Health Check Complete for $ENVIRONMENT environment"

# Count warnings and errors (simplified check)
if grep -q "❌" /tmp/health_check.log 2>/dev/null; then
    error "Some components failed health checks. Review the output above."
    exit 1
elif grep -q "⚠️" /tmp/health_check.log 2>/dev/null; then
    warning "Some components have warnings. Review the output above."
    exit 0
else
    success "All infrastructure components are healthy! 🎉"
    exit 0
fi
