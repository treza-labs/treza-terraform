# Enable DynamoDB Streams on existing table
resource "aws_dynamodb_table" "enclaves_streams" {
  count = var.enable_streams ? 1 : 0
  
  name           = var.table_name
  billing_mode   = "PAY_PER_REQUEST"
  stream_enabled = true
  stream_view_type = "NEW_AND_OLD_IMAGES"
  
  # We're not creating a new table, just enabling streams
  # This is a workaround for enabling streams on existing table
  lifecycle {
    ignore_changes = [
      attribute,
      global_secondary_index,
      local_secondary_index,
      ttl,
      billing_mode,
      read_capacity,
      write_capacity,
      point_in_time_recovery,
      server_side_encryption,
      tags,
      tags_all
    ]
  }
  
  tags = var.tags
}

# Event Source Mapping for Lambda trigger
resource "aws_lambda_event_source_mapping" "dynamodb_stream" {
  event_source_arn  = var.enable_streams ? aws_dynamodb_table.enclaves_streams[0].stream_arn : data.aws_dynamodb_table.existing.stream_arn
  function_name     = var.lambda_trigger_arn
  starting_position = "LATEST"
  
  filter_criteria {
    filter {
      pattern = jsonencode({
        eventName = ["INSERT", "MODIFY"]
        dynamodb = {
          NewImage = {
            status = {
              S = ["PENDING_DEPLOY", "PENDING_DESTROY"]
            }
          }
        }
      })
    }
  }
  
  depends_on = [var.lambda_trigger_arn]
}

# Data source for existing DynamoDB table
data "aws_dynamodb_table" "existing" {
  name = var.table_name
}