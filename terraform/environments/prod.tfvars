# Production Environment Configuration
# Copy to terraform.tfvars and customize for your production environment

# Core Configuration
aws_region    = "us-west-2"
environment   = "prod"
project_name  = "treza"

# Existing DynamoDB Configuration
existing_dynamodb_table_name = "treza-enclaves-prod"

# Networking Configuration
vpc_cidr           = "10.2.0.0/16"  # Different CIDR for production
availability_zones = ["us-west-2a", "us-west-2b", "us-west-2c"]  # Multi-AZ for HA

# ECS Configuration - Large instances for production
ecs_cluster_name        = "treza-prod-infrastructure"
terraform_runner_cpu    = 2048  # High performance for production
terraform_runner_memory = 4096  # High memory for complex deployments

# Timeout Configuration (generous for production)
deployment_timeout_seconds = 2400  # 40 minutes
destroy_timeout_seconds    = 1800  # 30 minutes

# Monitoring Configuration
log_retention_days = 90  # Extended retention for compliance

# Production Tags
additional_tags = {
  Team        = "infrastructure"
  CostCenter  = "engineering"
  Environment = "production"
  Purpose     = "production-workloads"
  Backup      = "required"
  Monitoring  = "critical"
  SLA         = "99.9"
}