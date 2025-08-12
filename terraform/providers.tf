terraform {
  required_version = ">= 1.6"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
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
    # Backend configuration will be provided via backend config file
    # Configuration is loaded from environments/backend-{env}.conf
    encrypt = true
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