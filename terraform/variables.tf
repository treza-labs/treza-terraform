# Core Configuration
variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-west-2"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "treza"
}

# Existing DynamoDB Configuration
variable "existing_dynamodb_table_name" {
  description = "Name of existing DynamoDB table from treza-app"
  type        = string
  default     = "treza-enclaves"
}

# Networking Configuration
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones to use"
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b"]
}

# ECS Configuration
variable "ecs_cluster_name" {
  description = "Name of ECS cluster for Terraform runner"
  type        = string
  default     = "treza-infrastructure"
}

variable "terraform_runner_cpu" {
  description = "CPU units for Terraform runner task"
  type        = number
  default     = 1024
}

variable "terraform_runner_memory" {
  description = "Memory (MiB) for Terraform runner task"
  type        = number
  default     = 2048
}

# Step Functions Configuration
variable "deployment_timeout_seconds" {
  description = "Timeout for deployment Step Function"
  type        = number
  default     = 1800  # 30 minutes
}

variable "destroy_timeout_seconds" {
  description = "Timeout for destroy Step Function"
  type        = number
  default     = 1200  # 20 minutes
}

# Monitoring Configuration
variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}