#!/bin/bash
# Backup Script for Critical Infrastructure Resources
# Creates backups of Terraform state, configurations, and AWS resources

set -euo pipefail

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly BACKUP_DIR="${PROJECT_ROOT}/backups"
readonly TIMESTAMP=$(date +%Y%m%d_%H%M%S)

ENVIRONMENT="${1:-dev}"
PROJECT_NAME="${PROJECT_NAME:-treza}"
AWS_REGION="${AWS_REGION:-us-west-2}"
BACKUP_BUCKET=""
DRY_RUN=false

usage() {
    cat << EOF
${BLUE}Infrastructure Backup Script${NC}

Usage: $0 [environment] [options]

Arguments:
    environment         Environment to backup (dev, staging, prod)

Options:
    -b, --bucket <name> S3 bucket for backup storage
    --dry-run           Show what would be backed up
    -h, --help          Show this help message

Examples:
    $0 dev
    $0 prod --bucket my-backup-bucket
    $0 staging --dry-run

Backs up:
  - Terraform state files
  - DynamoDB tables (schemas and data)
  - CloudWatch dashboards
  - Lambda function code
  - Step Function definitions
  - IAM policies

EOF
    exit 0
}

error() {
    echo -e "${RED}Error: $*${NC}" >&2
    exit 1
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

# Create backup directory
prepare_backup_dir() {
    local backup_path="${BACKUP_DIR}/${ENVIRONMENT}/${TIMESTAMP}"
    
    if [ "$DRY_RUN" = false ]; then
        mkdir -p "$backup_path"/{terraform,dynamodb,cloudwatch,lambda,stepfunctions,iam}
    fi
    
    echo "$backup_path"
}

# Backup Terraform state
backup_terraform_state() {
    local backup_path="$1"
    info "Backing up Terraform state..."
    
    local bucket="${PROJECT_NAME}-terraform-state-${ENVIRONMENT}"
    local key="${ENVIRONMENT}/terraform.tfstate"
    
    if [ "$DRY_RUN" = false ]; then
        if aws s3 cp "s3://${bucket}/${key}" \
            "${backup_path}/terraform/terraform.tfstate" 2>/dev/null; then
            success "Terraform state backed up"
            
            # Also get state versions
            aws s3api list-object-versions \
                --bucket "${bucket}" \
                --prefix "${key}" \
                --output json > "${backup_path}/terraform/state-versions.json"
        else
            warning "Could not backup Terraform state"
        fi
    else
        info "Would backup: s3://${bucket}/${key}"
    fi
}

# Backup DynamoDB tables
backup_dynamodb() {
    local backup_path="$1"
    info "Backing up DynamoDB tables..."
    
    local tables=$(aws dynamodb list-tables \
        --query "TableNames[?contains(@, '${PROJECT_NAME}') && contains(@, '${ENVIRONMENT}')]" \
        --output json 2>/dev/null)
    
    echo "$tables" | jq -r '.[]' | while read -r table_name; do
        if [ -n "$table_name" ]; then
            info "  Backing up table: $table_name"
            
            if [ "$DRY_RUN" = false ]; then
                # Backup table schema
                aws dynamodb describe-table \
                    --table-name "$table_name" \
                    --output json > "${backup_path}/dynamodb/${table_name}-schema.json"
                
                # Create on-demand backup
                local backup_name="${table_name}-${TIMESTAMP}"
                aws dynamodb create-backup \
                    --table-name "$table_name" \
                    --backup-name "$backup_name" \
                    --region "${AWS_REGION}" &>/dev/null && \
                    success "  Table backup created: $backup_name" || \
                    warning "  Could not create backup for $table_name"
            fi
        fi
    done
}

# Backup Lambda functions
backup_lambda_functions() {
    local backup_path="$1"
    info "Backing up Lambda functions..."
    
    local functions=$(aws lambda list-functions \
        --query "Functions[?starts_with(FunctionName, '${PROJECT_NAME}-${ENVIRONMENT}')]" \
        --output json 2>/dev/null)
    
    echo "$functions" | jq -r '.[].FunctionName' | while read -r func_name; do
        if [ -n "$func_name" ]; then
            info "  Backing up: $func_name"
            
            if [ "$DRY_RUN" = false ]; then
                # Get function configuration
                aws lambda get-function-configuration \
                    --function-name "$func_name" \
                    --output json > "${backup_path}/lambda/${func_name}-config.json"
                
                # Get function code URL
                local code_location=$(aws lambda get-function \
                    --function-name "$func_name" \
                    --query 'Code.Location' \
                    --output text)
                
                # Download function code
                if [ -n "$code_location" ]; then
                    curl -s "$code_location" -o "${backup_path}/lambda/${func_name}-code.zip"
                    success "  Function backed up: $func_name"
                fi
            fi
        fi
    done
}

# Backup Step Functions
backup_step_functions() {
    local backup_path="$1"
    info "Backing up Step Functions..."
    
    local state_machines=$(aws stepfunctions list-state-machines \
        --query "stateMachines[?contains(name, '${PROJECT_NAME}-${ENVIRONMENT}')]" \
        --output json 2>/dev/null)
    
    echo "$state_machines" | jq -r '.[].stateMachineArn' | while read -r sm_arn; do
        if [ -n "$sm_arn" ]; then
            local sm_name=$(echo "$sm_arn" | awk -F: '{print $NF}')
            info "  Backing up: $sm_name"
            
            if [ "$DRY_RUN" = false ]; then
                aws stepfunctions describe-state-machine \
                    --state-machine-arn "$sm_arn" \
                    --output json > "${backup_path}/stepfunctions/${sm_name}.json"
                success "  State machine backed up: $sm_name"
            fi
        fi
    done
}

# Backup CloudWatch dashboards
backup_cloudwatch_dashboards() {
    local backup_path="$1"
    info "Backing up CloudWatch dashboards..."
    
    local dashboard_name="${PROJECT_NAME}-${ENVIRONMENT}"
    
    if [ "$DRY_RUN" = false ]; then
        if aws cloudwatch get-dashboard \
            --dashboard-name "$dashboard_name" \
            --output json > "${backup_path}/cloudwatch/${dashboard_name}.json" 2>/dev/null; then
            success "Dashboard backed up: $dashboard_name"
        else
            warning "Dashboard not found: $dashboard_name"
        fi
    else
        info "Would backup dashboard: $dashboard_name"
    fi
}

# Backup IAM policies
backup_iam_policies() {
    local backup_path="$1"
    info "Backing up IAM policies..."
    
    local roles=$(aws iam list-roles \
        --query "Roles[?contains(RoleName, '${PROJECT_NAME}-${ENVIRONMENT}')]" \
        --output json 2>/dev/null)
    
    echo "$roles" | jq -r '.[].RoleName' | while read -r role_name; do
        if [ -n "$role_name" ]; then
            info "  Backing up role: $role_name"
            
            if [ "$DRY_RUN" = false ]; then
                # Get role details
                aws iam get-role \
                    --role-name "$role_name" \
                    --output json > "${backup_path}/iam/${role_name}-role.json"
                
                # Get attached policies
                aws iam list-attached-role-policies \
                    --role-name "$role_name" \
                    --output json > "${backup_path}/iam/${role_name}-policies.json"
                
                # Get inline policies
                aws iam list-role-policies \
                    --role-name "$role_name" \
                    --output json > "${backup_path}/iam/${role_name}-inline-policies.json"
                
                success "  Role backed up: $role_name"
            fi
        fi
    done
}

# Upload to S3
upload_to_s3() {
    local backup_path="$1"
    
    if [ -z "$BACKUP_BUCKET" ]; then
        info "No backup bucket specified, skipping S3 upload"
        return
    fi
    
    info "Uploading backup to S3..."
    
    if [ "$DRY_RUN" = false ]; then
        local s3_path="s3://${BACKUP_BUCKET}/backups/${ENVIRONMENT}/${TIMESTAMP}/"
        
        if aws s3 sync "$backup_path" "$s3_path" --quiet; then
            success "Backup uploaded to $s3_path"
        else
            warning "Could not upload backup to S3"
        fi
    else
        info "Would upload to: s3://${BACKUP_BUCKET}/backups/${ENVIRONMENT}/${TIMESTAMP}/"
    fi
}

# Create backup manifest
create_manifest() {
    local backup_path="$1"
    
    if [ "$DRY_RUN" = false ]; then
        cat > "${backup_path}/manifest.json" <<EOF
{
  "timestamp": "${TIMESTAMP}",
  "environment": "${ENVIRONMENT}",
  "project": "${PROJECT_NAME}",
  "region": "${AWS_REGION}",
  "backup_path": "${backup_path}",
  "created_by": "$(whoami)",
  "aws_account": "$(aws sts get-caller-identity --query Account --output text)"
}
EOF
        success "Backup manifest created"
    fi
}

# Compress backup
compress_backup() {
    local backup_path="$1"
    
    if [ "$DRY_RUN" = false ]; then
        info "Compressing backup..."
        local archive_name="backup-${ENVIRONMENT}-${TIMESTAMP}.tar.gz"
        
        tar -czf "${BACKUP_DIR}/${archive_name}" -C "$(dirname "$backup_path")" "$(basename "$backup_path")"
        
        local size=$(du -h "${BACKUP_DIR}/${archive_name}" | cut -f1)
        success "Backup compressed: $archive_name ($size)"
    fi
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -b|--bucket)
            BACKUP_BUCKET="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
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
            error "Unknown option: $1"
            ;;
    esac
done

# Main execution
main() {
    echo -e "${BLUE}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║     Infrastructure Backup                     ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "Environment: ${BLUE}${ENVIRONMENT}${NC}"
    echo -e "Region:      ${BLUE}${AWS_REGION}${NC}"
    echo -e "Timestamp:   ${BLUE}${TIMESTAMP}${NC}"
    if [ "$DRY_RUN" = true ]; then
        echo -e "Mode:        ${YELLOW}DRY RUN${NC}"
    fi
    echo ""
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &>/dev/null; then
        error "AWS credentials not configured"
    fi
    
    # Create backup directory
    local backup_path=$(prepare_backup_dir)
    
    # Run backup tasks
    backup_terraform_state "$backup_path"
    backup_dynamodb "$backup_path"
    backup_lambda_functions "$backup_path"
    backup_step_functions "$backup_path"
    backup_cloudwatch_dashboards "$backup_path"
    backup_iam_policies "$backup_path"
    
    # Create manifest
    create_manifest "$backup_path"
    
    # Compress
    compress_backup "$backup_path"
    
    # Upload to S3
    upload_to_s3 "$backup_path"
    
    echo ""
    echo -e "${GREEN}════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}Backup completed successfully!${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "Backup location: ${BLUE}${backup_path}${NC}"
    if [ -f "${BACKUP_DIR}/backup-${ENVIRONMENT}-${TIMESTAMP}.tar.gz" ]; then
        echo -e "Archive:         ${BLUE}backup-${ENVIRONMENT}-${TIMESTAMP}.tar.gz${NC}"
    fi
    echo ""
}

main

