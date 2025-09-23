variable "name_prefix" {
  description = "Name prefix for all resources"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed for SSH access"
  type        = list(string)
  default     = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
}

variable "management_cidrs" {
  description = "CIDR blocks for management access"
  type        = list(string)
  default     = []
}

variable "security_group_rules" {
  description = "Security group configuration"
  type = object({
    ssh_port         = number
    enclave_port     = number
    monitoring_port  = number
    allowed_protocols = list(string)
  })
  default = {
    ssh_port         = 22
    enclave_port     = 8080
    monitoring_port  = 9090
    allowed_protocols = ["tcp", "udp"]
  }
}

variable "environment" {
  description = "Environment name"
  type        = string
}