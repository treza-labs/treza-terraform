# CloudWatch Log Group for Step Functions
resource "aws_cloudwatch_log_group" "step_functions" {
  name              = "/aws/stepfunctions/${var.name_prefix}-deployment"
  retention_in_days = var.log_retention_days
  
  tags = var.tags
}

# Deployment State Machine
resource "aws_sfn_state_machine" "deployment" {
  name     = "${var.name_prefix}-deployment"
  role_arn = var.step_functions_role_arn
  
  # Temporarily disabled logging configuration to resolve IAM permissions issue
  # Will be re-enabled after initial deployment
  # logging_configuration {
  #   log_destination        = "${aws_cloudwatch_log_group.step_functions.arn}:*"
  #   include_execution_data = true
  #   level                  = "ALL"
  # }
  
  definition = jsonencode({
    Comment = "Treza Enclave Deployment Workflow"
    StartAt = "ValidateDeploymentRequest"
    TimeoutSeconds = var.deployment_timeout
    
    States = {
      ValidateDeploymentRequest = {
        Type = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = var.validation_lambda_arn
          Payload = {
            "enclave_id.$" = "$.enclave_id"
            "action.$" = "$.action"
            "configuration.$" = "$.configuration"
          }
        }
        ResultPath = "$.validation_result"
        Next = "CheckValidationResult"
        Retry = [
          {
            ErrorEquals = ["Lambda.ServiceException", "Lambda.AWSLambdaException", "Lambda.SdkClientException"]
            IntervalSeconds = 5
            MaxAttempts = 3
            BackoffRate = 2.0
          }
        ]
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Next = "UpdateStatusToFailed"
            ResultPath = "$.error"
          }
        ]
      }
      
      CheckValidationResult = {
        Type = "Choice"
        Choices = [
          {
            Variable = "$.validation_result.Payload.valid"
            BooleanEquals = true
            Next = "UpdateStatusToInProgress"
          }
        ]
        Default = "UpdateStatusToFailed"
      }
      
      UpdateStatusToInProgress = {
        Type = "Task"
        Resource = "arn:aws:states:::dynamodb:updateItem"
        Parameters = {
          TableName = var.dynamodb_table_name
          Key = {
            id = {
              "S.$" = "$.enclave_id"
            }
          }
          UpdateExpression = "SET #status = :status, #updated_at = :timestamp"
          ExpressionAttributeNames = {
            "#status" = "status"
            "#updated_at" = "updated_at"
          }
          ExpressionAttributeValues = {
            ":status" = {
              S = "DEPLOYING"
            }
            ":timestamp" = {
              "S.$" = "$$.State.EnteredTime"
            }
          }
        }
        ResultPath = "$.update_result"
        Next = "RunTerraformDeployment"
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Next = "UpdateStatusToFailed"
            ResultPath = "$.error"
          }
        ]
      }
      
      RunTerraformDeployment = {
        Type = "Task"
        Resource = "arn:aws:states:::ecs:runTask.sync"
        Parameters = {
          LaunchType = "FARGATE"
          Cluster = var.ecs_cluster_arn
          TaskDefinition = var.ecs_task_definition_arn
          NetworkConfiguration = {
            AwsvpcConfiguration = {
              Subnets = var.subnet_ids
              SecurityGroups = [var.security_group_id]
              AssignPublicIp = "DISABLED"
            }
          }
          Overrides = {
            ContainerOverrides = [
              {
                Name = "terraform-runner"
                Environment = [
                  {
                    Name = "ENCLAVE_ID"
                    "Value.$" = "$.enclave_id"
                  },
                  {
                    Name = "ACTION"
                    Value = "deploy"
                  },
                  {
                    Name = "CONFIGURATION"
                    "Value.$" = "$.configuration"
                  }
                ]
              }
            ]
          }
        }
        ResultPath = "$.terraform_result"
        Next = "CheckDeploymentResult"
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Next = "UpdateStatusToFailed"
            ResultPath = "$.error"
          }
        ]
      }
      
      CheckDeploymentResult = {
        Type = "Choice"
        Choices = [
          {
            Variable = "$.terraform_result.LastStatus"
            StringEquals = "STOPPED"
            Next = "CheckExitCode"
          }
        ]
        Default = "UpdateStatusToFailed"
      }
      
      CheckExitCode = {
        Type = "Choice"
        Choices = [
          {
            Variable = "$.terraform_result.Containers[0].ExitCode"
            NumericEquals = 0
            Next = "UpdateStatusToDeployed"
          }
        ]
        Default = "UpdateStatusToFailed"
      }
      
      UpdateStatusToDeployed = {
        Type = "Task"
        Resource = "arn:aws:states:::dynamodb:updateItem"
        Parameters = {
          TableName = var.dynamodb_table_name
          Key = {
            id = {
              "S.$" = "$.enclave_id"
            }
          }
          UpdateExpression = "SET #status = :status, #updated_at = :timestamp"
          ExpressionAttributeNames = {
            "#status" = "status"
            "#updated_at" = "updated_at"
          }
          ExpressionAttributeValues = {
            ":status" = {
              S = "DEPLOYED"
            }
            ":timestamp" = {
              "S.$" = "$$.State.EnteredTime"
            }
          }
        }
        End = true
      }
      
      UpdateStatusToFailed = {
        Type = "Task"
        Resource = "arn:aws:states:::dynamodb:updateItem"
        Parameters = {
          TableName = var.dynamodb_table_name
          Key = {
            id = {
              "S.$" = "$.enclave_id"
            }
          }
          UpdateExpression = "SET #status = :status, #updated_at = :timestamp, #error = :error"
          ExpressionAttributeNames = {
            "#status" = "status"
            "#updated_at" = "updated_at"
            "#error" = "error_message"
          }
          ExpressionAttributeValues = {
            ":status" = {
              S = "FAILED"
            }
            ":timestamp" = {
              "S.$" = "$$.State.EnteredTime"
            }
            ":error" = {
              "S.$" = "$.validation_result.Payload.message"
            }
          }
        }
        Next = "NotifyError"
      }
      
      NotifyError = {
        Type = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = var.error_handler_lambda_arn
          Payload = {
            "execution_name.$" = "$$.Execution.Name"
            "execution_arn.$" = "$$.Execution.Name"
            "state_machine.$" = "$$.StateMachine.Name"
            "error_message" = "Step Functions execution failed"
          }
        }
        End = true
      }
    }
  })
  
  tags = var.tags
}

# Cleanup State Machine
resource "aws_sfn_state_machine" "cleanup" {
  name     = "${var.name_prefix}-cleanup"
  role_arn = var.step_functions_role_arn
  
  # Temporarily disabled logging configuration to resolve IAM permissions issue
  # Will be re-enabled after initial deployment
  # logging_configuration {
  #   log_destination        = "${aws_cloudwatch_log_group.step_functions.arn}:*"
  #   include_execution_data = true
  #   level                  = "ALL"
  # }
  
  definition = jsonencode({
    Comment = "Treza Enclave Cleanup Workflow"
    StartAt = "UpdateStatusToDestroying"
    TimeoutSeconds = var.destroy_timeout
    
    States = {
      UpdateStatusToDestroying = {
        Type = "Task"
        Resource = "arn:aws:states:::dynamodb:updateItem"
        Parameters = {
          TableName = var.dynamodb_table_name
          Key = {
            id = {
              "S.$" = "$.enclave_id"
            }
          }
          UpdateExpression = "SET #status = :status, #updated_at = :timestamp"
          ExpressionAttributeNames = {
            "#status" = "status"
            "#updated_at" = "updated_at"
          }
          ExpressionAttributeValues = {
            ":status" = {
              S = "DESTROYING"
            }
            ":timestamp" = {
              "S.$" = "$$.State.EnteredTime"
            }
          }
        }
        ResultPath = "$.update_result"
        Next = "RunTerraformDestroy"
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Next = "UpdateStatusToFailed"
            ResultPath = "$.error"
          }
        ]
      }
      
      RunTerraformDestroy = {
        Type = "Task"
        Resource = "arn:aws:states:::ecs:runTask.sync"
        Parameters = {
          LaunchType = "FARGATE"
          Cluster = var.ecs_cluster_arn
          TaskDefinition = var.ecs_task_definition_arn
          NetworkConfiguration = {
            AwsvpcConfiguration = {
              Subnets = var.subnet_ids
              SecurityGroups = [var.security_group_id]
              AssignPublicIp = "DISABLED"
            }
          }
          Overrides = {
            ContainerOverrides = [
              {
                Name = "terraform-runner"
                Environment = [
                  {
                    Name = "ENCLAVE_ID"
                    "Value.$" = "$.enclave_id"
                  },
                  {
                    Name = "ACTION"
                    Value = "destroy"
                  }
                ]
              }
            ]
          }
        }
        ResultPath = "$.terraform_result"
        Next = "CheckDestroyResult"
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Next = "UpdateStatusToFailed"
            ResultPath = "$.error"
          }
        ]
      }
      
      CheckDestroyResult = {
        Type = "Choice"
        Choices = [
          {
            Variable = "$.terraform_result.LastStatus"
            StringEquals = "STOPPED"
            Next = "CheckExitCode"
          }
        ]
        Default = "UpdateStatusToFailed"
      }
      
      CheckExitCode = {
        Type = "Choice"
        Choices = [
          {
            Variable = "$.terraform_result.Containers[0].ExitCode"
            NumericEquals = 0
            Next = "UpdateStatusToDestroyed"
          }
        ]
        Default = "UpdateStatusToFailed"
      }
      
      UpdateStatusToDestroyed = {
        Type = "Task"
        Resource = "arn:aws:states:::dynamodb:updateItem"
        Parameters = {
          TableName = var.dynamodb_table_name
          Key = {
            id = {
              "S.$" = "$.enclave_id"
            }
          }
          UpdateExpression = "SET #status = :status, #updated_at = :timestamp"
          ExpressionAttributeNames = {
            "#status" = "status"
            "#updated_at" = "updated_at"
          }
          ExpressionAttributeValues = {
            ":status" = {
              S = "DESTROYED"
            }
            ":timestamp" = {
              "S.$" = "$$.State.EnteredTime"
            }
          }
        }
        End = true
      }
      
      UpdateStatusToFailed = {
        Type = "Task"
        Resource = "arn:aws:states:::dynamodb:updateItem"
        Parameters = {
          TableName = var.dynamodb_table_name
          Key = {
            id = {
              "S.$" = "$.enclave_id"
            }
          }
          UpdateExpression = "SET #status = :status, #updated_at = :timestamp, #error = :error"
          ExpressionAttributeNames = {
            "#status" = "status"
            "#updated_at" = "updated_at"
            "#error" = "error_message"
          }
          ExpressionAttributeValues = {
            ":status" = {
              S = "FAILED"
            }
            ":timestamp" = {
              "S.$" = "$$.State.EnteredTime"
            }
            ":error" = {
              "S.$" = "$.validation_result.Payload.message"
            }
          }
        }
        Next = "NotifyError"
      }
      
      NotifyError = {
        Type = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = var.error_handler_lambda_arn
          Payload = {
            "execution_name.$" = "$$.Execution.Name"
            "execution_arn.$" = "$$.Execution.Name"
            "state_machine.$" = "$$.StateMachine.Name"
            "error_message" = "Step Functions execution failed"
          }
        }
        End = true
      }
    }
  })
  
  tags = var.tags
}