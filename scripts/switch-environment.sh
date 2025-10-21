#!/bin/bash
set -euo pipefail

# Environment switching utility for Treza Terraform infrastructure
# Usage: ./scripts/switch-environment.sh <environment>

ENVIRONMENT=${1:-}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$PROJECT_ROOT/terraform"

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

warning() {
    echo -e "${YELLOW}⚠️  $*${NC}"
}

error() {
    echo -e "${RED}❌ $*${NC}"
}

info() {
    echo -e "${BLUE}ℹ️  $*${NC}"
}

usage() {
    echo -e "${BLUE}Treza Environment Switcher${NC}"
    echo ""
    echo "Usage: $0 <environment>"
    echo ""
    echo "Available environments:"
    if [ -d "$TERRAFORM_DIR/environments" ]; then
        for file in "$TERRAFORM_DIR/environments"/*.tfvars; do
            if [ -f "$file" ]; then
                env_name=$(basename "$file" .tfvars)
                echo "  - $env_name"
            fi
        done
    else
        echo "  No environments found in $TERRAFORM_DIR/environments"
    fi
    echo ""
    echo "Examples:"
    echo "  $0 dev      # Switch to development environment"
    echo "  $0 staging  # Switch to staging environment"
    echo "  $0 prod     # Switch to production environment"
    echo ""
    echo "This script will:"
    echo "  1. Validate the environment configuration exists"
    echo "  2. Copy environment-specific files to terraform directory"
    echo "  3. Initialize Terraform with the correct backend"
    echo "  4. Show current environment status"
}

show_current_environment() {
    echo -e "${PURPLE}Current Environment Status:${NC}"
    
    # Check if terraform.tfvars exists and show environment
    if [ -f "$TERRAFORM_DIR/terraform.tfvars" ]; then
        current_env=$(grep '^environment' "$TERRAFORM_DIR/terraform.tfvars" 2>/dev/null | cut -d'"' -f2 || echo "unknown")
        echo "  Environment: $current_env"
        
        # Show backend info
        if [ -f "$TERRAFORM_DIR/backend.conf" ]; then
            bucket=$(grep '^bucket' "$TERRAFORM_DIR/backend.conf" 2>/dev/null | cut -d'"' -f2 || echo "unknown")
            region=$(grep '^region' "$TERRAFORM_DIR/backend.conf" 2>/dev/null | cut -d'"' -f2 || echo "unknown")
            echo "  Backend Bucket: $bucket"
            echo "  Backend Region: $region"
        else
            warning "No backend configuration found"
        fi
        
        # Check if terraform is initialized
        if [ -d "$TERRAFORM_DIR/.terraform" ]; then
            success "Terraform initialized"
        else
            warning "Terraform not initialized"
        fi
    else
        warning "No environment currently configured"
    fi
}

validate_environment() {
    local env=$1
    
    # Check if environment file exists
    local env_file="$TERRAFORM_DIR/environments/${env}.tfvars"
    if [ ! -f "$env_file" ]; then
        error "Environment file not found: $env_file"
        echo ""
        echo "Available environments:"
        for file in "$TERRAFORM_DIR/environments"/*.tfvars; do
            if [ -f "$file" ]; then
                env_name=$(basename "$file" .tfvars)
                echo "  - $env_name"
            fi
        done
        return 1
    fi
    
    # Check if backend file exists
    local backend_file="$TERRAFORM_DIR/environments/backend-${env}.conf"
    if [ ! -f "$backend_file" ]; then
        error "Backend configuration not found: $backend_file"
        return 1
    fi
    
    success "Environment configuration validated: $env"
    return 0
}

switch_environment() {
    local env=$1
    
    info "Switching to $env environment..."
    
    # Validate environment first
    if ! validate_environment "$env"; then
        return 1
    fi
    
    # Copy environment files
    local env_file="$TERRAFORM_DIR/environments/${env}.tfvars"
    local backend_file="$TERRAFORM_DIR/environments/backend-${env}.conf"
    
    info "Copying environment configuration..."
    cp "$env_file" "$TERRAFORM_DIR/terraform.tfvars"
    cp "$backend_file" "$TERRAFORM_DIR/backend.conf"
    
    success "Environment files copied"
    
    # Clean previous terraform state
    if [ -d "$TERRAFORM_DIR/.terraform" ]; then
        warning "Cleaning previous Terraform initialization..."
        rm -rf "$TERRAFORM_DIR/.terraform"
        rm -f "$TERRAFORM_DIR/.terraform.lock.hcl"
    fi
    
    # Initialize terraform
    info "Initializing Terraform for $env environment..."
    cd "$TERRAFORM_DIR"
    
    if terraform init -backend-config=backend.conf; then
        success "Terraform initialized successfully"
    else
        error "Failed to initialize Terraform"
        return 1
    fi
    
    # Validate configuration
    info "Validating Terraform configuration..."
    if terraform validate; then
        success "Terraform configuration is valid"
    else
        error "Terraform configuration validation failed"
        return 1
    fi
    
    success "Successfully switched to $env environment!"
    echo ""
    show_current_environment
    
    # Show next steps
    echo ""
    echo -e "${PURPLE}Next Steps:${NC}"
    echo "  make plan ENV=$env     # Generate deployment plan"
    echo "  make apply ENV=$env    # Apply changes"
    echo "  make validate-all ENV=$env  # Run all validations"
    echo "  make health-check ENV=$env  # Check infrastructure health"
}

# Main script
if [ -z "$ENVIRONMENT" ]; then
    usage
    exit 1
fi

case "$ENVIRONMENT" in
    -h|--help|help)
        usage
        exit 0
        ;;
    status|current)
        show_current_environment
        exit 0
        ;;
    *)
        log "🔄 Environment Switcher - Target: $ENVIRONMENT"
        echo "================================================================="
        
        if switch_environment "$ENVIRONMENT"; then
            exit 0
        else
            error "Failed to switch to $ENVIRONMENT environment"
            exit 1
        fi
        ;;
esac
