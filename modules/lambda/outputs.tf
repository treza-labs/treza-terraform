output "enclave_trigger_arn" {
  description = "ARN of the enclave trigger Lambda function"
  value       = aws_lambda_function.enclave_trigger.arn
}

output "enclave_trigger_function_name" {
  description = "Name of the enclave trigger Lambda function"
  value       = aws_lambda_function.enclave_trigger.function_name
}

output "validation_function_arn" {
  description = "ARN of the validation Lambda function"
  value       = aws_lambda_function.validation.arn
}

output "validation_function_name" {
  description = "Name of the validation Lambda function"
  value       = aws_lambda_function.validation.function_name
}

output "error_handler_function_arn" {
  description = "ARN of the error handler Lambda function"
  value       = aws_lambda_function.error_handler.arn
}

output "error_handler_function_name" {
  description = "Name of the error handler Lambda function"
  value       = aws_lambda_function.error_handler.function_name
}

output "status_monitor_function_arn" {
  description = "ARN of the status monitor Lambda function"
  value       = aws_lambda_function.status_monitor.arn
}

output "status_monitor_function_name" {
  description = "Name of the status monitor Lambda function"
  value       = aws_lambda_function.status_monitor.function_name
}