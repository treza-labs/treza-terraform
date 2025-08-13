#!/bin/bash
set -e

# Build script for Lambda functions
echo "=== Building Lambda Functions ==="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
LAMBDA_SRC_DIR="$PROJECT_ROOT/lambda"
BUILDS_DIR="$SCRIPT_DIR/builds"

# Create builds directory
mkdir -p "$BUILDS_DIR"

# Function to build a Lambda function
build_function() {
    local function_name=$1
    local src_dir="$LAMBDA_SRC_DIR/$function_name"
    local build_file="$BUILDS_DIR/${function_name}.zip"
    
    echo "Building $function_name..."
    
    if [ ! -d "$src_dir" ]; then
        echo "Error: Source directory $src_dir not found"
        return 1
    fi
    
    # Create temporary build directory
    local temp_dir=$(mktemp -d)
    
    # Copy source files
    cp -r "$src_dir"/* "$temp_dir/"
    
    # Install dependencies if requirements.txt exists
    if [ -f "$temp_dir/requirements.txt" ]; then
        echo "Installing dependencies for $function_name..."
        pip3 install -r "$temp_dir/requirements.txt" -t "$temp_dir/" --quiet
    fi
    
    # Remove unnecessary files
    find "$temp_dir" -name "*.pyc" -delete
    find "$temp_dir" -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
    find "$temp_dir" -name "*.dist-info" -type d -exec rm -rf {} + 2>/dev/null || true
    
    # Create ZIP file
    cd "$temp_dir"
    zip -r "$build_file" . -x "requirements.txt" > /dev/null
    cd - > /dev/null
    
    # Cleanup
    rm -rf "$temp_dir"
    
    echo "✓ Built $function_name -> $(basename "$build_file")"
    echo "  Size: $(du -h "$build_file" | cut -f1)"
}

# Build all Lambda functions
echo "Source directory: $LAMBDA_SRC_DIR"
echo "Builds directory: $BUILDS_DIR"
echo ""

if [ ! -d "$LAMBDA_SRC_DIR" ]; then
    echo "Error: Lambda source directory not found at $LAMBDA_SRC_DIR"
    exit 1
fi

# Build each function
for func_dir in "$LAMBDA_SRC_DIR"/*; do
    if [ -d "$func_dir" ]; then
        func_name=$(basename "$func_dir")
        build_function "$func_name"
    fi
done

echo ""
echo "=== Build Summary ==="
ls -la "$BUILDS_DIR"
echo ""
echo "✅ All Lambda functions built successfully!"
echo ""
echo "Usage:"
echo "  terraform plan   # Will use the built packages"
echo "  terraform apply  # Will deploy the functions"