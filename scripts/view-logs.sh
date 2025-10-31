#!/bin/bash
set -euo pipefail

# Enhanced log viewer script for Treza infrastructure
# Usage: ./view-logs.sh [environment] [component] [options]

# Default values
ENVIRONMENT=""
COMPONENT="menu"
TAIL_LINES=50
FOLLOW=false
FILTER_PATTERN=""
TIME_RANGE="1h"
EXPORT_FILE=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help|help)
            ENVIRONMENT="dev"
            COMPONENT="help"
            shift
            ;;
        -f|--follow)
            FOLLOW=true
            shift
            ;;
        --filter)
            FILTER_PATTERN="$2"
            shift 2
            ;;
        --since)
            TIME_RANGE="$2"
            shift 2
            ;;
        --export)
            EXPORT_FILE="$2"
            shift 2
            ;;
        --lines)
            TAIL_LINES="$2"
            shift 2
            ;;
        *)
            if [ -z "$ENVIRONMENT" ]; then
                ENVIRONMENT=$1
            elif [ "$COMPONENT" = "menu" ]; then
                COMPONENT=$1
            else
                TAIL_LINES=$1
            fi
            shift
            ;;
    esac
done

# Set defaults if not provided
ENVIRONMENT=${ENVIRONMENT:-dev}
COMPONENT=${COMPONENT:-menu}

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
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║       📋 Treza Infrastructure Log Viewer                  ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Usage: $0 [environment] [component] [options]"
    echo ""
    echo -e "${PURPLE}Environments:${NC}"
    echo "  dev, staging, prod (default: dev)"
    echo ""
    echo -e "${PURPLE}Components:${NC}"
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
    echo -e "${PURPLE}Options:${NC}"
    echo "  -f, --follow           Follow logs in real-time (tail -f style)"
    echo "  --filter PATTERN       Filter logs by pattern (e.g., 'ERROR', 'WARNING')"
    echo "  --since TIME          Time range (e.g., '1h', '30m', '2d') (default: 1h)"
    echo "  --lines N             Number of lines to show (default: 50)"
    echo "  --export FILE         Export logs to a file"
    echo "  -h, --help            Show this help message"
    echo ""
    echo -e "${PURPLE}Examples:${NC}"
    echo ""
    echo "  ${CYAN}# Interactive menu${NC}"
    echo "  $0"
    echo "  $0 staging"
    echo ""
    echo "  ${CYAN}# View specific component${NC}"
    echo "  $0 prod lambda-trigger"
    echo "  $0 dev ecs-runner --lines 100"
    echo ""
    echo "  ${CYAN}# Follow logs in real-time${NC}"
    echo "  $0 dev lambda-trigger --follow"
    echo "  $0 prod ecs-runner -f"
    echo ""
    echo "  ${CYAN}# Filter and search${NC}"
    echo "  $0 dev all --filter ERROR"
    echo "  $0 prod lambda-error --filter 'stack trace'"
    echo ""
    echo "  ${CYAN}# Time range selection${NC}"
    echo "  $0 dev ecs-runner --since 30m"
    echo "  $0 prod all --since 2h"
    echo ""
    echo "  ${CYAN}# Export logs${NC}"
    echo "  $0 dev all --export dev-logs-\$(date +%Y%m%d).txt"
    echo "  $0 prod lambda-trigger --since 1d --export prod-trigger.log"
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
        
        # Show active options
        if [ "$FOLLOW" = true ]; then
            info "Mode: Follow (real-time, press Ctrl+C to stop)"
        fi
        if [ -n "$FILTER_PATTERN" ]; then
            info "Filter: '$FILTER_PATTERN'"
        fi
        if [ -n "$EXPORT_FILE" ]; then
            info "Exporting to: $EXPORT_FILE"
        fi
        info "Time range: $TIME_RANGE"
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
            
            # Build the filter pattern for AWS CloudWatch Logs
            local aws_filter_pattern=""
            if [ -n "$FILTER_PATTERN" ]; then
                aws_filter_pattern="--filter-pattern \"$FILTER_PATTERN\""
            fi
            
            # Fetch and display logs based on mode
            if [ "$FOLLOW" = true ]; then
                # Follow mode - real-time log streaming
                info "📡 Streaming logs in real-time... (Ctrl+C to stop)"
                echo ""
                
                if [ -n "$aws_filter_pattern" ]; then
                    eval "aws logs tail \"$log_group\" --follow --since \"$TIME_RANGE\" --format short $aws_filter_pattern" || {
                        error "Failed to follow logs with filter"
                    }
                else
                    aws logs tail "$log_group" --follow --since "$TIME_RANGE" --format short || {
                        error "Failed to follow logs"
                    }
                fi
            elif [ -n "$EXPORT_FILE" ]; then
                # Export mode - save logs to file
                info "📥 Exporting logs to: $EXPORT_FILE"
                
                if [ -n "$aws_filter_pattern" ]; then
                    eval "aws logs tail \"$log_group\" --since \"$TIME_RANGE\" --format short $aws_filter_pattern" > "$EXPORT_FILE" 2>&1 || {
                        error "Failed to export logs"
                        return 1
                    }
                else
                    aws logs tail "$log_group" --since "$TIME_RANGE" --format short > "$EXPORT_FILE" 2>&1 || {
                        error "Failed to export logs"
                        return 1
                    }
                fi
                
                local line_count=$(wc -l < "$EXPORT_FILE" | tr -d ' ')
                local file_size=$(ls -lh "$EXPORT_FILE" | awk '{print $5}')
                success "Exported $line_count lines ($file_size) to $EXPORT_FILE"
            else
                # Standard view mode
                if [ -n "$aws_filter_pattern" ]; then
                    eval "aws logs tail \"$log_group\" --since \"$TIME_RANGE\" --format short $aws_filter_pattern | tail -n \"$TAIL_LINES\"" || {
                        warning "Could not tail logs with filter, trying without filter..."
                        aws logs tail "$log_group" --since "$TIME_RANGE" --format short | grep -i "$FILTER_PATTERN" | tail -n "$TAIL_LINES" || echo "No matching logs found"
                    }
                else
                    aws logs tail "$log_group" --since "$TIME_RANGE" --format short | tail -n "$TAIL_LINES" || {
                        warning "Could not tail logs, trying alternative method..."
                        aws logs get-log-events \
                            --log-group-name "$log_group" \
                            --log-stream-name "$LATEST_STREAM" \
                            --limit "$TAIL_LINES" \
                            --query 'events[*].message' \
                            --output text 2>/dev/null || echo "No recent logs available"
                    }
                fi
            fi
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
    echo -e "  ${PURPLE}Environment:${NC} ${GREEN}${ENVIRONMENT}${NC}"
    echo -e "  ${PURPLE}Time Range:${NC}  ${YELLOW}${TIME_RANGE}${NC}"
    echo -e "  ${PURPLE}Lines:${NC}       ${YELLOW}${TAIL_LINES}${NC}"
    if [ "$FOLLOW" = true ]; then
        echo -e "  ${PURPLE}Follow Mode:${NC} ${GREEN}ON${NC}"
    fi
    if [ -n "$FILTER_PATTERN" ]; then
        echo -e "  ${PURPLE}Filter:${NC}      ${YELLOW}${FILTER_PATTERN}${NC}"
    fi
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
    echo -e "${PURPLE}Options:${NC}"
    echo "  e) Change environment"
    echo "  t) Change time range"
    echo "  f) Toggle follow mode"
    echo "  s) Set filter pattern"
    echo "  x) Export logs to file"
    echo "  0) Exit"
    echo ""
    echo -n "Enter choice: "
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
            e|E)
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
            t|T)
                echo ""
                echo "Current time range: $TIME_RANGE"
                echo "Examples: 30m, 1h, 2h, 1d, 7d"
                echo -n "Enter new time range: "
                read -r new_time
                if [ -n "$new_time" ]; then
                    TIME_RANGE=$new_time
                    success "Time range changed to: $TIME_RANGE"
                else
                    error "Invalid time range"
                fi
                sleep 1
                ;;
            f|F)
                if [ "$FOLLOW" = true ]; then
                    FOLLOW=false
                    success "Follow mode disabled"
                else
                    FOLLOW=true
                    success "Follow mode enabled"
                fi
                sleep 1
                ;;
            s|S)
                echo ""
                echo "Current filter: ${FILTER_PATTERN:-none}"
                echo "Enter filter pattern (e.g., 'ERROR', 'WARNING', leave empty to clear):"
                echo -n "Filter: "
                read -r new_filter
                FILTER_PATTERN=$new_filter
                if [ -n "$FILTER_PATTERN" ]; then
                    success "Filter set to: $FILTER_PATTERN"
                else
                    success "Filter cleared"
                fi
                sleep 1
                ;;
            x|X)
                echo ""
                echo "Enter filename for export (e.g., logs-\$(date +%Y%m%d).txt):"
                echo -n "Filename: "
                read -r export_name
                if [ -n "$export_name" ]; then
                    EXPORT_FILE=$export_name
                    success "Will export to: $EXPORT_FILE"
                    echo ""
                    echo "Select component to export (1-8), or 0 to cancel:"
                    read -p "Choice: " export_choice
                    case $export_choice in
                        1) view_logs "$(get_log_group lambda-trigger)" "Lambda - Enclave Trigger" ;;
                        2) view_logs "$(get_log_group lambda-validation)" "Lambda - Validation" ;;
                        3) view_logs "$(get_log_group lambda-error)" "Lambda - Error Handler" ;;
                        4) view_logs "$(get_log_group lambda-status)" "Lambda - Status Monitor" ;;
                        5) view_logs "$(get_log_group ecs-runner)" "ECS - Terraform Runner" ;;
                        8) view_all_logs ;;
                        0) info "Export cancelled" ;;
                        *) error "Invalid choice" ;;
                    esac
                    EXPORT_FILE=""  # Reset after export
                else
                    error "No filename provided"
                fi
                read -p "Press Enter to continue..."
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

