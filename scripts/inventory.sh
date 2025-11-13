#!/bin/bash
# Resource Inventory Script
# Generates comprehensive reports of all deployed AWS resources

set -euo pipefail

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly OUTPUT_DIR="${PROJECT_ROOT}/inventory"

ENVIRONMENT="${1:-dev}"
PROJECT_NAME="${PROJECT_NAME:-treza}"
AWS_REGION="${AWS_REGION:-us-west-2}"
OUTPUT_FORMAT="text"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

usage() {
    cat << EOF
${BLUE}Infrastructure Inventory Generator${NC}

Usage: $0 [environment] [options]

Arguments:
    environment         Environment to inventory (dev, staging, prod, all)

Options:
    -f, --format <fmt>  Output format: text, json, csv (default: text)
    -o, --output <dir>  Output directory (default: ./inventory)
    -h, --help          Show this help message

Examples:
    $0 dev
    $0 prod --format json
    $0 all --output /tmp/inventory

Generates inventory for:
  - VPC and networking resources
  - EC2 instances and security groups
  - ECS clusters and services
  - Lambda functions
  - Step Functions
  - DynamoDB tables
  - S3 buckets
  - IAM roles and policies
  - CloudWatch resources
  - Cost estimates

EOF
    exit 0
}

info() {
    echo -e "${BLUE}→${NC} $*"
}

success() {
    echo -e "${GREEN}✓${NC} $*"
}

# Initialize output file
init_output() {
    local env="$1"
    mkdir -p "$OUTPUT_DIR"
    local output_file="${OUTPUT_DIR}/inventory-${env}-${TIMESTAMP}.${OUTPUT_FORMAT}"
    echo "$output_file"
}

# Start report
start_report() {
    local env="$1"
    local output="$2"
    
    case $OUTPUT_FORMAT in
        json)
            echo "{" > "$output"
            echo "  \"environment\": \"$env\"," >> "$output"
            echo "  \"project\": \"$PROJECT_NAME\"," >> "$output"
            echo "  \"region\": \"$AWS_REGION\"," >> "$output"
            echo "  \"timestamp\": \"$TIMESTAMP\"," >> "$output"
            echo "  \"resources\": {" >> "$output"
            ;;
        csv)
            echo "Type,Name,ID,Status,Tags,Details" > "$output"
            ;;
        text)
            cat > "$output" <<EOF
═══════════════════════════════════════════════════════════
              INFRASTRUCTURE INVENTORY REPORT
═══════════════════════════════════════════════════════════

Environment:  $env
Project:      $PROJECT_NAME
Region:       $AWS_REGION
Generated:    $(date)
AWS Account:  $(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "Unknown")

EOF
            ;;
    esac
}

# Inventory VPC resources
inventory_vpc() {
    local env="$1"
    local output="$2"
    
    info "Inventorying VPC resources..."
    
    local vpcs=$(aws ec2 describe-vpcs \
        --filters "Name=tag:Environment,Values=${env}" \
                  "Name=tag:Project,Values=${PROJECT_NAME}" \
        --output json 2>/dev/null)
    
    if [ "$OUTPUT_FORMAT" = "text" ]; then
        cat >> "$output" <<EOF

───────────────────────────────────────────────────────────
VPC RESOURCES
───────────────────────────────────────────────────────────

EOF
        echo "$vpcs" | jq -r '.Vpcs[] | "VPC ID:       \(.VpcId)\nCIDR Block:   \(.CidrBlock)\nState:        \(.State)\n"' >> "$output"
        
        # Subnets
        echo "Subnets:" >> "$output"
        local vpc_id=$(echo "$vpcs" | jq -r '.Vpcs[0].VpcId // empty')
        if [ -n "$vpc_id" ]; then
            aws ec2 describe-subnets \
                --filters "Name=vpc-id,Values=${vpc_id}" \
                --query 'Subnets[].{ID:SubnetId,CIDR:CidrBlock,AZ:AvailabilityZone,Type:Tags[?Key==`Type`].Value|[0]}' \
                --output table >> "$output" 2>/dev/null
        fi
    elif [ "$OUTPUT_FORMAT" = "json" ]; then
        echo "    \"vpc\": $vpcs," >> "$output"
    fi
}

# Inventory EC2 instances
inventory_ec2() {
    local env="$1"
    local output="$2"
    
    info "Inventorying EC2 instances..."
    
    local instances=$(aws ec2 describe-instances \
        --filters "Name=tag:Environment,Values=${env}" \
                  "Name=tag:Project,Values=${PROJECT_NAME}" \
        --output json 2>/dev/null)
    
    if [ "$OUTPUT_FORMAT" = "text" ]; then
        echo -e "\nEC2 Instances:" >> "$output"
        echo "$instances" | jq -r '.Reservations[].Instances[] | "  \(.InstanceId) - \(.InstanceType) - \(.State.Name)"' >> "$output"
    elif [ "$OUTPUT_FORMAT" = "json" ]; then
        echo "    \"ec2_instances\": $instances," >> "$output"
    fi
}

# Inventory ECS resources
inventory_ecs() {
    local env="$1"
    local output="$2"
    
    info "Inventorying ECS resources..."
    
    local cluster_name="${PROJECT_NAME}-${env}"
    
    if [ "$OUTPUT_FORMAT" = "text" ]; then
        cat >> "$output" <<EOF

───────────────────────────────────────────────────────────
ECS RESOURCES
───────────────────────────────────────────────────────────

EOF
        # Cluster info
        aws ecs describe-clusters \
            --clusters "$cluster_name" \
            --query 'clusters[0].{Name:clusterName,Status:status,Tasks:runningTasksCount,Services:activeServicesCount}' \
            --output table >> "$output" 2>/dev/null || echo "Cluster not found" >> "$output"
        
        # Task definitions
        echo -e "\nTask Definitions:" >> "$output"
        aws ecs list-task-definitions \
            --family-prefix "${PROJECT_NAME}-${env}" \
            --query 'taskDefinitionArns[]' \
            --output text >> "$output" 2>/dev/null | sed 's/^/  /'
    elif [ "$OUTPUT_FORMAT" = "json" ]; then
        local cluster_info=$(aws ecs describe-clusters --clusters "$cluster_name" --output json 2>/dev/null)
        echo "    \"ecs_cluster\": $cluster_info," >> "$output"
    fi
}

# Inventory Lambda functions
inventory_lambda() {
    local env="$1"
    local output="$2"
    
    info "Inventorying Lambda functions..."
    
    local functions=$(aws lambda list-functions \
        --query "Functions[?starts_with(FunctionName, '${PROJECT_NAME}-${env}')]" \
        --output json 2>/dev/null)
    
    if [ "$OUTPUT_FORMAT" = "text" ]; then
        cat >> "$output" <<EOF

───────────────────────────────────────────────────────────
LAMBDA FUNCTIONS
───────────────────────────────────────────────────────────

EOF
        echo "$functions" | jq -r '.[] | "Name:     \(.FunctionName)\nRuntime:  \(.Runtime)\nMemory:   \(.MemorySize) MB\nTimeout:  \(.Timeout)s\nState:    \(.State)\n"' >> "$output"
    elif [ "$OUTPUT_FORMAT" = "json" ]; then
        echo "    \"lambda_functions\": $functions," >> "$output"
    fi
}

# Inventory Step Functions
inventory_stepfunctions() {
    local env="$1"
    local output="$2"
    
    info "Inventorying Step Functions..."
    
    local state_machines=$(aws stepfunctions list-state-machines \
        --query "stateMachines[?contains(name, '${PROJECT_NAME}-${env}')]" \
        --output json 2>/dev/null)
    
    if [ "$OUTPUT_FORMAT" = "text" ]; then
        cat >> "$output" <<EOF

───────────────────────────────────────────────────────────
STEP FUNCTIONS
───────────────────────────────────────────────────────────

EOF
        echo "$state_machines" | jq -r '.[] | "Name:    \(.name)\nARN:     \(.stateMachineArn)\nStatus:  \(.status)\nCreated: \(.creationDate)\n"' >> "$output"
    elif [ "$OUTPUT_FORMAT" = "json" ]; then
        echo "    \"step_functions\": $state_machines," >> "$output"
    fi
}

# Inventory DynamoDB tables
inventory_dynamodb() {
    local env="$1"
    local output="$2"
    
    info "Inventorying DynamoDB tables..."
    
    if [ "$OUTPUT_FORMAT" = "text" ]; then
        cat >> "$output" <<EOF

───────────────────────────────────────────────────────────
DYNAMODB TABLES
───────────────────────────────────────────────────────────

EOF
        aws dynamodb list-tables \
            --query "TableNames[?contains(@, '${PROJECT_NAME}') && contains(@, '${env}')]" \
            --output text 2>/dev/null | while read -r table; do
                if [ -n "$table" ]; then
                    aws dynamodb describe-table \
                        --table-name "$table" \
                        --query 'Table.{Name:TableName,Status:TableStatus,Items:ItemCount,Size:TableSizeBytes}' \
                        --output table >> "$output" 2>/dev/null
                fi
            done
    fi
}

# Inventory S3 buckets
inventory_s3() {
    local env="$1"
    local output="$2"
    
    info "Inventorying S3 buckets..."
    
    if [ "$OUTPUT_FORMAT" = "text" ]; then
        cat >> "$output" <<EOF

───────────────────────────────────────────────────────────
S3 BUCKETS
───────────────────────────────────────────────────────────

EOF
        aws s3api list-buckets \
            --query "Buckets[?contains(Name, '${PROJECT_NAME}') && contains(Name, '${env}')].Name" \
            --output text 2>/dev/null | while read -r bucket; do
                if [ -n "$bucket" ]; then
                    local size=$(aws s3 ls "s3://$bucket" --recursive --summarize 2>/dev/null | grep "Total Size" | awk '{print $3}')
                    local size_mb=$((size / 1024 / 1024))
                    echo "Bucket: $bucket (${size_mb} MB)" >> "$output"
                fi
            done
    fi
}

# Inventory IAM roles
inventory_iam() {
    local env="$1"
    local output="$2"
    
    info "Inventorying IAM roles..."
    
    if [ "$OUTPUT_FORMAT" = "text" ]; then
        cat >> "$output" <<EOF

───────────────────────────────────────────────────────────
IAM ROLES
───────────────────────────────────────────────────────────

EOF
        aws iam list-roles \
            --query "Roles[?contains(RoleName, '${PROJECT_NAME}-${env}')].{Role:RoleName,Created:CreateDate}" \
            --output table >> "$output" 2>/dev/null
    fi
}

# Inventory CloudWatch resources
inventory_cloudwatch() {
    local env="$1"
    local output="$2"
    
    info "Inventorying CloudWatch resources..."
    
    if [ "$OUTPUT_FORMAT" = "text" ]; then
        cat >> "$output" <<EOF

───────────────────────────────────────────────────────────
CLOUDWATCH RESOURCES
───────────────────────────────────────────────────────────

Log Groups:
EOF
        aws logs describe-log-groups \
            --log-group-name-prefix "/aws/lambda/${PROJECT_NAME}-${env}" \
            --query 'logGroups[].{Name:logGroupName,Retention:retentionInDays,Size:storedBytes}' \
            --output table >> "$output" 2>/dev/null
        
        echo -e "\nDashboards:" >> "$output"
        aws cloudwatch list-dashboards \
            --query "DashboardEntries[?contains(DashboardName, '${PROJECT_NAME}-${env}')].DashboardName" \
            --output text >> "$output" 2>/dev/null | sed 's/^/  /'
    fi
}

# Cost estimate
estimate_costs() {
    local env="$1"
    local output="$2"
    
    info "Estimating costs..."
    
    if [ "$OUTPUT_FORMAT" = "text" ]; then
        cat >> "$output" <<EOF

───────────────────────────────────────────────────────────
COST ESTIMATE (Last 7 Days)
───────────────────────────────────────────────────────────

EOF
        local start_date=$(date -u -d "7 days ago" '+%Y-%m-%d' 2>/dev/null || date -u -v-7d '+%Y-%m-%d')
        local end_date=$(date -u '+%Y-%m-%d')
        
        local cost=$(aws ce get-cost-and-usage \
            --time-period Start="${start_date}",End="${end_date}" \
            --granularity DAILY \
            --metrics UnblendedCost \
            --filter file:/dev/stdin << EOF 2>/dev/null || echo "0"
{
    "Tags": {
        "Key": "Environment",
        "Values": ["${env}"]
    }
}
EOF
)
        
        if [ -n "$cost" ] && [ "$cost" != "0" ]; then
            local total=$(echo "$cost" | jq -r '.ResultsByTime[].Total.UnblendedCost.Amount' | \
                         awk '{sum+=$1} END {printf "%.2f", sum}')
            echo "Total Cost (7 days): \$${total}" >> "$output"
            echo "Estimated Monthly:   \$$(echo "$total * 4.3" | bc -l | xargs printf "%.2f")" >> "$output"
        else
            echo "Cost data not available" >> "$output"
        fi
    fi
}

# End report
end_report() {
    local output="$1"
    
    case $OUTPUT_FORMAT in
        json)
            echo "  }" >> "$output"
            echo "}" >> "$output"
            ;;
        text)
            cat >> "$output" <<EOF

═══════════════════════════════════════════════════════════
                    END OF REPORT
═══════════════════════════════════════════════════════════
EOF
            ;;
    esac
}

# Generate inventory for one environment
generate_inventory() {
    local env="$1"
    
    info "Generating inventory for: $env"
    
    local output=$(init_output "$env")
    
    start_report "$env" "$output"
    inventory_vpc "$env" "$output"
    inventory_ec2 "$env" "$output"
    inventory_ecs "$env" "$output"
    inventory_lambda "$env" "$output"
    inventory_stepfunctions "$env" "$output"
    inventory_dynamodb "$env" "$output"
    inventory_s3 "$env" "$output"
    inventory_iam "$env" "$output"
    inventory_cloudwatch "$env" "$output"
    estimate_costs "$env" "$output"
    end_report "$output"
    
    success "Inventory generated: $output"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--format)
            OUTPUT_FORMAT="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        dev|staging|prod|all)
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
    echo -e "${BLUE}║     Infrastructure Inventory Generator        ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &>/dev/null; then
        echo -e "${RED}Error: AWS credentials not configured${NC}"
        exit 1
    fi
    
    # Generate inventory
    if [ "$ENVIRONMENT" = "all" ]; then
        for env in dev staging prod; do
            generate_inventory "$env"
        done
    else
        generate_inventory "$ENVIRONMENT"
    fi
    
    echo ""
    echo -e "${GREEN}════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}Inventory generation completed!${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "Output directory: ${BLUE}${OUTPUT_DIR}${NC}"
    echo ""
}

main

