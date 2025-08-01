variable "table_name" {
  description = "Name of the existing DynamoDB table"
  type        = string
}

variable "lambda_trigger_arn" {
  description = "ARN of the Lambda function to trigger on DynamoDB stream events"
  type        = string
}

variable "enable_streams" {
  description = "Whether to enable DynamoDB streams (set to false if streams already enabled)"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}