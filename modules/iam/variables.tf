variable "name_prefix" {
  description = "Name prefix for all resources"
  type        = string
}

variable "dynamodb_table_arn" {
  description = "ARN of the DynamoDB table for enclave data"
  type        = string
}

variable "s3_state_bucket_name" {
  description = "Name of the S3 bucket for Terraform state"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}