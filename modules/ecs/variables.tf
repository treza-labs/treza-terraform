variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "cluster_name" {
  description = "Name of the ECS cluster"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for ECS tasks"
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group ID for ECS tasks"
  type        = string
}

variable "task_execution_role_arn" {
  description = "ARN of the ECS task execution role"
  type        = string
}

variable "task_role_arn" {
  description = "ARN of the ECS task role"
  type        = string
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

variable "s3_state_bucket_name" {
  description = "Name of the S3 bucket for Terraform state"
  type        = string
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

variable "shared_enclave_security_group_id" {
  description = "ID of the shared security group for all enclave instances"
  type        = string
  default     = ""
}