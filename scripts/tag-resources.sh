#!/bin/bash
# Resource Tagging Automation Script
# Ensures all resources have required tags for governance and cost tracking

set -euo pipefail

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Configuration
ENVIRONMENT="${1:-dev}"
PROJECT_NAME="${PROJECT_NAME:-treza}"
AWS_REGION="${AWS_REGION:-us-west-2}"
DRY_RUN=false
FORCE=false

# Required tags
declare -A REQUIRED_TAGS=(
    ["Environment"]="$ENVIRONMENT"
    ["Project"]="$PROJECT_NAME"
    ["ManagedBy"]="Terraform"
)

# Optional tags
declare -A OPTIONAL_TAGS=(
    ["Team"]="Infrastructure"
    ["CostCenter"]="Engineering"
)

usage() {
    cat << EOF
${BLUE}Resource Tagging Automation${NC}

Usage: $0 [environment] [options]

Arguments:
    environment         Environment to tag (dev, staging, prod)

Options:
    --dry-run           Show what would be tagged
    --force             Force tag updates (overwrites existing)
    -h, --help          Show this help message

Examples:
    $0 dev
    $0 prod --dry-run
    $0 staging --force

Tags resources:
  - EC2 instances
  - ECS clusters and services
  - Lambda functions
  - S3 buckets
  - DynamoDB tables
  - Security groups
  - VPCs
  - IAM roles

EOF
    exit 0
}

error() {
    echo -e "${RED}Error: $*${NC}" >&2
}

success() {
    echo -e "${GREEN}✓ $*${NC}"
}

info() {
    echo -e "${BLUE}→ $*${NC}"
}

warning() {
    echo -e "${YELLOW}⚠ $*${NC}"
}

# Tag EC2 instances
tag_ec2_instances() {
    info "Tagging EC2 instances..."
    
    local instances=$(aws ec2 describe-instances \
        --filters "Name=tag:Project,Values=${PROJECT_NAME}" \
        --query 'Reservations[].Instances[].InstanceId' \
        --output text 2>/dev/null)
    
    local count=0
    for instance_id in $instances; do
        if [ -n "$instance_id" ]; then
            if [ "$DRY_RUN" = true ]; then
                info "Would tag instance: $instance_id"
            else
                local tags=""
                for tag_key in "${!REQUIRED_TAGS[@]}"; do
                    tags="$tags Key=$tag_key,Value=${REQUIRED_TAGS[$tag_key]}"
                done
                
                aws ec2 create-tags \
                    --resources "$instance_id" \
                    --tags $tags &>/dev/null
                success "Tagged instance: $instance_id"
            fi
            count=$((count + 1))
        fi
    done
    
    echo "  Tagged $count instances"
}

# Tag Lambda functions
tag_lambda_functions() {
    info "Tagging Lambda functions..."
    
    local functions=$(aws lambda list-functions \
        --query "Functions[?starts_with(FunctionName, '${PROJECT_NAME}')].FunctionName" \
        --output text 2>/dev/null)
    
    local count=0
    for func_name in $functions; do
        if [ -n "$func_name" ]; then
            if [ "$DRY_RUN" = true ]; then
                info "Would tag function: $func_name"
            else
                local tags_json="{"
                local first=true
                for tag_key in "${!REQUIRED_TAGS[@]}"; do
                    if [ "$first" = false ]; then
                        tags_json="$tags_json,"
                    fi
                    tags_json="$tags_json\"$tag_key\":\"${REQUIRED_TAGS[$tag_key]}\""
                    first=false
                done
                tags_json="$tags_json}"
                
                local func_arn=$(aws lambda get-function \
                    --function-name "$func_name" \
                    --query 'Configuration.FunctionArn' \
                    --output text 2>/dev/null)
                
                aws lambda tag-resource \
                    --resource "$func_arn" \
                    --tags "$tags_json" &>/dev/null || true
                success "Tagged function: $func_name"
            fi
            count=$((count + 1))
        fi
    done
    
    echo "  Tagged $count Lambda functions"
}

# Tag S3 buckets
tag_s3_buckets() {
    info "Tagging S3 buckets..."
    
    local buckets=$(aws s3api list-buckets \
        --query "Buckets[?contains(Name, '${PROJECT_NAME}')].Name" \
        --output text 2>/dev/null)
    
    local count=0
    for bucket in $buckets; do
        if [ -n "$bucket" ]; then
            if [ "$DRY_RUN" = true ]; then
                info "Would tag bucket: $bucket"
            else
                local tags="TagSet=["
                local first=true
                for tag_key in "${!REQUIRED_TAGS[@]}"; do
                    if [ "$first" = false ]; then
                        tags="$tags,"
                    fi
                    tags="$tags{Key=$tag_key,Value=${REQUIRED_TAGS[$tag_key]}}"
                    first=false
                done
                tags="$tags]"
                
                aws s3api put-bucket-tagging \
                    --bucket "$bucket" \
                    --tagging "$tags" &>/dev/null || true
                success "Tagged bucket: $bucket"
            fi
            count=$((count + 1))
        fi
    done
    
    echo "  Tagged $count S3 buckets"
}

# Tag DynamoDB tables
tag_dynamodb_tables() {
    info "Tagging DynamoDB tables..."
    
    local tables=$(aws dynamodb list-tables \
        --query "TableNames[?contains(@, '${PROJECT_NAME}')]" \
        --output text 2>/dev/null)
    
    local count=0
    for table in $tables; do
        if [ -n "$table" ]; then
            if [ "$DRY_RUN" = true ]; then
                info "Would tag table: $table"
            else
                local table_arn=$(aws dynamodb describe-table \
                    --table-name "$table" \
                    --query 'Table.TableArn' \
                    --output text 2>/dev/null)
                
                local tags=""
                for tag_key in "${!REQUIRED_TAGS[@]}"; do
                    tags="$tags Key=$tag_key,Value=${REQUIRED_TAGS[$tag_key]}"
                done
                
                aws dynamodb tag-resource \
                    --resource-arn "$table_arn" \
                    --tags $tags &>/dev/null || true
                success "Tagged table: $table"
            fi
            count=$((count + 1))
        fi
    done
    
    echo "  Tagged $count DynamoDB tables"
}

# Tag ECS resources
tag_ecs_resources() {
    info "Tagging ECS resources..."
    
    local cluster_name="${PROJECT_NAME}-${ENVIRONMENT}"
    local cluster_arn=$(aws ecs describe-clusters \
        --clusters "$cluster_name" \
        --query 'clusters[0].clusterArn' \
        --output text 2>/dev/null)
    
    if [ "$cluster_arn" != "None" ] && [ -n "$cluster_arn" ]; then
        if [ "$DRY_RUN" = true ]; then
            info "Would tag ECS cluster: $cluster_name"
        else
            local tags=""
            for tag_key in "${!REQUIRED_TAGS[@]}"; do
                tags="$tags key=$tag_key,value=${REQUIRED_TAGS[$tag_key]}"
            done
            
            aws ecs tag-resource \
                --resource-arn "$cluster_arn" \
                --tags $tags &>/dev/null || true
            success "Tagged ECS cluster: $cluster_name"
        fi
    fi
}

# Tag VPC resources
tag_vpc_resources() {
    info "Tagging VPC resources..."
    
    local vpcs=$(aws ec2 describe-vpcs \
        --filters "Name=tag:Project,Values=${PROJECT_NAME}" \
        --query 'Vpcs[].VpcId' \
        --output text 2>/dev/null)
    
    local count=0
    for vpc_id in $vpcs; do
        if [ -n "$vpc_id" ]; then
            if [ "$DRY_RUN" = true ]; then
                info "Would tag VPC: $vpc_id"
            else
                local tags=""
                for tag_key in "${!REQUIRED_TAGS[@]}"; do
                    tags="$tags Key=$tag_key,Value=${REQUIRED_TAGS[$tag_key]}"
                done
                
                aws ec2 create-tags \
                    --resources "$vpc_id" \
                    --tags $tags &>/dev/null
                success "Tagged VPC: $vpc_id"
            fi
            count=$((count + 1))
        fi
    done
    
    echo "  Tagged $count VPCs"
}

# Tag security groups
tag_security_groups() {
    info "Tagging security groups..."
    
    local vpcs=$(aws ec2 describe-vpcs \
        --filters "Name=tag:Project,Values=${PROJECT_NAME}" \
        --query 'Vpcs[0].VpcId' \
        --output text 2>/dev/null)
    
    if [ "$vpcs" != "None" ] && [ -n "$vpcs" ]; then
        local sgs=$(aws ec2 describe-security-groups \
            --filters "Name=vpc-id,Values=${vpcs}" \
            --query 'SecurityGroups[].GroupId' \
            --output text 2>/dev/null)
        
        local count=0
        for sg_id in $sgs; do
            if [ -n "$sg_id" ]; then
                if [ "$DRY_RUN" = true ]; then
                    info "Would tag security group: $sg_id"
                else
                    local tags=""
                    for tag_key in "${!REQUIRED_TAGS[@]}"; do
                        tags="$tags Key=$tag_key,Value=${REQUIRED_TAGS[$tag_key]}"
                    done
                    
                    aws ec2 create-tags \
                        --resources "$sg_id" \
                        --tags $tags &>/dev/null
                    success "Tagged security group: $sg_id"
                fi
                count=$((count + 1))
            fi
        done
        
        echo "  Tagged $count security groups"
    fi
}

# Verify tags
verify_tags() {
    info "Verifying tags..."
    
    local untagged=0
    
    # Check EC2
    local instances=$(aws ec2 describe-instances \
        --filters "Name=tag:Project,Values=${PROJECT_NAME}" \
        --query 'Reservations[].Instances[].[InstanceId,Tags[?Key==`Environment`].Value|[0]]' \
        --output text 2>/dev/null)
    
    while read -r instance_id env_tag; do
        if [ -z "$env_tag" ] || [ "$env_tag" = "None" ]; then
            warning "Instance $instance_id missing Environment tag"
            untagged=$((untagged + 1))
        fi
    done <<< "$instances"
    
    if [ $untagged -eq 0 ]; then
        success "All resources properly tagged"
    else
        warning "$untagged resources still missing tags"
    fi
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        dev|staging|prod)
            ENVIRONMENT="$1"
            REQUIRED_TAGS["Environment"]="$1"
            shift
            ;;
        *)
            error "Unknown option: $1"
            usage
            ;;
    esac
done

# Main execution
main() {
    echo -e "${BLUE}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║     Resource Tagging Automation               ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "Environment: ${BLUE}${ENVIRONMENT}${NC}"
    echo -e "Project:     ${BLUE}${PROJECT_NAME}${NC}"
    if [ "$DRY_RUN" = true ]; then
        echo -e "Mode:        ${YELLOW}DRY RUN${NC}"
    fi
    echo ""
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &>/dev/null; then
        error "AWS credentials not configured"
        exit 1
    fi
    
    # Apply tags
    tag_ec2_instances
    tag_lambda_functions
    tag_s3_buckets
    tag_dynamodb_tables
    tag_ecs_resources
    tag_vpc_resources
    tag_security_groups
    
    # Verify
    verify_tags
    
    echo ""
    echo -e "${GREEN}════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}Tagging completed${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════${NC}"
}

main

