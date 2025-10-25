#!/bin/bash
set -euo pipefail

# Log viewer script for Treza infrastructure
# Usage: ./view-logs.sh [environment] [component] [options]

# Check for help first
if [[ "${1:-}" =~ ^(-h|--help|help)$ ]]; then
    ENVIRONMENT="dev"
    COMPONENT="help"
    TAIL_LINES=50
else
    ENVIRONMENT=${1:-dev}
    COMPONENT=${2:-menu}
    TAIL_LINES=${3:-50}
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

success() {
    echo -e "${GREEN}✅ $*${NC}"
}

error() {
    echo -e "${RED}❌ $*${NC}"
}

info() {
    echo -e "${BLUE}ℹ️  $*${NC}"
}

highlight() {
    echo -e "${CYAN}$*${NC}"
}

# Show usage
show_usage() {
    echo -e "${CYAN}📋 Treza Infrastructure Log Viewer${NC}"
    echo ""
    echo "Usage: $0 [environment] [component] [lines]"
    echo ""
    echo "Environments:"
    echo "  dev, staging, prod (default: dev)"
    echo ""
    echo "Components:"
    echo "  menu           - Interactive menu (default)"
    echo "  all            - View all logs"
    echo "  lambda-trigger - Enclave trigger Lambda logs"
    echo "  lambda-validation - Validation Lambda logs"
    echo "  lambda-error   - Error handler Lambda logs"
    echo "  lambda-status  - Status monitor Lambda logs"
    echo "  ecs-runner     - ECS Terraform runner logs"
    echo "  step-deploy    - Deployment Step Function logs"
    echo "  step-cleanup   - Cleanup Step Function logs"
    echo ""
    echo "Options:"
    echo "  lines          - Number of lines to show (default: 50)"
    echo ""
    echo "Examples:"
    echo "  $0                              # Interactive menu for dev"
    echo "  $0 staging                      # Interactive menu for staging"
    echo "  $0 prod lambda-trigger          # View trigger Lambda logs in prod"
    echo "  $0 dev ecs-runner 100           # View last 100 lines of ECS logs"
    echo "  $0 staging all                  # View all logs for staging"
    echo ""
}

# Handle help component early
if [[ "$COMPONENT" == "help" ]]; then
    show_usage
    exit 0
fi

# Check if AWS CLI is available
if ! command -v aws &> /dev/null; then
    error "AWS CLI not found. Please install AWS CLI."
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity &>/dev/null; then
    error "AWS credentials not configured or invalid."
    exit 1
fi

# Validate environment
case "$ENVIRONMENT" in
    dev|staging|prod)
        ;;
    *)
        error "Invalid environment '$ENVIRONMENT'. Use: dev, staging, or prod"
        show_usage
        exit 1
        ;;
esac

# Get log group name pattern
get_log_group() {
    local component=$1
    case "$component" in
        lambda-trigger)
            echo "/aws/lambda/treza-${ENVIRONMENT}-enclave-trigger"
            ;;
        lambda-validation)
            echo "/aws/lambda/treza-${ENVIRONMENT}-validation"
            ;;
        lambda-error)
            echo "/aws/lambda/treza-${ENVIRONMENT}-error-handler"
            ;;
        lambda-status)
            echo "/aws/lambda/treza-${ENVIRONMENT}-status-monitor"
            ;;
        ecs-runner)
            echo "/ecs/treza-${ENVIRONMENT}-terraform-runner"
            ;;
        *)
            echo ""
            ;;
    esac
}

# View logs from a log group
view_logs() {
    local log_group=$1
    local component_name=$2
    
    echo ""
    highlight "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${PURPLE}📄 ${component_name}${NC}"
    highlight "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if aws logs describe-log-groups --log-group-name-prefix "$log_group" 2>/dev/null | grep -q "$log_group"; then
        success "Log group exists: $log_group"
        echo ""
        
        # Get the latest log stream
        LATEST_STREAM=$(aws logs describe-log-streams \
            --log-group-name "$log_group" \
            --order-by LastEventTime \
            --descending \
            --max-items 1 \
            --query 'logStreams[0].logStreamName' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$LATEST_STREAM" ] && [ "$LATEST_STREAM" != "None" ]; then
            info "Latest log stream: $LATEST_STREAM"
            echo ""
            
            # Fetch and display logs
            aws logs tail "$log_group" --since 1h --format short --filter-pattern "" | tail -n "$TAIL_LINES" || {
                warning "Could not tail logs, trying alternative method..."
                aws logs get-log-events \
                    --log-group-name "$log_group" \
                    --log-stream-name "$LATEST_STREAM" \
                    --limit "$TAIL_LINES" \
                    --query 'events[*].message' \
                    --output text 2>/dev/null || echo "No recent logs available"
            }
        else
            error "No log streams found in this log group"
        fi
    else
        error "Log group not found: $log_group"
        info "This component may not have been deployed yet or no logs have been generated."
    fi
    
    echo ""
}

# View Step Function execution logs
view_step_function_logs() {
    local sf_name=$1
    local component_name=$2
    
    echo ""
    highlight "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${PURPLE}📄 ${component_name}${NC}"
    highlight "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Get the state machine ARN
    REGION=$(aws configure get region || echo "us-west-2")
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    SF_ARN="arn:aws:states:${REGION}:${ACCOUNT_ID}:stateMachine:${sf_name}"
    
    if aws stepfunctions describe-state-machine --state-machine-arn "$SF_ARN" &>/dev/null; then
        success "Step Function exists: $sf_name"
        echo ""
        
        # Get recent executions
        info "Recent executions (last $TAIL_LINES):"
        aws stepfunctions list-executions \
            --state-machine-arn "$SF_ARN" \
            --max-results "$TAIL_LINES" \
            --query 'executions[*].[name, status, startDate, stopDate]' \
            --output table 2>/dev/null || error "Could not retrieve executions"
    else
        error "Step Function not found: $sf_name"
        info "This component may not have been deployed yet."
    fi
    
    echo ""
}

# Interactive menu
show_menu() {
    clear
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║         Treza Infrastructure Log Viewer                   ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  Environment: ${GREEN}${ENVIRONMENT}${NC}"
    echo -e "  Lines to show: ${YELLOW}${TAIL_LINES}${NC}"
    echo ""
    echo -e "${PURPLE}Select a component to view logs:${NC}"
    echo ""
    echo "  1) Lambda - Enclave Trigger"
    echo "  2) Lambda - Validation"
    echo "  3) Lambda - Error Handler"
    echo "  4) Lambda - Status Monitor"
    echo "  5) ECS - Terraform Runner"
    echo "  6) Step Function - Deployment"
    echo "  7) Step Function - Cleanup"
    echo ""
    echo "  8) View ALL logs"
    echo ""
    echo "  9) Change environment"
    echo "  0) Exit"
    echo ""
    echo -n "Enter choice [0-9]: "
}

# Interactive mode
interactive_mode() {
    while true; do
        show_menu
        read -r choice
        
        case $choice in
            1)
                view_logs "$(get_log_group lambda-trigger)" "Lambda - Enclave Trigger"
                read -p "Press Enter to continue..."
                ;;
            2)
                view_logs "$(get_log_group lambda-validation)" "Lambda - Validation"
                read -p "Press Enter to continue..."
                ;;
            3)
                view_logs "$(get_log_group lambda-error)" "Lambda - Error Handler"
                read -p "Press Enter to continue..."
                ;;
            4)
                view_logs "$(get_log_group lambda-status)" "Lambda - Status Monitor"
                read -p "Press Enter to continue..."
                ;;
            5)
                view_logs "$(get_log_group ecs-runner)" "ECS - Terraform Runner"
                read -p "Press Enter to continue..."
                ;;
            6)
                view_step_function_logs "treza-${ENVIRONMENT}-deployment" "Step Function - Deployment"
                read -p "Press Enter to continue..."
                ;;
            7)
                view_step_function_logs "treza-${ENVIRONMENT}-cleanup" "Step Function - Cleanup"
                read -p "Press Enter to continue..."
                ;;
            8)
                view_all_logs
                read -p "Press Enter to continue..."
                ;;
            9)
                echo ""
                echo "Current environment: $ENVIRONMENT"
                echo -n "Enter new environment (dev/staging/prod): "
                read -r new_env
                if [[ "$new_env" =~ ^(dev|staging|prod)$ ]]; then
                    ENVIRONMENT=$new_env
                    success "Environment changed to: $ENVIRONMENT"
                else
                    error "Invalid environment"
                fi
                sleep 1
                ;;
            0)
                echo ""
                info "Goodbye! 👋"
                exit 0
                ;;
            *)
                error "Invalid choice"
                sleep 1
                ;;
        esac
    done
}

# View all logs
view_all_logs() {
    clear
    log "📋 Viewing all logs for environment: $ENVIRONMENT"
    
    view_logs "$(get_log_group lambda-trigger)" "Lambda - Enclave Trigger"
    view_logs "$(get_log_group lambda-validation)" "Lambda - Validation"
    view_logs "$(get_log_group lambda-error)" "Lambda - Error Handler"
    view_logs "$(get_log_group lambda-status)" "Lambda - Status Monitor"
    view_logs "$(get_log_group ecs-runner)" "ECS - Terraform Runner"
    view_step_function_logs "treza-${ENVIRONMENT}-deployment" "Step Function - Deployment"
    view_step_function_logs "treza-${ENVIRONMENT}-cleanup" "Step Function - Cleanup"
    
    highlight "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    success "All logs displayed"
}

# Main execution
case "$COMPONENT" in
    menu)
        interactive_mode
        ;;
    all)
        view_all_logs
        ;;
    lambda-trigger|lambda-validation|lambda-error|lambda-status|ecs-runner)
        LOG_GROUP=$(get_log_group "$COMPONENT")
        view_logs "$LOG_GROUP" "$(echo "$COMPONENT" | tr '-' ' ' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)}1')"
        ;;
    step-deploy)
        view_step_function_logs "treza-${ENVIRONMENT}-deployment" "Step Function - Deployment"
        ;;
    step-cleanup)
        view_step_function_logs "treza-${ENVIRONMENT}-cleanup" "Step Function - Cleanup"
        ;;
    help|--help|-h)
        show_usage
        ;;
    *)
        error "Unknown component: $COMPONENT"
        echo ""
        show_usage
        exit 1
        ;;
esac

