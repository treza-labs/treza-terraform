# Create or use existing DynamoDB table for enclaves
resource "aws_dynamodb_table" "enclaves" {
  name           = var.table_name
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "id"
  stream_enabled = true
  stream_view_type = "NEW_AND_OLD_IMAGES"
  
  lifecycle {
    ignore_changes = [
      # Ignore changes that might cause unnecessary recreations
      stream_view_type,
    ]
  }
  
  attribute {
    name = "id"
    type = "S"
  }
  
  # Add GSI for status queries
  global_secondary_index {
    name     = "status-index"
    hash_key = "status"
    
    projection_type = "ALL"
  }
  
  # Add GSI for wallet address queries
  global_secondary_index {
    name     = "WalletIndex"
    hash_key = "walletAddress"
    
    projection_type = "ALL"
  }
  
  attribute {
    name = "status"
    type = "S"
  }
  
  attribute {
    name = "walletAddress"
    type = "S"
  }
  
  tags = var.tags
}

# Event Source Mapping for Lambda trigger
resource "aws_lambda_event_source_mapping" "dynamodb_stream" {
  event_source_arn  = aws_dynamodb_table.enclaves.stream_arn
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