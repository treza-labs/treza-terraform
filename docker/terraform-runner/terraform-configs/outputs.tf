output "instance_id" {
  description = "ID of the EC2 instance"
  value       = aws_instance.nitro_enclave.id
}

output "instance_arn" {
  description = "ARN of the EC2 instance"
  value       = aws_instance.nitro_enclave.arn
}

output "public_ip" {
  description = "Public IP address of the instance"
  value       = aws_instance.nitro_enclave.public_ip
}

output "private_ip" {
  description = "Private IP address of the instance"
  value       = aws_instance.nitro_enclave.private_ip
}

output "security_group_id" {
  description = "ID of the security group (shared)"
  value       = "sg-0766bf09d75f2eeff"
}

output "log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.enclave.name
}

output "enclave_configuration" {
  description = "Enclave configuration details"
  value = {
    enclave_id  = var.enclave_id
    cpu_count   = var.cpu_count
    memory_mib  = var.memory_mib
    debug_mode  = var.debug_mode
  }
}

# Application Logging Outputs
output "application_log_group_name" {
  description = "Name of the application log group"
  value       = module.application_logging.application_log_group_name
}

output "stdout_log_group_name" {
  description = "Name of the stdout log group"
  value       = module.application_logging.stdout_log_group_name
}

output "stderr_log_group_name" {
  description = "Name of the stderr log group"
  value       = module.application_logging.stderr_log_group_name
}

output "cloudwatch_agent_instance_profile_name" {
  description = "Name of the CloudWatch agent instance profile"
  value       = module.application_logging.cloudwatch_agent_instance_profile_name
}