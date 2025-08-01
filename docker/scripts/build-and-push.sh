#!/bin/bash
set -e

# Configuration
REGISTRY_REGION=${AWS_REGION:-us-west-2}
IMAGE_NAME=${IMAGE_NAME:-treza-dev-terraform-runner}
TAG=${TAG:-latest}

echo "=== Building and Pushing Terraform Runner Docker Image ==="
echo "Region: $REGISTRY_REGION"
echo "Image Name: $IMAGE_NAME"
echo "Tag: $TAG"

# Get AWS account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
if [ -z "$ACCOUNT_ID" ]; then
    echo "ERROR: Could not get AWS account ID. Make sure AWS CLI is configured."
    exit 1
fi

REGISTRY_URI="$ACCOUNT_ID.dkr.ecr.$REGISTRY_REGION.amazonaws.com"
FULL_IMAGE_NAME="$REGISTRY_URI/$IMAGE_NAME:$TAG"

echo "Registry URI: $REGISTRY_URI"
echo "Full Image Name: $FULL_IMAGE_NAME"

# Login to ECR
echo "=== Logging into ECR ==="
aws ecr get-login-password --region $REGISTRY_REGION | docker login --username AWS --password-stdin $REGISTRY_URI

# Create ECR repository if it doesn't exist
echo "=== Creating ECR repository if needed ==="
aws ecr describe-repositories --repository-names $IMAGE_NAME --region $REGISTRY_REGION 2>/dev/null || \
aws ecr create-repository --repository-name $IMAGE_NAME --region $REGISTRY_REGION

# Build Docker image
echo "=== Building Docker image ==="
cd "$(dirname "$0")/../terraform-runner"
docker build -t $IMAGE_NAME:$TAG .
docker tag $IMAGE_NAME:$TAG $FULL_IMAGE_NAME

# Push to ECR
echo "=== Pushing to ECR ==="
docker push $FULL_IMAGE_NAME

echo "=== Build and Push Complete ==="
echo "Image: $FULL_IMAGE_NAME"