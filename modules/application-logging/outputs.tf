output "application_log_group_name" {
  description = "Name of the application log group"
  value       = aws_cloudwatch_log_group.application.name
}

output "application_log_group_arn" {
  description = "ARN of the application log group"
  value       = aws_cloudwatch_log_group.application.arn
}

output "stdout_log_group_name" {
  description = "Name of the stdout log group"
  value       = aws_cloudwatch_log_group.container_stdout.name
}

output "stderr_log_group_name" {
  description = "Name of the stderr log group"
  value       = aws_cloudwatch_log_group.container_stderr.name
}

output "cloudwatch_agent_role_arn" {
  description = "ARN of the CloudWatch agent IAM role"
  value       = aws_iam_role.cloudwatch_agent.arn
}

output "cloudwatch_agent_instance_profile_name" {
  description = "Name of the CloudWatch agent instance profile"
  value       = aws_iam_instance_profile.cloudwatch_agent.name
}
