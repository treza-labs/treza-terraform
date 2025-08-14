variable "enclave_id" {
  description = "Unique identifier for the enclave"
  type        = string
}

variable "wallet_address" {
  description = "Wallet address of the enclave owner"
  type        = string
}

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "log_retention_days" {
  description = "Number of days to retain logs"
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
