output "dashboard_url" {
  description = "URL of the CloudWatch dashboard"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.main.dashboard_name}"
}

output "dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.main.dashboard_name
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for alerts (if created)"
  value       = var.create_sns_topic ? aws_sns_topic.alerts[0].arn : ""
}

output "step_function_alarm_arn" {
  description = "ARN of the Step Function failure alarm"
  value       = aws_cloudwatch_metric_alarm.step_function_failures.arn
}

output "ecs_task_alarm_arn" {
  description = "ARN of the ECS task failure alarm"
  value       = aws_cloudwatch_metric_alarm.ecs_task_failures.arn
}