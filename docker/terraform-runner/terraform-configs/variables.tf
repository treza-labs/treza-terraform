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
  default     = "m5n.large"
  
  validation {
    condition = contains([
      "m5n.large", "m5n.xlarge", "m5n.2xlarge", "m5n.4xlarge",
      "c5n.large", "c5n.xlarge", "c5n.2xlarge", "c5n.4xlarge",
      "r5n.large", "r5n.xlarge", "r5n.2xlarge", "r5n.4xlarge"
    ], var.instance_type)
    error_message = "Instance type must support Nitro Enclaves."
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
  default     = 512
  
  validation {
    condition     = var.memory_mib >= 512 && var.memory_mib <= 32768
    error_message = "Memory must be between 512 MiB and 32768 MiB."
  }
}

variable "eif_path" {
  description = "Path to the Enclave Image File (EIF)"
  type        = string
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