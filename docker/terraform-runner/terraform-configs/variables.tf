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
  default     = "m6i.xlarge"
  
  validation {
    condition = contains([
      "m6i.xlarge", "m6i.2xlarge", "m6i.4xlarge", "m6i.8xlarge", "m6i.12xlarge", "m6i.16xlarge", "m6i.24xlarge",
      "c6i.xlarge", "c6i.2xlarge", "c6i.4xlarge", "c6i.9xlarge", "c6i.12xlarge", "c6i.18xlarge", "c6i.24xlarge"
    ], var.instance_type)
    error_message = "Instance type must support Nitro Enclaves. Supported types: m6i.xlarge and larger, c6i.xlarge and larger."
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
  validation {
    condition = length(var.allowed_ssh_cidrs) > 0 && !contains(var.allowed_ssh_cidrs, "0.0.0.0/0")
    error_message = "SSH access from 0.0.0.0/0 is not allowed for security reasons. Specify specific CIDR blocks."
  }
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

variable "ssh_port" {
  description = "SSH port for instance access"
  type        = number
  default     = 22
  validation {
    condition = var.ssh_port > 0 && var.ssh_port <= 65535
    error_message = "SSH port must be between 1 and 65535."
  }
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

variable "shared_security_group_id" {
  description = "ID of the shared security group for all enclave instances"
  type        = string
  default     = ""
}

# ── Workload manifest variables ─────────────────────────────────────────────

variable "workload_type" {
  description = "Type of workload to run in the enclave: batch (run-to-completion), service (long-running HTTP server), or daemon (background process)"
  type        = string
  default     = "batch"

  validation {
    condition     = contains(["batch", "service", "daemon"], var.workload_type)
    error_message = "Workload type must be one of: batch, service, daemon."
  }
}

variable "health_check_path" {
  description = "HTTP path for health checks on service workloads (e.g. /health)"
  type        = string
  default     = "/health"
}

variable "health_check_interval" {
  description = "Interval in seconds between health checks for service/daemon workloads"
  type        = number
  default     = 30

  validation {
    condition     = var.health_check_interval >= 5 && var.health_check_interval <= 300
    error_message = "Health check interval must be between 5 and 300 seconds."
  }
}

variable "aws_services" {
  description = "Comma-separated list of AWS services the enclave workload needs access to via the vsock proxy (e.g. kms,s3,secretsmanager)"
  type        = string
  default     = ""
}

variable "expose_ports" {
  description = "Comma-separated list of ports the user's application listens on inside the enclave (for vsock port-forwarding)"
  type        = string
  default     = ""
}