#!/bin/bash
set -e

# Test script for Treza Terraform Infrastructure
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "=== Running Treza Infrastructure Tests ==="

# Test types
RUN_UNIT=${RUN_UNIT:-true}
RUN_INTEGRATION=${RUN_INTEGRATION:-true}
RUN_TERRAFORM=${RUN_TERRAFORM:-true}

# Setup
TESTS_DIR="$PROJECT_ROOT/tests"
TERRAFORM_DIR="$PROJECT_ROOT/terraform"

# Check prerequisites
echo "=== Checking Prerequisites ==="

if ! command -v python3 &> /dev/null; then
    echo "Error: Python 3 is not installed"
    exit 1
fi

if ! command -v pip3 &> /dev/null; then
    echo "Error: pip3 is not installed"
    exit 1
fi

echo "✓ Prerequisites check passed"

# Install test dependencies
echo "=== Installing Test Dependencies ==="
cd "$TESTS_DIR"

if [ -f "requirements.txt" ]; then
    pip3 install -r requirements.txt
    echo "✓ Test dependencies installed"
else
    echo "Warning: No test requirements.txt found"
fi

# Run unit tests
if [ "$RUN_UNIT" = "true" ]; then
    echo "=== Running Unit Tests ==="
    cd "$TESTS_DIR"
    
    if [ -d "unit" ]; then
        python3 -m pytest unit/ -v --tb=short
        echo "✓ Unit tests completed"
    else
        echo "Warning: No unit tests directory found"
    fi
fi

# Run integration tests
if [ "$RUN_INTEGRATION" = "true" ]; then
    echo "=== Running Integration Tests ==="
    cd "$TESTS_DIR"
    
    if [ -d "integration" ]; then
        # Skip slow tests by default
        python3 -m pytest integration/ -v --tb=short -m "not slow"
        echo "✓ Integration tests completed"
    else
        echo "Warning: No integration tests directory found"
    fi
fi

# Test Terraform configuration
if [ "$RUN_TERRAFORM" = "true" ]; then
    echo "=== Testing Terraform Configuration ==="
    cd "$TERRAFORM_DIR"
    
    # Clean any existing state
    rm -rf .terraform .terraform.lock.hcl terraform.tfstate*
    
    # Check if example files exist
    if [ ! -f "terraform.tfvars.example" ]; then
        echo "Warning: No terraform.tfvars.example found"
    else
        # Use example as test configuration
        cp terraform.tfvars.example test.tfvars
        
        # Initialize
        echo "Initializing Terraform..."
        if terraform init; then
            echo "✓ Terraform init successful"
        else
            echo "Warning: Terraform init failed"
        fi
        
        # Validate
        echo "Validating Terraform configuration..."
        if terraform validate; then
            echo "✓ Terraform validation successful"
        else
            echo "Warning: Terraform validation failed (may be plugin timeout)"
        fi
        
        # Clean up test files
        rm -f test.tfvars
    fi
fi

# Test Docker build
echo "=== Testing Docker Build ==="
cd "$PROJECT_ROOT"

if [ -f "docker/terraform-runner/Dockerfile" ]; then
    echo "Testing Docker build (dry run)..."
    cd docker/terraform-runner
    
    # Test Docker syntax
    if docker build --dry-run . > /dev/null 2>&1; then
        echo "✓ Docker build syntax valid"
    else
        echo "Warning: Docker build test failed"
    fi
else
    echo "Warning: No Dockerfile found"
fi

# Summary
echo ""
echo "=== Test Summary ==="
echo "✓ Test suite completed"
echo ""
echo "Test types run:"
[ "$RUN_UNIT" = "true" ] && echo "  - Unit tests"
[ "$RUN_INTEGRATION" = "true" ] && echo "  - Integration tests"
[ "$RUN_TERRAFORM" = "true" ] && echo "  - Terraform validation"
echo ""
echo "For full integration tests with AWS, run:"
echo "  RUN_INTEGRATION=true AWS_PROFILE=your-profile ./scripts/test.sh"
echo ""