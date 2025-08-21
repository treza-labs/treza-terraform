variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "enclave_id" {
  description = "Unique identifier for the enclave"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for the enclave"
  type        = string
  default     = "m5.xlarge"
  
  validation {
    condition = contains([
      "m5.xlarge", "m5.2xlarge", "m5.4xlarge", "m5.8xlarge", "m5.12xlarge", "m5.16xlarge", "m5.24xlarge",
      "c5.xlarge", "c5.2xlarge", "c5.4xlarge", "c5.9xlarge", "c5.12xlarge", "c5.18xlarge", "c5.24xlarge"
    ], var.instance_type)
    error_message = "Instance type must support Nitro Enclaves. Supported types: m5.xlarge and larger, c5.xlarge and larger."
  }
}

variable "cpu_count" {
  description = "Number of CPUs to allocate to the enclave"
  type        = number
  default     = 2
  
  validation {
    condition     = var.cpu_count >= 2 && var.cpu_count <= 16
    error_message = "CPU count must be between 2 and 16."
  }
}

variable "memory_mib" {
  description = "Amount of memory (MiB) to allocate to the enclave"
  type        = number
  default     = 1024
  
  validation {
    condition     = var.memory_mib >= 1024 && var.memory_mib <= 32768
    error_message = "Memory must be between 1024 MiB and 32768 MiB."
  }
}

variable "eif_path" {
  description = "Path to the Enclave Image File (EIF)"
  type        = string
}

variable "docker_image" {
  description = "Docker image to run in the enclave"
  type        = string
  default     = "nginx:alpine"
}

variable "debug_mode" {
  description = "Enable debug mode for the enclave"
  type        = bool
  default     = false
}

variable "vpc_id" {
  description = "VPC ID where the enclave will be deployed"
  type        = string
  default     = ""
}

variable "subnet_id" {
  description = "Subnet ID where the enclave will be deployed"
  type        = string
  default     = ""
}

variable "key_pair_name" {
  description = "Name of the EC2 Key Pair for SSH access"
  type        = string
  default     = ""
}

variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed for SSH access"
  type        = list(string)
  default     = ["10.0.0.0/8"]
}

variable "allowed_enclave_cidrs" {
  description = "CIDR blocks allowed for enclave communication"
  type        = list(string)
  default     = ["10.0.0.0/8"]
}

variable "enclave_port" {
  description = "Port for enclave communication"
  type        = number
  default     = 8080
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}

variable "wallet_address" {
  description = "Wallet address of the enclave owner"
  type        = string
  default     = "test-wallet-address"
}
}