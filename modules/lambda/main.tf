# Enclave Trigger Lambda Function
resource "aws_lambda_function" "enclave_trigger" {
  filename         = local.enclave_trigger_zip_path
  function_name    = "${var.name_prefix}-enclave-trigger"
  role            = var.lambda_execution_role_arn
  handler         = "index.handler"
  runtime         = "python3.9"
  timeout         = 60
  
  source_code_hash = filebase64sha256(local.enclave_trigger_zip_path)
  
  lifecycle {
    replace_triggered_by = [null_resource.build_lambda_functions]
    ignore_changes      = [source_code_hash]
  }
  
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
  
  lifecycle {
    replace_triggered_by = [null_resource.build_lambda_functions]
    ignore_changes      = [source_code_hash]
  }
  
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
  
  lifecycle {
    replace_triggered_by = [null_resource.build_lambda_functions]
    ignore_changes      = [source_code_hash]
  }
  
  environment {
    variables = {
      DYNAMODB_TABLE_NAME = var.dynamodb_table_name
    }
  }
  
  tags = var.tags
}

# Create ZIP files for Lambda functions
# Build Lambda functions with dependencies before deploying
resource "null_resource" "build_lambda_functions" {
  triggers = {
    # Force rebuild every time to ensure dependencies are included
    always_run = timestamp()
  }

  provisioner "local-exec" {
    command     = "./build-functions.sh"
    working_dir = path.module
  }
}

# Lambda functions use pre-built zip files from build script

# Data sources for Lambda function packages
# Use the pre-built zip files created by the build script
locals {
  validation_zip_path    = "${path.module}/builds/validation.zip"
  error_handler_zip_path = "${path.module}/builds/error_handler.zip"
  enclave_trigger_zip_path = "${path.module}/builds/enclave_trigger.zip"
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