# Terraform configuration for Nitro Enclave deployment
terraform {
  required_version = ">= 1.6"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Project     = "treza"
      Environment = var.environment
      ManagedBy   = "terraform"
      EnclaveId   = var.enclave_id
    }
  }
}

# Data sources
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# Local values
locals {
  name_prefix = "treza-${var.environment}-${var.enclave_id}"
  
  common_tags = {
    Project     = "treza"
    Environment = var.environment
    EnclaveId   = var.enclave_id
    ManagedBy   = "terraform"
  }
}

# EC2 Instance for Nitro Enclave
resource "aws_instance" "nitro_enclave" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  key_name              = var.key_pair_name != "" ? var.key_pair_name : null
  vpc_security_group_ids = [aws_security_group.enclave.id]
  subnet_id             = var.subnet_id
  iam_instance_profile   = module.application_logging.cloudwatch_agent_instance_profile_name
  
  # Enable Nitro Enclaves
  enclave_options {
    enabled = true
  }
  
  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    enclave_id  = var.enclave_id
    cpu_count   = var.cpu_count
    memory_mib  = var.memory_mib
    eif_path    = var.eif_path
    debug_mode  = var.debug_mode
  }))
  
  tags = merge(local.common_tags, {
    Name = local.name_prefix
  })
}

# Security Group for Enclave Instance
resource "aws_security_group" "enclave" {
  name_prefix = "${local.name_prefix}-"
  description = "Security group for Nitro Enclave instance"
  vpc_id      = var.vpc_id
  
  # SSH access (customize as needed)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
    description = "SSH access"
  }
  
  # Enclave communication port (customize based on your application)
  ingress {
    from_port   = var.enclave_port
    to_port     = var.enclave_port
    protocol    = "tcp"
    cidr_blocks = var.allowed_enclave_cidrs
    description = "Enclave communication"
  }
  
  # Outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-sg"
  })
}

# IAM Role for EC2 Instance
resource "aws_iam_role" "enclave_instance" {
  name = "${local.name_prefix}-instance-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
  
  tags = local.common_tags
}

# IAM Instance Profile
resource "aws_iam_instance_profile" "enclave_instance" {
  name = "${local.name_prefix}-instance-profile"
  role = aws_iam_role.enclave_instance.name
  
  tags = local.common_tags
}

# IAM Policy for Enclave Instance
resource "aws_iam_role_policy" "enclave_instance" {
  name = "${local.name_prefix}-instance-policy"
  role = aws_iam_role.enclave_instance.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:PutParameter"
        ]
        Resource = [
          "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/treza/${var.enclave_id}/*"
        ]
      }
    ]
  })
}

# CloudWatch Log Group for Enclave Infrastructure
resource "aws_cloudwatch_log_group" "enclave" {
  name              = "/aws/ec2/treza/${var.enclave_id}"
  retention_in_days = var.log_retention_days
  
  tags = local.common_tags
}

# Application Logging Module
module "application_logging" {
  source = "../../../modules/application-logging"
  
  enclave_id         = var.enclave_id
  wallet_address     = var.wallet_address
  name_prefix        = local.name_prefix
  log_retention_days = var.log_retention_days
  tags              = local.common_tags
}

# Data source for Amazon Linux AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
  
  filter {
    name   = "state"
    values = ["available"]
  }
}