#!/bin/bash
# Smoke Test Script
# Quick validation that infrastructure is operational

set -euo pipefail

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script directory
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration
ENVIRONMENT="${1:-dev}"
PROJECT_NAME="${PROJECT_NAME:-treza}"
AWS_REGION="${AWS_REGION:-us-west-2}"
VERBOSE=false

# Test results
declare -a PASSED_TESTS=()
declare -a FAILED_TESTS=()
declare -a WARNING_TESTS=()

usage() {
    cat << EOF
${BLUE}Infrastructure Smoke Test${NC}

Usage: $0 [environment] [options]

Arguments:
    environment    Environment to test (dev, staging, prod) - default: dev

Options:
    -v, --verbose  Verbose output
    -h, --help     Show this help message

Examples:
    $0 dev
    $0 prod --verbose

EOF
    exit 0
}

log_test() {
    local test_name="$1"
    local status="$2"
    local message="${3:-}"
    
    case "$status" in
        PASS)
            PASSED_TESTS+=("$test_name")
            echo -e "${GREEN}✓${NC} ${test_name}"
            ;;
        FAIL)
            FAILED_TESTS+=("$test_name")
            echo -e "${RED}✗${NC} ${test_name}"
            [ -n "$message" ] && echo -e "  ${RED}→${NC} $message"
            ;;
        WARN)
            WARNING_TESTS+=("$test_name")
            echo -e "${YELLOW}⚠${NC} ${test_name}"
            [ -n "$message" ] && echo -e "  ${YELLOW}→${NC} $message"
            ;;
    esac
}

test_aws_connectivity() {
    echo -e "\n${BLUE}═══ Testing AWS Connectivity ═══${NC}"
    
    if aws sts get-caller-identity &>/dev/null; then
        log_test "AWS Credentials" "PASS"
    else
        log_test "AWS Credentials" "FAIL" "Cannot authenticate with AWS"
        return 1
    fi
    
    local account_id=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
    if [ -n "$account_id" ]; then
        log_test "AWS Account ID: $account_id" "PASS"
    fi
}

test_vpc() {
    echo -e "\n${BLUE}═══ Testing VPC Infrastructure ═══${NC}"
    
    local vpc_id=$(aws ec2 describe-vpcs \
        --filters "Name=tag:Environment,Values=${ENVIRONMENT}" \
                  "Name=tag:Project,Values=${PROJECT_NAME}" \
        --query 'Vpcs[0].VpcId' \
        --output text \
        --region "${AWS_REGION}" 2>/dev/null)
    
    if [ "$vpc_id" != "None" ] && [ -n "$vpc_id" ]; then
        log_test "VPC Exists: $vpc_id" "PASS"
        
        # Test subnets
        local subnet_count=$(aws ec2 describe-subnets \
            --filters "Name=vpc-id,Values=${vpc_id}" \
            --query 'length(Subnets)' \
            --output text \
            --region "${AWS_REGION}" 2>/dev/null)
        
        if [ "$subnet_count" -ge 4 ]; then
            log_test "Subnets: $subnet_count found" "PASS"
        else
            log_test "Subnets: $subnet_count found" "WARN" "Expected at least 4 subnets"
        fi
        
        # Test NAT Gateways
        local nat_count=$(aws ec2 describe-nat-gateways \
            --filter "Name=vpc-id,Values=${vpc_id}" "Name=state,Values=available" \
            --query 'length(NatGateways)' \
            --output text \
            --region "${AWS_REGION}" 2>/dev/null)
        
        if [ "$nat_count" -ge 1 ]; then
            log_test "NAT Gateways: $nat_count active" "PASS"
        else
            log_test "NAT Gateways" "FAIL" "No active NAT gateways found"
        fi
        
        # Test VPC Endpoints
        local endpoint_count=$(aws ec2 describe-vpc-endpoints \
            --filters "Name=vpc-id,Values=${vpc_id}" \
            --query 'length(VpcEndpoints)' \
            --output text \
            --region "${AWS_REGION}" 2>/dev/null)
        
        if [ "$endpoint_count" -ge 3 ]; then
            log_test "VPC Endpoints: $endpoint_count configured" "PASS"
        else
            log_test "VPC Endpoints: $endpoint_count configured" "WARN" "Expected at least 3 endpoints"
        fi
    else
        log_test "VPC" "FAIL" "VPC not found for environment: ${ENVIRONMENT}"
    fi
}

test_ecs() {
    echo -e "\n${BLUE}═══ Testing ECS Infrastructure ═══${NC}"
    
    local cluster_name="${PROJECT_NAME}-${ENVIRONMENT}"
    
    local cluster_status=$(aws ecs describe-clusters \
        --clusters "${cluster_name}" \
        --query 'clusters[0].status' \
        --output text \
        --region "${AWS_REGION}" 2>/dev/null)
    
    if [ "$cluster_status" = "ACTIVE" ]; then
        log_test "ECS Cluster: $cluster_name" "PASS"
        
        # Check task definitions
        local task_family="${PROJECT_NAME}-${ENVIRONMENT}-terraform-runner"
        local task_status=$(aws ecs describe-task-definition \
            --task-definition "${task_family}" \
            --query 'taskDefinition.status' \
            --output text \
            --region "${AWS_REGION}" 2>/dev/null)
        
        if [ "$task_status" = "ACTIVE" ]; then
            log_test "Task Definition: $task_family" "PASS"
        else
            log_test "Task Definition: $task_family" "WARN" "Status: $task_status"
        fi
    else
        log_test "ECS Cluster: $cluster_name" "FAIL" "Cluster not active or not found"
    fi
}

test_lambda_functions() {
    echo -e "\n${BLUE}═══ Testing Lambda Functions ═══${NC}"
    
    local functions=(
        "${PROJECT_NAME}-${ENVIRONMENT}-enclave-trigger"
        "${PROJECT_NAME}-${ENVIRONMENT}-validation"
        "${PROJECT_NAME}-${ENVIRONMENT}-error-handler"
    )
    
    for func_name in "${functions[@]}"; do
        local state=$(aws lambda get-function \
            --function-name "${func_name}" \
            --query 'Configuration.State' \
            --output text \
            --region "${AWS_REGION}" 2>/dev/null)
        
        if [ "$state" = "Active" ]; then
            log_test "Lambda: ${func_name##*-}" "PASS"
        elif [ "$state" = "None" ]; then
            log_test "Lambda: ${func_name##*-}" "FAIL" "Function not found"
        else
            log_test "Lambda: ${func_name##*-}" "WARN" "State: $state"
        fi
    done
}

test_step_functions() {
    echo -e "\n${BLUE}═══ Testing Step Functions ═══${NC}"
    
    local state_machines=$(aws stepfunctions list-state-machines \
        --query "stateMachines[?contains(name, '${PROJECT_NAME}-${ENVIRONMENT}')]" \
        --output json \
        --region "${AWS_REGION}" 2>/dev/null)
    
    local count=$(echo "$state_machines" | jq -r 'length')
    
    if [ "$count" -ge 2 ]; then
        log_test "State Machines: $count found" "PASS"
        
        # Check individual state machines
        echo "$state_machines" | jq -r '.[].name' | while read -r sm_name; do
            if [ -n "$sm_name" ]; then
                log_test "  ${sm_name##*-}" "PASS"
            fi
        done
    else
        log_test "State Machines" "WARN" "Expected at least 2 state machines, found $count"
    fi
}

test_cloudwatch() {
    echo -e "\n${BLUE}═══ Testing CloudWatch ═══${NC}"
    
    # Test log groups
    local log_group_prefix="/aws/lambda/${PROJECT_NAME}-${ENVIRONMENT}"
    local log_groups=$(aws logs describe-log-groups \
        --log-group-name-prefix "${log_group_prefix}" \
        --query 'length(logGroups)' \
        --output text \
        --region "${AWS_REGION}" 2>/dev/null)
    
    if [ "$log_groups" -gt 0 ]; then
        log_test "CloudWatch Log Groups: $log_groups" "PASS"
    else
        log_test "CloudWatch Log Groups" "WARN" "No log groups found"
    fi
    
    # Test dashboard
    local dashboard_name="${PROJECT_NAME}-${ENVIRONMENT}"
    if aws cloudwatch get-dashboard \
        --dashboard-name "${dashboard_name}" \
        --region "${AWS_REGION}" &>/dev/null; then
        log_test "CloudWatch Dashboard: $dashboard_name" "PASS"
    else
        log_test "CloudWatch Dashboard" "WARN" "Dashboard not found (optional)"
    fi
}

test_dynamodb() {
    echo -e "\n${BLUE}═══ Testing DynamoDB ═══${NC}"
    
    # Test state lock table
    local lock_table="${PROJECT_NAME}-terraform-locks-${ENVIRONMENT}"
    local table_status=$(aws dynamodb describe-table \
        --table-name "${lock_table}" \
        --query 'Table.TableStatus' \
        --output text \
        --region "${AWS_REGION}" 2>/dev/null)
    
    if [ "$table_status" = "ACTIVE" ]; then
        log_test "State Lock Table: $lock_table" "PASS"
    else
        log_test "State Lock Table" "WARN" "Table may have different naming"
    fi
}

test_s3_backend() {
    echo -e "\n${BLUE}═══ Testing S3 Backend ═══${NC}"
    
    local bucket_name="${PROJECT_NAME}-terraform-state-${ENVIRONMENT}"
    
    if aws s3api head-bucket --bucket "${bucket_name}" 2>/dev/null; then
        log_test "S3 Bucket: $bucket_name" "PASS"
        
        # Check versioning
        local versioning=$(aws s3api get-bucket-versioning \
            --bucket "${bucket_name}" \
            --query 'Status' \
            --output text 2>/dev/null)
        
        if [ "$versioning" = "Enabled" ]; then
            log_test "  Versioning" "PASS"
        else
            log_test "  Versioning" "WARN" "Not enabled"
        fi
        
        # Check encryption
        if aws s3api get-bucket-encryption --bucket "${bucket_name}" &>/dev/null; then
            log_test "  Encryption" "PASS"
        else
            log_test "  Encryption" "WARN" "Not configured"
        fi
    else
        log_test "S3 Bucket" "FAIL" "Bucket not found: $bucket_name"
    fi
}

test_iam_roles() {
    echo -e "\n${BLUE}═══ Testing IAM Roles ═══${NC}"
    
    local roles=(
        "${PROJECT_NAME}-${ENVIRONMENT}-lambda-execution"
        "${PROJECT_NAME}-${ENVIRONMENT}-ecs-task"
        "${PROJECT_NAME}-${ENVIRONMENT}-ecs-execution"
    )
    
    for role_name in "${roles[@]}"; do
        if aws iam get-role --role-name "${role_name}" &>/dev/null; then
            log_test "IAM Role: ${role_name##*-}" "PASS"
        else
            log_test "IAM Role: ${role_name##*-}" "WARN" "Role may have different naming"
        fi
    done
}

test_quick_smoke() {
    echo -e "\n${BLUE}═══ Running Quick Smoke Tests ═══${NC}"
    
    # Quick critical checks
    test_aws_connectivity || return 1
    test_vpc
    test_ecs
    test_lambda_functions
}

test_comprehensive() {
    echo -e "\n${BLUE}═══ Running Comprehensive Tests ═══${NC}"
    
    test_aws_connectivity || return 1
    test_vpc
    test_ecs
    test_lambda_functions
    test_step_functions
    test_cloudwatch
    test_dynamodb
    test_s3_backend
    test_iam_roles
}

print_summary() {
    local total=$((${#PASSED_TESTS[@]} + ${#FAILED_TESTS[@]} + ${#WARNING_TESTS[@]}))
    
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
    echo -e "${BLUE}             Smoke Test Summary                ${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
    echo ""
    echo -e "Environment:  ${BLUE}${ENVIRONMENT}${NC}"
    echo -e "Region:       ${BLUE}${AWS_REGION}${NC}"
    echo -e "Project:      ${BLUE}${PROJECT_NAME}${NC}"
    echo ""
    echo -e "${GREEN}Passed:${NC}       ${#PASSED_TESTS[@]}"
    echo -e "${RED}Failed:${NC}       ${#FAILED_TESTS[@]}"
    echo -e "${YELLOW}Warnings:${NC}     ${#WARNING_TESTS[@]}"
    echo -e "━━━━━━━━━━━━━━"
    echo -e "Total:        $total"
    echo ""
    
    if [ ${#FAILED_TESTS[@]} -eq 0 ]; then
        echo -e "${GREEN}✓ Infrastructure is operational${NC}"
        echo ""
        return 0
    else
        echo -e "${RED}✗ Infrastructure has issues${NC}"
        echo ""
        echo -e "${RED}Failed Tests:${NC}"
        for test in "${FAILED_TESTS[@]}"; do
            echo -e "  - $test"
        done
        echo ""
        return 1
    fi
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--verbose)
            VERBOSE=true
            set -x
            shift
            ;;
        -h|--help)
            usage
            ;;
        dev|staging|prod)
            ENVIRONMENT="$1"
            shift
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Main execution
main() {
    echo -e "${BLUE}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║     Treza Infrastructure Smoke Test           ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}"
    
    test_comprehensive
    
    print_summary
}

main

