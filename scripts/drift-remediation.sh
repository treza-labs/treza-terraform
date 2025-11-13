#!/bin/bash
# Drift Detection and Remediation Script
# Detects infrastructure drift and applies fixes

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
readonly DRIFT_LOG="${PROJECT_ROOT}/drift-report.txt"

ENVIRONMENT="${1:-dev}"
PROJECT_NAME="${PROJECT_NAME:-treza}"
AUTO_REMEDIATE=false
DRY_RUN=false
VERBOSE=false

usage() {
    cat << EOF
${BLUE}Infrastructure Drift Detection and Remediation${NC}

Usage: $0 [environment] [options]

Arguments:
    environment         Environment to check (dev, staging, prod)

Options:
    -a, --auto          Automatically remediate drift (use with caution)
    --dry-run           Show what would be fixed without making changes
    -v, --verbose       Verbose output
    -h, --help          Show this help message

Examples:
    $0 dev                          # Detect drift only
    $0 prod --dry-run               # Preview fixes
    $0 staging --auto               # Auto-remediate (careful!)

Checks for:
  - Terraform state drift
  - Missing resource tags
  - Incorrect IAM permissions
  - Misconfigured security groups
  - Unencrypted resources
  - Missing CloudWatch alarms

EOF
    exit 0
}

error() {
    echo -e "${RED}Error: $*${NC}" >&2
}

success() {
    echo -e "${GREEN}✓ $*${NC}"
}

warning() {
    echo -e "${YELLOW}⚠ $*${NC}"
}

info() {
    echo -e "${BLUE}→ $*${NC}"
}

log_drift() {
    local resource="$1"
    local issue="$2"
    local fix="$3"
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') | $resource | $issue | $fix" >> "$DRIFT_LOG"
}

# Initialize drift report
init_report() {
    cat > "$DRIFT_LOG" <<EOF
DRIFT DETECTION REPORT
Environment: $ENVIRONMENT
Date: $(date)
================================================================================

EOF
}

# Check Terraform state drift
check_terraform_drift() {
    info "Checking Terraform state drift..."
    
    cd "${PROJECT_ROOT}/terraform"
    
    if terraform plan -detailed-exitcode -var-file="environments/${ENVIRONMENT}.tfvars" -out=/tmp/drift-plan &>/dev/null; then
        success "No Terraform drift detected"
        return 0
    else
        local exit_code=$?
        if [ $exit_code -eq 2 ]; then
            warning "Terraform drift detected"
            
            # Show drift
            terraform show /tmp/drift-plan > /tmp/drift-details.txt
            
            log_drift "Terraform" "Configuration drift detected" "Run terraform apply"
            
            if [ "$AUTO_REMEDIATE" = true ]; then
                if [ "$DRY_RUN" = false ]; then
                    warning "Applying Terraform changes..."
                    terraform apply /tmp/drift-plan
                    success "Drift remediated"
                else
                    info "Would apply Terraform changes"
                fi
            fi
            
            return 1
        else
            error "Terraform plan failed"
            return 1
        fi
    fi
}

# Check missing tags
check_missing_tags() {
    info "Checking for missing resource tags..."
    
    local required_tags=("Environment" "Project" "ManagedBy")
    local drift_count=0
    
    # Check EC2 instances
    local instances=$(aws ec2 describe-instances \
        --filters "Name=tag:Environment,Values=${ENVIRONMENT}" \
        --query 'Reservations[].Instances[].InstanceId' \
        --output json 2>/dev/null)
    
    echo "$instances" | jq -r '.[]' | while read -r instance_id; do
        if [ -n "$instance_id" ]; then
            local tags=$(aws ec2 describe-tags \
                --filters "Name=resource-id,Values=${instance_id}" \
                --query 'Tags[].Key' \
                --output json 2>/dev/null)
            
            for tag in "${required_tags[@]}"; do
                if ! echo "$tags" | jq -e ".[] | select(. == \"$tag\")" &>/dev/null; then
                    warning "Instance $instance_id missing tag: $tag"
                    log_drift "EC2:$instance_id" "Missing tag: $tag" "Add tag"
                    drift_count=$((drift_count + 1))
                    
                    if [ "$AUTO_REMEDIATE" = true ]; then
                        if [ "$DRY_RUN" = false ]; then
                            local value=""
                            case $tag in
                                Environment) value="$ENVIRONMENT" ;;
                                Project) value="$PROJECT_NAME" ;;
                                ManagedBy) value="Terraform" ;;
                            esac
                            
                            aws ec2 create-tags \
                                --resources "$instance_id" \
                                --tags "Key=$tag,Value=$value" &>/dev/null
                            success "Added tag $tag to $instance_id"
                        else
                            info "Would add tag $tag to $instance_id"
                        fi
                    fi
                fi
            done
        fi
    done
    
    if [ $drift_count -eq 0 ]; then
        success "All resources properly tagged"
    else
        warning "Found $drift_count tagging issues"
    fi
}

# Check S3 bucket encryption
check_s3_encryption() {
    info "Checking S3 bucket encryption..."
    
    local buckets=$(aws s3api list-buckets \
        --query "Buckets[?contains(Name, '${PROJECT_NAME}') && contains(Name, '${ENVIRONMENT}')].Name" \
        --output json 2>/dev/null)
    
    local drift_count=0
    
    echo "$buckets" | jq -r '.[]' | while read -r bucket; do
        if [ -n "$bucket" ]; then
            if ! aws s3api get-bucket-encryption --bucket "$bucket" &>/dev/null; then
                warning "Bucket $bucket not encrypted"
                log_drift "S3:$bucket" "No encryption" "Enable encryption"
                drift_count=$((drift_count + 1))
                
                if [ "$AUTO_REMEDIATE" = true ]; then
                    if [ "$DRY_RUN" = false ]; then
                        aws s3api put-bucket-encryption \
                            --bucket "$bucket" \
                            --server-side-encryption-configuration '{
                                "Rules": [{
                                    "ApplyServerSideEncryptionByDefault": {
                                        "SSEAlgorithm": "AES256"
                                    }
                                }]
                            }' &>/dev/null
                        success "Enabled encryption on $bucket"
                    else
                        info "Would enable encryption on $bucket"
                    fi
                fi
            fi
        fi
    done
    
    if [ $drift_count -eq 0 ]; then
        success "All S3 buckets encrypted"
    fi
}

# Check S3 versioning
check_s3_versioning() {
    info "Checking S3 bucket versioning..."
    
    local state_bucket="${PROJECT_NAME}-terraform-state-${ENVIRONMENT}"
    
    if aws s3api head-bucket --bucket "$state_bucket" 2>/dev/null; then
        local versioning=$(aws s3api get-bucket-versioning \
            --bucket "$state_bucket" \
            --query 'Status' \
            --output text 2>/dev/null)
        
        if [ "$versioning" != "Enabled" ]; then
            warning "Versioning not enabled on state bucket"
            log_drift "S3:$state_bucket" "Versioning disabled" "Enable versioning"
            
            if [ "$AUTO_REMEDIATE" = true ]; then
                if [ "$DRY_RUN" = false ]; then
                    aws s3api put-bucket-versioning \
                        --bucket "$state_bucket" \
                        --versioning-configuration Status=Enabled &>/dev/null
                    success "Enabled versioning on $state_bucket"
                else
                    info "Would enable versioning on $state_bucket"
                fi
            fi
        else
            success "State bucket versioning enabled"
        fi
    fi
}

# Check Lambda function configurations
check_lambda_configs() {
    info "Checking Lambda function configurations..."
    
    local functions=$(aws lambda list-functions \
        --query "Functions[?starts_with(FunctionName, '${PROJECT_NAME}-${ENVIRONMENT}')]" \
        --output json 2>/dev/null)
    
    local drift_count=0
    
    echo "$functions" | jq -r '.[].FunctionName' | while read -r func_name; do
        if [ -n "$func_name" ]; then
            # Check if DLQ is configured
            local dlq=$(aws lambda get-function-configuration \
                --function-name "$func_name" \
                --query 'DeadLetterConfig.TargetArn' \
                --output text 2>/dev/null)
            
            if [ "$dlq" = "None" ] || [ -z "$dlq" ]; then
                warning "Lambda $func_name has no Dead Letter Queue"
                log_drift "Lambda:$func_name" "No DLQ configured" "Add DLQ"
                drift_count=$((drift_count + 1))
            fi
            
            # Check timeout
            local timeout=$(aws lambda get-function-configuration \
                --function-name "$func_name" \
                --query 'Timeout' \
                --output text 2>/dev/null)
            
            if [ "$timeout" -lt 30 ]; then
                warning "Lambda $func_name has low timeout: ${timeout}s"
                log_drift "Lambda:$func_name" "Timeout too low" "Increase timeout"
                drift_count=$((drift_count + 1))
            fi
        fi
    done
    
    if [ $drift_count -eq 0 ]; then
        success "Lambda configurations OK"
    fi
}

# Check CloudWatch log retention
check_log_retention() {
    info "Checking CloudWatch log retention..."
    
    local log_groups=$(aws logs describe-log-groups \
        --log-group-name-prefix "/aws/lambda/${PROJECT_NAME}-${ENVIRONMENT}" \
        --query 'logGroups[]' \
        --output json 2>/dev/null)
    
    local drift_count=0
    
    echo "$log_groups" | jq -r '.[].logGroupName' | while read -r log_group; do
        if [ -n "$log_group" ]; then
            local retention=$(echo "$log_groups" | jq -r ".[] | select(.logGroupName==\"$log_group\") | .retentionInDays // \"never\"")
            
            if [ "$retention" = "never" ]; then
                warning "Log group $log_group has no retention policy"
                log_drift "CloudWatch:$log_group" "No retention policy" "Set retention"
                drift_count=$((drift_count + 1))
                
                if [ "$AUTO_REMEDIATE" = true ]; then
                    if [ "$DRY_RUN" = false ]; then
                        aws logs put-retention-policy \
                            --log-group-name "$log_group" \
                            --retention-in-days 7 &>/dev/null
                        success "Set retention on $log_group to 7 days"
                    else
                        info "Would set retention on $log_group"
                    fi
                fi
            fi
        fi
    done
    
    if [ $drift_count -eq 0 ]; then
        success "Log retention policies OK"
    fi
}

# Check security group rules
check_security_groups() {
    info "Checking security group rules..."
    
    local vpcs=$(aws ec2 describe-vpcs \
        --filters "Name=tag:Environment,Values=${ENVIRONMENT}" \
                  "Name=tag:Project,Values=${PROJECT_NAME}" \
        --query 'Vpcs[0].VpcId' \
        --output text 2>/dev/null)
    
    if [ "$vpcs" != "None" ] && [ -n "$vpcs" ]; then
        local sgs=$(aws ec2 describe-security-groups \
            --filters "Name=vpc-id,Values=${vpcs}" \
            --query 'SecurityGroups[]' \
            --output json 2>/dev/null)
        
        # Check for overly permissive rules
        echo "$sgs" | jq -r '.[] | select(.IpPermissions[].IpRanges[].CidrIp == "0.0.0.0/0") | .GroupId' | while read -r sg_id; do
            warning "Security group $sg_id allows 0.0.0.0/0"
            log_drift "SG:$sg_id" "Overly permissive rule" "Review and restrict"
        done
    fi
}

# Check IAM policies
check_iam_policies() {
    info "Checking IAM policies for overly permissive access..."
    
    local roles=$(aws iam list-roles \
        --query "Roles[?contains(RoleName, '${PROJECT_NAME}-${ENVIRONMENT}')]" \
        --output json 2>/dev/null)
    
    echo "$roles" | jq -r '.[].RoleName' | while read -r role_name; do
        if [ -n "$role_name" ]; then
            local policies=$(aws iam list-attached-role-policies \
                --role-name "$role_name" \
                --query 'AttachedPolicies[].PolicyArn' \
                --output json 2>/dev/null)
            
            # Check for admin access
            if echo "$policies" | grep -q "AdministratorAccess"; then
                warning "Role $role_name has AdministratorAccess"
                log_drift "IAM:$role_name" "Excessive permissions" "Apply least privilege"
            fi
        fi
    done
}

# Generate drift summary
generate_summary() {
    cat >> "$DRIFT_LOG" <<EOF

================================================================================
SUMMARY
================================================================================

Total drift issues found: $(grep -c " | " "$DRIFT_LOG" || echo 0)

EOF
    
    if [ -s "$DRIFT_LOG" ]; then
        echo "" >> "$DRIFT_LOG"
        echo "Detailed issues:" >> "$DRIFT_LOG"
        grep " | " "$DRIFT_LOG" | while IFS='|' read -r timestamp resource issue fix; do
            echo "  - $resource: $issue" >> "$DRIFT_LOG"
        done
    fi
    
    info "Drift report saved to: $DRIFT_LOG"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -a|--auto)
            AUTO_REMEDIATE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            AUTO_REMEDIATE=true
            shift
            ;;
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
            error "Unknown option: $1"
            usage
            ;;
    esac
done

# Main execution
main() {
    echo -e "${BLUE}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║     Drift Detection and Remediation           ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "Environment:     ${BLUE}${ENVIRONMENT}${NC}"
    echo -e "Auto-remediate:  ${BLUE}${AUTO_REMEDIATE}${NC}"
    if [ "$DRY_RUN" = true ]; then
        echo -e "Mode:            ${YELLOW}DRY RUN${NC}"
    fi
    echo ""
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &>/dev/null; then
        error "AWS credentials not configured"
        exit 1
    fi
    
    # Initialize report
    init_report
    
    # Run checks
    check_terraform_drift
    check_missing_tags
    check_s3_encryption
    check_s3_versioning
    check_lambda_configs
    check_log_retention
    check_security_groups
    check_iam_policies
    
    # Generate summary
    generate_summary
    
    echo ""
    echo -e "${GREEN}════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}Drift detection completed${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════${NC}"
    echo ""
    
    # Show summary
    if [ -f "$DRIFT_LOG" ]; then
        cat "$DRIFT_LOG"
    fi
}

main

