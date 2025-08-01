output "deployment_state_machine_arn" {
  description = "ARN of the deployment Step Functions state machine"
  value       = aws_sfn_state_machine.deployment.arn
}

output "deployment_state_machine_name" {
  description = "Name of the deployment Step Functions state machine"
  value       = aws_sfn_state_machine.deployment.name
}

output "cleanup_state_machine_arn" {
  description = "ARN of the cleanup Step Functions state machine"
  value       = aws_sfn_state_machine.cleanup.arn
}

output "cleanup_state_machine_name" {
  description = "Name of the cleanup Step Functions state machine"
  value       = aws_sfn_state_machine.cleanup.name
}

output "log_group_arn" {
  description = "ARN of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.step_functions.arn
}