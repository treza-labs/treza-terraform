variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "deployment_step_function_arn" {
  description = "ARN of the deployment Step Functions state machine"
  type        = string
}

variable "cleanup_step_function_arn" {
  description = "ARN of the cleanup Step Functions state machine"
  type        = string
}

variable "dynamodb_table_name" {
  description = "Name of the DynamoDB table"
  type        = string
}

variable "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
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