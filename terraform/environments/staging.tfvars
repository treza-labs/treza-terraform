# Staging Environment Configuration  
# Copy to terraform.tfvars and customize for your staging environment

# Core Configuration
aws_region    = "us-west-2"
environment   = "staging"
project_name  = "treza"

# Existing DynamoDB Configuration
existing_dynamodb_table_name = "treza-enclaves-staging"

# Networking Configuration
vpc_cidr           = "10.1.0.0/16"  # Different CIDR for staging
availability_zones = ["us-west-2a", "us-west-2b", "us-west-2c"]  # More AZs for HA

# ECS Configuration - Medium instances for staging
ecs_cluster_name        = "treza-staging-infrastructure"
terraform_runner_cpu    = 1024  # Production-like sizing
terraform_runner_memory = 2048  # Production-like sizing

# Timeout Configuration (production-like)
deployment_timeout_seconds = 1800  # 30 minutes
destroy_timeout_seconds    = 1200  # 20 minutes

# Monitoring Configuration
log_retention_days = 14  # Medium retention

# Security Configuration
allowed_ssh_cidrs = ["10.1.0.0/16", "172.16.0.0/12"]  # Private networks only
management_cidrs  = ["10.1.10.0/24"]  # More restricted management access

security_group_rules = {
  ssh_port         = 22
  enclave_port     = 8443    # HTTPS port for staging
  monitoring_port  = 9443    # Secure monitoring
  allowed_protocols = ["tcp"]  # More restrictive for staging
}

# Staging Tags
additional_tags = {
  Team        = "infrastructure"
  CostCenter  = "engineering"
  Environment = "staging"
  Purpose     = "pre-production-testing"
  Schedule    = "business-hours"  # Can be shut down nights/weekends
}