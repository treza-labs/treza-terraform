output "cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = aws_ecs_cluster.main.arn
}

output "cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.main.name
}

output "terraform_runner_task_definition_arn" {
  description = "ARN of the Terraform runner task definition"
  value       = aws_ecs_task_definition.terraform_runner.arn
}

output "terraform_runner_task_definition_family" {
  description = "Family of the Terraform runner task definition"
  value       = aws_ecs_task_definition.terraform_runner.family
}

output "ecr_repository_url" {
  description = "URL of the ECR repository for Terraform runner"
  value       = aws_ecr_repository.terraform_runner.repository_url
}

output "log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.terraform_runner.name
}