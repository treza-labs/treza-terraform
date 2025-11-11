#!/bin/bash
# Cost Monitoring and Alerting Script
# Monitors AWS costs and sends alerts when thresholds are exceeded

set -euo pipefail

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly COST_THRESHOLD_DEV=100
readonly COST_THRESHOLD_STAGING=200
readonly COST_THRESHOLD_PROD=500
readonly LOOKBACK_DAYS=7

usage() {
    cat << EOF
${BLUE}Cost Monitoring and Alerting Script${NC}

Usage: $0 [options]

Options:
    -e, --environment <env>    Environment to check (dev, staging, prod, all)
    -t, --threshold <amount>   Alert threshold in USD (overrides defaults)
    -d, --days <number>        Lookback period in days (default: 7)
    -s, --slack-webhook <url>  Slack webhook URL for notifications
    -m, --email <address>      Email address for notifications
    --dry-run                  Show costs without sending alerts
    -h, --help                 Show this help message

Examples:
    $0 -e dev                               # Check dev environment
    $0 -e all                               # Check all environments
    $0 -e prod -t 1000                      # Check prod with custom threshold
    $0 -e all --slack-webhook <URL>         # Send Slack notifications
    $0 -e staging -m admin@example.com      # Send email notifications

EOF
    exit 0
}

error() {
    echo -e "${RED}Error: $*${NC}" >&2
    exit 1
}

success() {
    echo -e "${GREEN}✅ $*${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $*${NC}"
}

info() {
    echo -e "${BLUE}ℹ️  $*${NC}"
}

# Check AWS CLI
check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        error "AWS CLI not installed"
    fi
    
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured"
    fi
}

# Get cost for environment
get_environment_cost() {
    local env="$1"
    local days="${2:-7}"
    
    local start_date=$(date -u -d "${days} days ago" '+%Y-%m-%d' 2>/dev/null || date -u -v-${days}d '+%Y-%m-%d')
    local end_date=$(date -u '+%Y-%m-%d')
    
    info "Fetching costs for ${env} environment (${days} days)..."
    
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
    
    if [ -z "$cost" ] || [ "$cost" = "0" ]; then
        warning "Could not fetch costs for ${env}"
        echo "0"
        return
    fi
    
    # Parse JSON and sum costs
    local total=$(echo "$cost" | jq -r '.ResultsByTime[].Total.UnblendedCost.Amount' | \
                  awk '{sum+=$1} END {printf "%.2f", sum}')
    
    echo "${total:-0}"
}

# Get cost breakdown by service
get_service_breakdown() {
    local env="$1"
    local days="${2:-7}"
    
    local start_date=$(date -u -d "${days} days ago" '+%Y-%m-%d' 2>/dev/null || date -u -v-${days}d '+%Y-%m-%d')
    local end_date=$(date -u '+%Y-%m-%d')
    
    aws ce get-cost-and-usage \
        --time-period Start="${start_date}",End="${end_date}" \
        --granularity DAILY \
        --metrics UnblendedCost \
        --group-by Type=SERVICE \
        --filter file:/dev/stdin << EOF 2>/dev/null || echo "{}"
{
    "Tags": {
        "Key": "Environment",
        "Values": ["${env}"]
    }
}
EOF
}

# Check if cost exceeds threshold
check_threshold() {
    local cost="$1"
    local threshold="$2"
    local env="$3"
    
    if (( $(echo "$cost > $threshold" | bc -l) )); then
        warning "Cost alert for ${env}: \$${cost} exceeds threshold of \$${threshold}"
        return 0
    else
        success "Cost for ${env}: \$${cost} (within threshold of \$${threshold})"
        return 1
    fi
}

# Send Slack notification
send_slack_notification() {
    local webhook_url="$1"
    local env="$2"
    local cost="$3"
    local threshold="$4"
    
    local color="danger"
    local message="🚨 Cost Alert: ${env} environment has exceeded budget threshold"
    
    local payload=$(cat <<EOF
{
    "attachments": [
        {
            "color": "${color}",
            "title": "${message}",
            "fields": [
                {
                    "title": "Environment",
                    "value": "${env}",
                    "short": true
                },
                {
                    "title": "Current Cost",
                    "value": "\$${cost}",
                    "short": true
                },
                {
                    "title": "Threshold",
                    "value": "\$${threshold}",
                    "short": true
                },
                {
                    "title": "Period",
                    "value": "${LOOKBACK_DAYS} days",
                    "short": true
                }
            ],
            "footer": "Treza Cost Monitor",
            "ts": $(date +%s)
        }
    ]
}
EOF
)
    
    curl -X POST -H 'Content-type: application/json' \
        --data "$payload" \
        "$webhook_url" &> /dev/null && success "Slack notification sent" || warning "Failed to send Slack notification"
}

# Send email notification (requires AWS SES or similar)
send_email_notification() {
    local email="$1"
    local env="$2"
    local cost="$3"
    local threshold="$4"
    
    local subject="Cost Alert: ${env} environment exceeded budget"
    local body="Environment: ${env}\nCurrent Cost: \$${cost}\nThreshold: \$${threshold}\nPeriod: ${LOOKBACK_DAYS} days"
    
    # Using AWS SES (requires configuration)
    if command -v aws ses send-email &> /dev/null; then
        aws ses send-email \
            --from "alerts@example.com" \
            --to "$email" \
            --subject "$subject" \
            --text "$body" &> /dev/null && success "Email notification sent" || warning "Failed to send email"
    else
        warning "AWS SES not configured, skipping email notification"
    fi
}

# Display cost report
display_cost_report() {
    local env="$1"
    local cost="$2"
    local threshold="$3"
    
    echo ""
    echo "┌─────────────────────────────────────────────────────────┐"
    echo "│             Cost Report: ${env}                    │"
    echo "├─────────────────────────────────────────────────────────┤"
    printf "│ Current Cost (${LOOKBACK_DAYS} days):     %-10s              │\n" "\$${cost}"
    printf "│ Budget Threshold:       %-10s              │\n" "\$${threshold}"
    
    local percentage=$(echo "scale=2; ($cost / $threshold) * 100" | bc)
    printf "│ Budget Used:            %-5s%%                  │\n" "${percentage}"
    
    if (( $(echo "$cost > $threshold" | bc -l) )); then
        echo "│ Status:                 ⚠️  OVER BUDGET            │"
    elif (( $(echo "$cost > ($threshold * 0.8)" | bc -l) )); then
        echo "│ Status:                 ⚠️  WARNING (>80%)         │"
    else
        echo "│ Status:                 ✅ OK                     │"
    fi
    echo "└─────────────────────────────────────────────────────────┘"
    echo ""
}

# Main function
main() {
    local environment=""
    local threshold=""
    local days="$LOOKBACK_DAYS"
    local slack_webhook=""
    local email=""
    local dry_run=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -e|--environment)
                environment="$2"
                shift 2
                ;;
            -t|--threshold)
                threshold="$2"
                shift 2
                ;;
            -d|--days)
                days="$2"
                shift 2
                ;;
            -s|--slack-webhook)
                slack_webhook="$2"
                shift 2
                ;;
            -m|--email)
                email="$2"
                shift 2
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            -h|--help)
                usage
                ;;
            *)
                error "Unknown option: $1"
                ;;
        esac
    done
    
    if [ -z "$environment" ]; then
        error "Environment required. Use -e or --environment"
    fi
    
    check_aws_cli
    
    info "Starting cost monitoring..."
    
    # Process environments
    local environments=()
    if [ "$environment" = "all" ]; then
        environments=("dev" "staging" "prod")
    else
        environments=("$environment")
    fi
    
    local alerts_triggered=0
    
    for env in "${environments[@]}"; do
        # Set threshold based on environment
        if [ -z "$threshold" ]; then
            case $env in
                dev) threshold=$COST_THRESHOLD_DEV ;;
                staging) threshold=$COST_THRESHOLD_STAGING ;;
                prod) threshold=$COST_THRESHOLD_PROD ;;
                *) threshold=100 ;;
            esac
        fi
        
        # Get cost
        local cost=$(get_environment_cost "$env" "$days")
        
        # Display report
        display_cost_report "$env" "$cost" "$threshold"
        
        # Check threshold
        if check_threshold "$cost" "$threshold" "$env"; then
            alerts_triggered=$((alerts_triggered + 1))
            
            if [ "$dry_run" = false ]; then
                # Send notifications
                if [ -n "$slack_webhook" ]; then
                    send_slack_notification "$slack_webhook" "$env" "$cost" "$threshold"
                fi
                
                if [ -n "$email" ]; then
                    send_email_notification "$email" "$env" "$cost" "$threshold"
                fi
            else
                info "Dry run mode: notifications not sent"
            fi
        fi
    done
    
    echo ""
    if [ $alerts_triggered -gt 0 ]; then
        warning "${alerts_triggered} cost alert(s) triggered"
        exit 1
    else
        success "All costs within budget"
        exit 0
    fi
}

main "$@"

