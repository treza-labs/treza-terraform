terraform {
  required_version = ">= 1.6"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.19"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
  
  backend "s3" {
    # Configuration loaded from environments/backend-{env}.conf during init
    # Use: terraform init -backend-config=environments/backend-dev.conf
  }
}

provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Project     = "treza"
      Environment = var.environment
      ManagedBy   = "terraform"
      Repository  = "treza-terraform"
    }
  }
}