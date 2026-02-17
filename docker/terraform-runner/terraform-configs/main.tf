# Terraform Configuration for Nitro Enclaves with Proper vsocket Architecture
# This implements secure communication between parent and enclave via vsocket
# Date: 2025-08-25

# Variables are declared in variables.tf
# Provider and terraform blocks are in providers.tf

# Data sources
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
  
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Security Group for Nitro Enclave instances
resource "aws_security_group" "enclave_sg" {
  name        = "treza-enclave-sg-${var.enclave_id}"
  description = "Security group for Nitro Enclave instances with vsocket"
  vpc_id      = data.aws_vpc.default.id

  # Allow SSH access from authorized networks only
  ingress {
    from_port   = var.ssh_port
    to_port     = var.ssh_port
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
    description = "SSH from authorized networks"
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "treza-enclave-sg-${var.environment}"
    Environment = var.environment
    Purpose     = "nitro-enclaves-vsocket"
  }
}

# IAM role for EC2 instance
resource "aws_iam_role" "enclave_instance_role" {
  name = "treza-enclave-instance-role-${var.enclave_id}"

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

  tags = {
    Environment = var.environment
    Purpose     = "nitro-enclaves-vsocket"
  }
}

# IAM policy for CloudWatch Logs access
resource "aws_iam_role_policy" "enclave_cloudwatch_policy" {
  name = "treza-enclave-cloudwatch-policy-${var.enclave_id}"
  role = aws_iam_role.enclave_instance_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams",
          "logs:DescribeLogGroups"
        ]
        Resource = [
          "arn:aws:logs:${var.aws_region}:*:log-group:/aws/ec2/enclave/*",
          "arn:aws:logs:${var.aws_region}:*:log-group:/aws/ec2/enclave/*:*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = [
          "${aws_s3_bucket.enclave_scripts.arn}/*"
        ]
      }
    ]
  })
}

# IAM instance profile
resource "aws_iam_instance_profile" "enclave_instance_profile" {
  name = "treza-enclave-instance-profile-${var.enclave_id}"
  role = aws_iam_role.enclave_instance_role.name

  tags = {
    Environment = var.environment
    Purpose     = "nitro-enclaves-vsocket"
  }
}

# CloudWatch Log Group for enclave logs
resource "aws_cloudwatch_log_group" "enclave_logs" {
  name              = "/aws/ec2/enclave/${var.enclave_id}"
  retention_in_days = 7

  tags = {
    Environment = var.environment
    EnclaveId   = var.enclave_id
    Purpose     = "nitro-enclaves-vsocket"
  }
}

# S3 bucket for enclave scripts (avoids user_data 16KB limit)
resource "aws_s3_bucket" "enclave_scripts" {
  bucket_prefix = "treza-enclave-scripts-"
  force_destroy = true
  tags = {
    Environment = var.environment
    EnclaveId   = var.enclave_id
    Purpose     = "enclave-proxy-scripts"
  }
}

resource "aws_s3_object" "parent_proxy" {
  bucket = aws_s3_bucket.enclave_scripts.id
  key    = "parent_proxy.py"
  source = "${path.module}/parent_proxy.py"
  etag   = filemd5("${path.module}/parent_proxy.py")
}

resource "aws_s3_object" "enclave_proxy" {
  bucket = aws_s3_bucket.enclave_scripts.id
  key    = "enclave_proxy.py"
  source = "${path.module}/enclave_proxy.py"
  etag   = filemd5("${path.module}/enclave_proxy.py")
}

resource "aws_s3_object" "enclave_proxy_binary" {
  bucket = aws_s3_bucket.enclave_scripts.id
  key    = "enclave-proxy"
  source = "${path.module}/enclave-proxy"
  etag   = filemd5("${path.module}/enclave-proxy")
}

# User data script with template variables
locals {
  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    enclave_id           = var.enclave_id
    cpu_count            = var.cpu_count
    memory_mib           = var.memory_mib
    docker_image         = var.docker_image
    workload_type        = var.workload_type
    health_check_path    = var.health_check_path
    health_check_interval = var.health_check_interval
    aws_services         = var.aws_services
    expose_ports         = var.expose_ports
    scripts_bucket       = aws_s3_bucket.enclave_scripts.id
  }))
}

# EC2 instance for Nitro Enclave
resource "aws_instance" "enclave_instance" {
  ami                     = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  key_name               = "treza-debug-key"
  vpc_security_group_ids = [aws_security_group.enclave_sg.id]
  subnet_id              = data.aws_subnets.default.ids[0]
  iam_instance_profile   = aws_iam_instance_profile.enclave_instance_profile.name
  
  # Enable Nitro Enclaves
  enclave_options {
    enabled = true
  }
  
  # Ensure public IP
  associate_public_ip_address = true
  
  # User data script
  user_data = local.user_data

  tags = {
    Name        = "treza-enclave-${var.enclave_id}"
    Environment = var.environment
    EnclaveId   = var.enclave_id
    Purpose     = "nitro-enclaves-vsocket"
    Architecture = "vsocket-communication"
  }

  # Ensure instance is replaced if user data changes
  user_data_replace_on_change = true
}

# Update DynamoDB record with instance information
resource "null_resource" "update_enclave_record" {
  depends_on = [aws_instance.enclave_instance]
  
  provisioner "local-exec" {
    command = <<-EOT
      aws dynamodb update-item \
        --table-name "treza-enclaves-${var.environment}" \
        --key '{"id": {"S": "${var.enclave_id}"}}' \
        --update-expression "SET instance_id = :instance_id, #status = :status, updated_at = :timestamp, architecture = :architecture, workload_type = :workload_type" \
        --expression-attribute-names '{"#status": "status"}' \
        --expression-attribute-values '{
          ":instance_id": {"S": "${aws_instance.enclave_instance.id}"},
          ":status": {"S": "DEPLOYING"},
          ":timestamp": {"S": "${timestamp()}"},
          ":architecture": {"S": "vsocket-v2"},
          ":workload_type": {"S": "${var.workload_type}"}
        }' \
        --region ${var.aws_region}
    EOT
  }
}

# Mark deployment as complete
resource "null_resource" "mark_deployment_complete" {
  depends_on = [null_resource.update_enclave_record, aws_instance.enclave_instance]
  
  provisioner "local-exec" {
    command = <<-EOT
      sleep 10
      aws dynamodb update-item \
        --table-name "treza-enclaves-${var.environment}" \
        --key '{"id": {"S": "${var.enclave_id}"}}' \
        --update-expression "SET #status = :status, updated_at = :timestamp" \
        --expression-attribute-names '{"#status": "status"}' \
        --expression-attribute-values '{
          ":status": {"S": "DEPLOYED"},
          ":timestamp": {"S": "${timestamp()}"}
        }' \
        --region ${var.aws_region}
    EOT
  }
}

# Outputs are declared in outputs.tf
