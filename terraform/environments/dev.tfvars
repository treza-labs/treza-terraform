# Development Environment Configuration
# Copy to terraform.tfvars and customize for your dev environment

# Core Configuration
aws_region    = "us-west-2"
environment   = "dev"
project_name  = "treza"

# Existing DynamoDB Configuration
# Update this with your actual DynamoDB table name from treza-app
existing_dynamodb_table_name = "treza-enclaves-dev"

# Networking Configuration
vpc_cidr           = "10.0.0.0/16"
availability_zones = ["us-west-2a"]  # Single AZ for dev to avoid EIP limits

# ECS Configuration - Small instances for dev
ecs_cluster_name        = "treza-dev-infrastructure"
terraform_runner_cpu    = 512   # Smaller for cost savings
terraform_runner_memory = 1024  # Smaller for cost savings

# Timeout Configuration (shorter for dev)
deployment_timeout_seconds = 1200  # 20 minutes
destroy_timeout_seconds    = 900   # 15 minutes

# Monitoring Configuration
log_retention_days = 7  # Shorter retention for cost savings

# Security Configuration
allowed_ssh_cidrs = ["10.0.0.0/16", "172.16.0.0/12"]  # Private networks only
management_cidrs  = ["10.0.0.0/16"]

security_group_rules = {
  ssh_port         = 22
  enclave_port     = 8080
  monitoring_port  = 9090
  allowed_protocols = ["tcp", "udp", "icmp"]  # More permissive for dev
}

# Development Tags
additional_tags = {
  Team         = "infrastructure"
  CostCenter   = "engineering"
  Environment  = "development"
  Purpose      = "testing-validation"
  AutoShutdown = "true"  # For cost management
}