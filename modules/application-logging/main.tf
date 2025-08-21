# Application Logging Module for Nitro Enclaves
# Creates CloudWatch log groups for application logs from inside enclaves

# CloudWatch Log Group for Application Logs
resource "aws_cloudwatch_log_group" "application" {
  name              = "/aws/nitro-enclave/${var.enclave_id}/application"
  retention_in_days = var.log_retention_days
  
  tags = merge(var.tags, {
    Type = "ApplicationLogs"
    EnclaveId = var.enclave_id
    WalletAddress = var.wallet_address
  })
}

# CloudWatch Log Group for Container stdout/enc_1755213508944_hlhgl1vbestderr
resource "aws_cloudwatch_log_group" "container_stdout" {
  name              = "/aws/nitro-enclave/${var.enclave_id}/stdout"
  retention_in_days = var.log_retention_days
  
  tags = merge(var.tags, {
    Type = "ContainerStdout"
    EnclaveId = var.enclave_id
    WalletAddress = var.wallet_address
  })
}

# CloudWatch Log Group for Container stderr
resource "aws_cloudwatch_log_group" "container_stderr" {
  name              = "/aws/nitro-enclave/${var.enclave_id}/stderr"
  retention_in_days = var.log_retention_days
  
  tags = merge(var.tags, {
    Type = "ContainerStderr"
    EnclaveId = var.enclave_id
    WalletAddress = var.wallet_address
  })
}

# IAM Role for CloudWatch Agent in Enclave
resource "aws_iam_role" "cloudwatch_agent" {
  name = "treza-cw-role-${substr(replace(var.enclave_id, "_", "-"), 0, 16)}"
  
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
  
  tags = var.tags
}

# IAM Policy for CloudWatch Agent
resource "aws_iam_policy" "cloudwatch_agent" {
  name        = "treza-cw-policy-${substr(replace(var.enclave_id, "_", "-"), 0, 16)}"
  description = "CloudWatch agent policy for enclave ${var.enclave_id}"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = [
          aws_cloudwatch_log_group.application.arn,
          aws_cloudwatch_log_group.container_stdout.arn,
          aws_cloudwatch_log_group.container_stderr.arn,
          "${aws_cloudwatch_log_group.application.arn}:*",
          "${aws_cloudwatch_log_group.container_stdout.arn}:*",
          "${aws_cloudwatch_log_group.container_stderr.arn}:*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:PutParameter",
          "ssm:GetParameter",
          "ssm:DeleteParameter"
        ]
        Resource = [
          "arn:aws:ssm:*:*:parameter/treza/${var.enclave_id}/*"
        ]
      }
    ]
  })
  
  tags = var.tags
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.cloudwatch_agent.name
  policy_arn = aws_iam_policy.cloudwatch_agent.arn
}

# Instance Profile for EC2
resource "aws_iam_instance_profile" "cloudwatch_agent" {
  name = "treza-cw-profile-${substr(replace(var.enclave_id, "_", "-"), 0, 16)}"
  role = aws_iam_role.cloudwatch_agent.name
  
  tags = var.tags
}

