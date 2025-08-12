# Local values for common resource naming
locals {
  name_prefix = "${var.project_name}-${var.environment}"
  
  common_tags = merge(var.additional_tags, {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  })
}

# DynamoDB table will be created by the dynamodb_streams module

# Core Infrastructure Modules
module "networking" {
  source = "../modules/networking"
  
  name_prefix        = local.name_prefix
  vpc_cidr          = var.vpc_cidr
  availability_zones = var.availability_zones
  tags              = local.common_tags
}

module "iam" {
  source = "../modules/iam"
  
  name_prefix           = local.name_prefix
  dynamodb_table_arn    = module.dynamodb_streams.table_arn
  s3_state_bucket_name  = module.state_backend.bucket_name
  tags                  = local.common_tags
}

module "state_backend" {
  source = "../modules/state-backend"
  
  name_prefix = local.name_prefix
  tags        = local.common_tags
}

module "dynamodb_streams" {
  source = "../modules/dynamodb"
  
  table_name        = var.existing_dynamodb_table_name
  lambda_trigger_arn = module.lambda_functions.enclave_trigger_arn
  tags              = local.common_tags
}

module "lambda_functions" {
  source = "../modules/lambda"
  
  name_prefix                = local.name_prefix
  step_function_arn         = module.step_functions.deployment_state_machine_arn
  dynamodb_table_name       = var.existing_dynamodb_table_name
  lambda_execution_role_arn = module.iam.lambda_execution_role_arn
  tags                      = local.common_tags
}

module "step_functions" {
  source = "../modules/step-functions"
  
  name_prefix                = local.name_prefix
  ecs_cluster_arn           = module.ecs.cluster_arn
  ecs_task_definition_arn   = module.ecs.terraform_runner_task_definition_arn
  subnet_ids                = module.networking.private_subnet_ids
  security_group_id         = module.networking.terraform_runner_security_group_id
  step_functions_role_arn   = module.iam.step_functions_execution_role_arn
  dynamodb_table_name       = var.existing_dynamodb_table_name
  validation_lambda_arn     = module.lambda_functions.validation_function_arn
  error_handler_lambda_arn  = module.lambda_functions.error_handler_function_arn
  deployment_timeout        = var.deployment_timeout_seconds
  destroy_timeout           = var.destroy_timeout_seconds
  tags                      = local.common_tags
}

module "ecs" {
  source = "../modules/ecs"
  
  name_prefix                = local.name_prefix
  cluster_name              = var.ecs_cluster_name
  subnet_ids                = module.networking.private_subnet_ids
  security_group_id         = module.networking.terraform_runner_security_group_id
  task_execution_role_arn   = module.iam.ecs_task_execution_role_arn
  task_role_arn            = module.iam.ecs_task_role_arn
  terraform_runner_cpu      = var.terraform_runner_cpu
  terraform_runner_memory   = var.terraform_runner_memory
  s3_state_bucket_name     = module.state_backend.bucket_name
  tags                     = local.common_tags
}

module "monitoring" {
  source = "../modules/monitoring"
  
  name_prefix           = local.name_prefix
  step_function_arn     = module.step_functions.deployment_state_machine_arn
  ecs_cluster_name      = module.ecs.cluster_name
  log_retention_days    = var.log_retention_days
  tags                  = local.common_tags
}