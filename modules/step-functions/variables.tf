variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "ecs_cluster_arn" {
  description = "ARN of the ECS cluster"
  type        = string
}

variable "ecs_task_definition_arn" {
  description = "ARN of the ECS task definition"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for ECS tasks"
  type        = list(string)
}

variable "vpc_id" {
  description = "VPC ID for enclave deployments"
  type        = string
}

variable "security_group_id" {
  description = "Security group ID for ECS tasks"
  type        = string
}

variable "step_functions_role_arn" {
  description = "ARN of the Step Functions execution role"
  type        = string
}

variable "dynamodb_table_name" {
  description = "Name of the DynamoDB table"
  type        = string
}

variable "validation_lambda_arn" {
  description = "ARN of the validation Lambda function"
  type        = string
  default     = ""
}

variable "error_handler_lambda_arn" {
  description = "ARN of the error handler Lambda function"
  type        = string
  default     = ""
}

variable "deployment_timeout" {
  description = "Timeout for deployment Step Function in seconds"
  type        = number
  default     = 1800
}

variable "destroy_timeout" {
  description = "Timeout for destroy Step Function in seconds"
  type        = number
  default     = 1200
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