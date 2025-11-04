# TFLint Configuration
# https://github.com/terraform-linters/tflint

config {
  # Enable module inspection
  module = true
  
  # Force returning an error if there are issues
  force = false
  
  # Disable terraform version check
  disabled_by_default = false
}

# Enable AWS plugin
plugin "aws" {
  enabled = true
  version = "0.29.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

# Terraform Core Rules
# https://github.com/terraform-linters/tflint/tree/master/docs/rules

rule "terraform_deprecated_index" {
  enabled = true
}

rule "terraform_deprecated_interpolation" {
  enabled = true
}

rule "terraform_documented_outputs" {
  enabled = true
}

rule "terraform_documented_variables" {
  enabled = true
}

rule "terraform_module_pinned_source" {
  enabled = true
  style   = "semver"
}

rule "terraform_naming_convention" {
  enabled = true
  
  # Variable naming
  variable {
    format = "snake_case"
  }
  
  # Local value naming
  locals {
    format = "snake_case"
  }
  
  # Output naming
  output {
    format = "snake_case"
  }
  
  # Resource naming
  resource {
    format = "snake_case"
  }
  
  # Data source naming
  data {
    format = "snake_case"
  }
}

rule "terraform_required_providers" {
  enabled = true
}

rule "terraform_required_version" {
  enabled = true
}

rule "terraform_typed_variables" {
  enabled = true
}

rule "terraform_unused_declarations" {
  enabled = true
}

rule "terraform_unused_required_providers" {
  enabled = true
}

rule "terraform_standard_module_structure" {
  enabled = true
}

rule "terraform_workspace_remote" {
  enabled = true
}

# AWS Specific Rules
# https://github.com/terraform-linters/tflint-ruleset-aws/tree/master/docs/rules

rule "aws_resource_missing_tags" {
  enabled = true
  tags = [
    "Environment",
    "Project",
    "ManagedBy"
  ]
}

rule "aws_iam_policy_document_gov_friendly_arns" {
  enabled = false
}

rule "aws_iam_role_policy_too_long_policy" {
  enabled = true
}

rule "aws_iam_policy_too_long_policy" {
  enabled = true
}

rule "aws_s3_bucket_name" {
  enabled = true
  regex   = "^[a-z0-9][a-z0-9-]*[a-z0-9]$"
}

rule "aws_db_instance_invalid_type" {
  enabled = true
}

rule "aws_elasticache_cluster_invalid_type" {
  enabled = true
}

rule "aws_instance_invalid_type" {
  enabled = true
}

rule "aws_launch_configuration_invalid_image_id" {
  enabled = true
}

rule "aws_mq_broker_invalid_engine_type" {
  enabled = true
}

rule "aws_eks_cluster_invalid_version" {
  enabled = true
}

# Security Rules

rule "aws_security_group_rule_invalid_ingress" {
  enabled = true
}

rule "aws_security_group_rule_invalid_egress" {
  enabled = true
}

# Disable some overly strict rules
rule "aws_route_specified_multiple_targets" {
  enabled = false
}

rule "aws_route_not_specified_target" {
  enabled = false
}

