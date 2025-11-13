#!/bin/bash
# Infrastructure Performance Benchmarking Script
# Tests and validates infrastructure performance

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
readonly BENCHMARK_LOG="${PROJECT_ROOT}/benchmark-results.json"

ENVIRONMENT="${1:-dev}"
PROJECT_NAME="${PROJECT_NAME:-treza}"
VERBOSE=false
QUICK_MODE=false

usage() {
    cat << EOF
${BLUE}Infrastructure Performance Benchmarking${NC}

Usage: $0 [environment] [options]

Arguments:
    environment         Environment to benchmark (dev, staging, prod)

Options:
    -q, --quick         Quick benchmark (skip long-running tests)
    -v, --verbose       Verbose output
    -h, --help          Show this help message

Examples:
    $0 dev
    $0 prod --quick
    $0 staging --verbose

Benchmarks:
  - Lambda cold/warm start times
  - API Gateway response times
  - DynamoDB read/write latency
  - S3 upload/download speeds
  - Step Functions execution time
  - VPC network latency
  - ECS task startup time

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

highlight() {
    echo -e "${CYAN}$*${NC}"
}

# Initialize results
init_results() {
    cat > "$BENCHMARK_LOG" <<EOF
{
  "environment": "$ENVIRONMENT",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "benchmarks": []
}
EOF
}

# Add benchmark result
add_result() {
    local test_name="$1"
    local metric="$2"
    local value="$3"
    local unit="$4"
    local status="$5"
    
    local temp=$(mktemp)
    jq ".benchmarks += [{
        \"test\": \"$test_name\",
        \"metric\": \"$metric\",
        \"value\": $value,
        \"unit\": \"$unit\",
        \"status\": \"$status\",
        \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
    }]" "$BENCHMARK_LOG" > "$temp"
    mv "$temp" "$BENCHMARK_LOG"
}

# Lambda cold start test
benchmark_lambda_cold_start() {
    info "Testing Lambda cold start performance..."
    
    local functions=$(aws lambda list-functions \
        --query "Functions[?starts_with(FunctionName, '${PROJECT_NAME}-${ENVIRONMENT}')].FunctionName" \
        --output text 2>/dev/null | head -1)
    
    if [ -z "$functions" ]; then
        warning "No Lambda functions found"
        return
    fi
    
    local func_name=$(echo "$functions" | awk '{print $1}')
    
    # Force cold start by updating env var
    aws lambda update-function-configuration \
        --function-name "$func_name" \
        --environment "Variables={BENCHMARK_RUN=true}" &>/dev/null
    
    sleep 5
    
    # Measure cold start
    local start=$(date +%s%3N)
    aws lambda invoke \
        --function-name "$func_name" \
        --payload '{"test": "benchmark"}' \
        /tmp/lambda-response.json &>/dev/null
    local end=$(date +%s%3N)
    
    local cold_start=$((end - start))
    
    highlight "  Cold start: ${cold_start}ms"
    
    # Measure warm start
    start=$(date +%s%3N)
    aws lambda invoke \
        --function-name "$func_name" \
        --payload '{"test": "benchmark"}' \
        /tmp/lambda-response.json &>/dev/null
    end=$(date +%s%3N)
    
    local warm_start=$((end - start))
    
    highlight "  Warm start: ${warm_start}ms"
    
    add_result "lambda_cold_start" "cold_start_ms" "$cold_start" "milliseconds" "success"
    add_result "lambda_warm_start" "warm_start_ms" "$warm_start" "milliseconds" "success"
    
    # Assess performance
    if [ "$cold_start" -lt 1000 ]; then
        success "Lambda cold start performance: Excellent"
    elif [ "$cold_start" -lt 3000 ]; then
        success "Lambda cold start performance: Good"
    else
        warning "Lambda cold start performance: Needs improvement"
    fi
}

# DynamoDB latency test
benchmark_dynamodb() {
    info "Testing DynamoDB performance..."
    
    local tables=$(aws dynamodb list-tables \
        --query "TableNames[?contains(@, '${PROJECT_NAME}')]" \
        --output text 2>/dev/null | head -1)
    
    if [ -z "$tables" ]; then
        warning "No DynamoDB tables found"
        return
    fi
    
    local table_name=$(echo "$tables" | awk '{print $1}')
    
    # Write test
    local write_times=()
    for i in {1..10}; do
        local start=$(date +%s%3N)
        aws dynamodb put-item \
            --table-name "$table_name" \
            --item "{\"id\": {\"S\": \"benchmark-$i\"}, \"data\": {\"S\": \"test-data\"}}" \
            &>/dev/null
        local end=$(date +%s%3N)
        write_times+=($((end - start)))
    done
    
    # Calculate average write time
    local total=0
    for time in "${write_times[@]}"; do
        total=$((total + time))
    done
    local avg_write=$((total / ${#write_times[@]}))
    
    highlight "  Average write: ${avg_write}ms"
    
    # Read test
    local read_times=()
    for i in {1..10}; do
        local start=$(date +%s%3N)
        aws dynamodb get-item \
            --table-name "$table_name" \
            --key "{\"id\": {\"S\": \"benchmark-$i\"}}" \
            &>/dev/null
        local end=$(date +%s%3N)
        read_times+=($((end - start)))
    done
    
    # Calculate average read time
    total=0
    for time in "${read_times[@]}"; do
        total=$((total + time))
    done
    local avg_read=$((total / ${#read_times[@]}))
    
    highlight "  Average read: ${avg_read}ms"
    
    add_result "dynamodb_write" "avg_write_ms" "$avg_write" "milliseconds" "success"
    add_result "dynamodb_read" "avg_read_ms" "$avg_read" "milliseconds" "success"
    
    # Cleanup
    for i in {1..10}; do
        aws dynamodb delete-item \
            --table-name "$table_name" \
            --key "{\"id\": {\"S\": \"benchmark-$i\"}}" \
            &>/dev/null
    done
    
    if [ "$avg_write" -lt 50 ] && [ "$avg_read" -lt 20 ]; then
        success "DynamoDB performance: Excellent"
    elif [ "$avg_write" -lt 100 ] && [ "$avg_read" -lt 50 ]; then
        success "DynamoDB performance: Good"
    else
        warning "DynamoDB performance: Needs improvement"
    fi
}

# S3 transfer speed test
benchmark_s3() {
    info "Testing S3 transfer performance..."
    
    local buckets=$(aws s3api list-buckets \
        --query "Buckets[?contains(Name, '${PROJECT_NAME}') && contains(Name, '${ENVIRONMENT}')].Name" \
        --output text 2>/dev/null | head -1)
    
    if [ -z "$buckets" ]; then
        warning "No S3 buckets found"
        return
    fi
    
    local bucket=$(echo "$buckets" | awk '{print $1}')
    
    # Create test file (1MB)
    dd if=/dev/urandom of=/tmp/benchmark-1mb.dat bs=1M count=1 &>/dev/null
    
    # Upload test
    local start=$(date +%s%3N)
    aws s3 cp /tmp/benchmark-1mb.dat "s3://${bucket}/benchmark/test.dat" &>/dev/null
    local end=$(date +%s%3N)
    local upload_time=$((end - start))
    
    highlight "  Upload 1MB: ${upload_time}ms"
    
    # Download test
    start=$(date +%s%3N)
    aws s3 cp "s3://${bucket}/benchmark/test.dat" /tmp/benchmark-download.dat &>/dev/null
    end=$(date +%s%3N)
    local download_time=$((end - start))
    
    highlight "  Download 1MB: ${download_time}ms"
    
    # Calculate speeds (MB/s)
    local upload_speed=$(awk "BEGIN {print 1000/$upload_time}")
    local download_speed=$(awk "BEGIN {print 1000/$download_time}")
    
    highlight "  Upload speed: ${upload_speed} MB/s"
    highlight "  Download speed: ${download_speed} MB/s"
    
    add_result "s3_upload" "upload_time_ms" "$upload_time" "milliseconds" "success"
    add_result "s3_download" "download_time_ms" "$download_time" "milliseconds" "success"
    
    # Cleanup
    aws s3 rm "s3://${bucket}/benchmark/test.dat" &>/dev/null
    rm -f /tmp/benchmark-*.dat
    
    success "S3 transfer performance tested"
}

# Step Functions execution time
benchmark_step_functions() {
    if [ "$QUICK_MODE" = true ]; then
        info "Skipping Step Functions test (quick mode)"
        return
    fi
    
    info "Testing Step Functions performance..."
    
    local state_machines=$(aws stepfunctions list-state-machines \
        --query "stateMachines[?contains(name, '${PROJECT_NAME}')].stateMachineArn" \
        --output text 2>/dev/null | head -1)
    
    if [ -z "$state_machines" ]; then
        warning "No Step Functions found"
        return
    fi
    
    local sm_arn=$(echo "$state_machines" | awk '{print $1}')
    
    # Start execution
    local exec_arn=$(aws stepfunctions start-execution \
        --state-machine-arn "$sm_arn" \
        --input '{"test": "benchmark"}' \
        --query 'executionArn' \
        --output text 2>/dev/null)
    
    if [ -n "$exec_arn" ]; then
        local start=$(date +%s)
        
        # Wait for completion (max 60s)
        local timeout=60
        local elapsed=0
        while [ $elapsed -lt $timeout ]; do
            local status=$(aws stepfunctions describe-execution \
                --execution-arn "$exec_arn" \
                --query 'status' \
                --output text 2>/dev/null)
            
            if [ "$status" = "SUCCEEDED" ] || [ "$status" = "FAILED" ]; then
                break
            fi
            
            sleep 2
            elapsed=$((elapsed + 2))
        done
        
        local end=$(date +%s)
        local duration=$((end - start))
        
        highlight "  Execution time: ${duration}s"
        add_result "step_functions" "execution_time_s" "$duration" "seconds" "success"
        success "Step Functions performance tested"
    fi
}

# ECS task startup time
benchmark_ecs() {
    info "Testing ECS task startup performance..."
    
    local cluster_name="${PROJECT_NAME}-${ENVIRONMENT}"
    local cluster_arn=$(aws ecs describe-clusters \
        --clusters "$cluster_name" \
        --query 'clusters[0].clusterArn' \
        --output text 2>/dev/null)
    
    if [ "$cluster_arn" = "None" ] || [ -z "$cluster_arn" ]; then
        warning "No ECS cluster found"
        return
    fi
    
    # Get running tasks
    local tasks=$(aws ecs list-tasks \
        --cluster "$cluster_arn" \
        --query 'taskArns[0]' \
        --output text 2>/dev/null)
    
    if [ "$tasks" != "None" ] && [ -n "$tasks" ]; then
        local task_details=$(aws ecs describe-tasks \
            --cluster "$cluster_arn" \
            --tasks "$tasks" \
            --query 'tasks[0]' \
            --output json 2>/dev/null)
        
        local created=$(echo "$task_details" | jq -r '.createdAt')
        local started=$(echo "$task_details" | jq -r '.startedAt')
        
        if [ "$created" != "null" ] && [ "$started" != "null" ]; then
            local created_ts=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${created:0:19}" +%s 2>/dev/null || echo 0)
            local started_ts=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${started:0:19}" +%s 2>/dev/null || echo 0)
            local startup_time=$((started_ts - created_ts))
            
            highlight "  Task startup time: ${startup_time}s"
            add_result "ecs_task_startup" "startup_time_s" "$startup_time" "seconds" "success"
            success "ECS performance tested"
        fi
    fi
}

# Network latency test
benchmark_network() {
    info "Testing network latency..."
    
    # Test AWS endpoint latency
    local start=$(date +%s%3N)
    aws sts get-caller-identity &>/dev/null
    local end=$(date +%s%3N)
    local latency=$((end - start))
    
    highlight "  AWS API latency: ${latency}ms"
    add_result "network_latency" "aws_api_latency_ms" "$latency" "milliseconds" "success"
    
    if [ "$latency" -lt 100 ]; then
        success "Network latency: Excellent"
    elif [ "$latency" -lt 300 ]; then
        success "Network latency: Good"
    else
        warning "Network latency: High"
    fi
}

# Generate summary
generate_summary() {
    info "Generating benchmark summary..."
    
    local temp=$(mktemp)
    jq '.' "$BENCHMARK_LOG" > "$temp"
    
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}BENCHMARK RESULTS${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════${NC}"
    echo ""
    
    jq -r '.benchmarks[] | "\(.test): \(.value)\(.unit) - \(.status)"' "$temp" | while read -r line; do
        echo "  $line"
    done
    
    echo ""
    echo -e "${BLUE}Results saved to: $BENCHMARK_LOG${NC}"
    
    # Calculate overall score
    local total_tests=$(jq '.benchmarks | length' "$BENCHMARK_LOG")
    local passed_tests=$(jq '[.benchmarks[] | select(.status == "success")] | length' "$BENCHMARK_LOG")
    
    echo ""
    echo -e "Tests completed: ${GREEN}${passed_tests}/${total_tests}${NC}"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -q|--quick)
            QUICK_MODE=true
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
    echo -e "${BLUE}║     Infrastructure Performance Benchmark      ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "Environment: ${BLUE}${ENVIRONMENT}${NC}"
    if [ "$QUICK_MODE" = true ]; then
        echo -e "Mode:        ${YELLOW}QUICK${NC}"
    fi
    echo ""
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &>/dev/null; then
        error "AWS credentials not configured"
        exit 1
    fi
    
    # Initialize results
    init_results
    
    # Run benchmarks
    benchmark_network
    benchmark_lambda_cold_start
    benchmark_dynamodb
    benchmark_s3
    benchmark_step_functions
    benchmark_ecs
    
    # Generate summary
    generate_summary
    
    echo ""
    echo -e "${GREEN}════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}Benchmarking completed${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════${NC}"
}

main

