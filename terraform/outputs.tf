# Core Infrastructure Outputs
output "vpc_id" {
  description = "ID of the VPC"
  value       = module.networking.vpc_id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = module.networking.private_subnet_ids
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = module.networking.public_subnet_ids
}

# State Backend Outputs
output "terraform_state_bucket" {
  description = "S3 bucket for Terraform state"
  value       = module.state_backend.bucket_name
}

output "terraform_state_dynamodb_table" {
  description = "DynamoDB table for Terraform state locking"
  value       = module.state_backend.dynamodb_table_name
}

# Step Functions Outputs
output "deployment_state_machine_arn" {
  description = "ARN of the deployment Step Functions state machine"
  value       = module.step_functions.deployment_state_machine_arn
}

output "cleanup_state_machine_arn" {
  description = "ARN of the cleanup Step Functions state machine"
  value       = module.step_functions.cleanup_state_machine_arn
}

# ECS Outputs
output "ecs_cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = module.ecs.cluster_arn
}

output "terraform_runner_task_definition_arn" {
  description = "ARN of the Terraform runner task definition"
  value       = module.ecs.terraform_runner_task_definition_arn
}

# Lambda Outputs
output "enclave_trigger_function_arn" {
  description = "ARN of the enclave trigger Lambda function"
  value       = module.lambda_functions.enclave_trigger_arn
}

output "validation_function_arn" {
  description = "ARN of the validation Lambda function"
  value       = module.lambda_functions.validation_function_arn
}

# Security Group Outputs
output "shared_enclave_security_group_id" {
  description = "ID of the shared security group for all enclave instances"
  value       = module.networking.shared_enclave_security_group_id
  sensitive   = false
}

output "terraform_runner_security_group_id" {
  description = "ID of the security group for Terraform runner tasks"
  value       = module.networking.terraform_runner_security_group_id
  sensitive   = false
}

# Monitoring Outputs
output "cloudwatch_dashboard_url" {
  description = "URL of the CloudWatch dashboard"
  value       = module.monitoring.dashboard_url
}