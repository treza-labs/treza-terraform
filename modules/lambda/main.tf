# Enclave Trigger Lambda Function
resource "aws_lambda_function" "enclave_trigger" {
  filename         = data.archive_file.enclave_trigger_zip.output_path
  function_name    = "${var.name_prefix}-enclave-trigger"
  role            = var.lambda_execution_role_arn
  handler         = "index.handler"
  runtime         = "python3.9"
  timeout         = 60
  
  source_code_hash = data.archive_file.enclave_trigger_zip.output_base64sha256
  
  environment {
    variables = {
      STEP_FUNCTION_ARN = var.step_function_arn
      DYNAMODB_TABLE_NAME = var.dynamodb_table_name
    }
  }
  
  tags = var.tags
}

# Validation Lambda Function
resource "aws_lambda_function" "validation" {
  filename         = local.validation_zip_path
  function_name    = "${var.name_prefix}-validation"
  role            = var.lambda_execution_role_arn
  handler         = "index.handler"
  runtime         = "python3.9"
  timeout         = 300
  
  source_code_hash = filebase64sha256(local.validation_zip_path)
  
  environment {
    variables = {
      DYNAMODB_TABLE_NAME = var.dynamodb_table_name
    }
  }
  
  tags = var.tags
}

# Error Handler Lambda Function
resource "aws_lambda_function" "error_handler" {
  filename         = local.error_handler_zip_path
  function_name    = "${var.name_prefix}-error-handler"
  role            = var.lambda_execution_role_arn
  handler         = "index.handler"
  runtime         = "python3.9"
  timeout         = 60
  
  source_code_hash = filebase64sha256(local.error_handler_zip_path)
  
  environment {
    variables = {
      DYNAMODB_TABLE_NAME = var.dynamodb_table_name
    }
  }
  
  tags = var.tags
}

# Create ZIP files for Lambda functions
data "archive_file" "enclave_trigger_zip" {
  type        = "zip"
  source_dir  = "${path.root}/../lambda/enclave_trigger"
  output_path = "${path.module}/builds/enclave-trigger.zip"
}

# Use pre-built zip files with dependencies from build script
locals {
  validation_zip_path = "${path.module}/builds/validation.zip"
  error_handler_zip_path = "${path.module}/builds/error_handler.zip"
}

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "enclave_trigger" {
  name              = "/aws/lambda/${aws_lambda_function.enclave_trigger.function_name}"
  retention_in_days = var.log_retention_days
  
  tags = var.tags
}

resource "aws_cloudwatch_log_group" "validation" {
  name              = "/aws/lambda/${aws_lambda_function.validation.function_name}"
  retention_in_days = var.log_retention_days
  
  tags = var.tags
}

resource "aws_cloudwatch_log_group" "error_handler" {
  name              = "/aws/lambda/${aws_lambda_function.error_handler.function_name}"
  retention_in_days = var.log_retention_days
  
  tags = var.tags
}