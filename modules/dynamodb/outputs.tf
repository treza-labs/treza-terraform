output "table_arn" {
  description = "ARN of the DynamoDB table"
  value       = data.aws_dynamodb_table.existing.arn
}

output "table_name" {
  description = "Name of the DynamoDB table"
  value       = data.aws_dynamodb_table.existing.name
}

output "stream_arn" {
  description = "ARN of the DynamoDB stream"
  value       = data.aws_dynamodb_table.existing.stream_arn
}

output "event_source_mapping_uuid" {
  description = "UUID of the Lambda event source mapping"
  value       = aws_lambda_event_source_mapping.dynamodb_stream.uuid
}