# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = var.cluster_name
  
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
  
  tags = var.tags
}

# ECS Cluster Capacity Providers
resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = aws_ecs_cluster.main.name
  
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]
  
  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE"
  }
}

# CloudWatch Log Group for ECS Tasks
resource "aws_cloudwatch_log_group" "terraform_runner" {
  name              = "/ecs/${var.name_prefix}-terraform-runner"
  retention_in_days = var.log_retention_days
  
  tags = var.tags
}

# ECS Task Definition for Terraform Runner
resource "aws_ecs_task_definition" "terraform_runner" {
  family                   = "${var.name_prefix}-terraform-runner"
  requires_compatibilities = ["FARGATE"]
  network_mode            = "awsvpc"
  cpu                     = var.terraform_runner_cpu
  memory                  = var.terraform_runner_memory
  execution_role_arn      = var.task_execution_role_arn
  task_role_arn          = var.task_role_arn
  
  container_definitions = jsonencode([
    {
      name  = "terraform-runner"
      image = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com/${var.name_prefix}-terraform-runner:latest"
      
      essential = true
      
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.terraform_runner.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "ecs"
        }
      }
      
      environment = [
        {
          name  = "AWS_DEFAULT_REGION"
          value = data.aws_region.current.name
        },
        {
          name  = "TF_STATE_BUCKET"
          value = var.s3_state_bucket_name
        },
        {
          name  = "TF_STATE_DYNAMODB_TABLE"
          value = "${var.name_prefix}-terraform-locks"
        },
        {
          name  = "FORCE_UPDATE"
          value = "2025-08-14-16-22"
        }
      ]
      
      mountPoints = []
      volumesFrom = []
    }
  ])
  
  tags = var.tags
}

# ECR Repository for Terraform Runner
resource "aws_ecr_repository" "terraform_runner" {
  name                 = "${var.name_prefix}-terraform-runner"
  image_tag_mutability = "MUTABLE"
  
  image_scanning_configuration {
    scan_on_push = true
  }
  
  tags = var.tags
}

# ECR Repository Lifecycle Policy
resource "aws_ecr_lifecycle_policy" "terraform_runner" {
  repository = aws_ecr_repository.terraform_runner.name
  
  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Delete untagged images older than 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}