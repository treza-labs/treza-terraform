output "instance_id" {
  description = "ID of the EC2 instance"
  value       = aws_instance.enclave_instance.id
}

output "instance_public_ip" {
  description = "Public IP address of the EC2 instance"
  value       = aws_instance.enclave_instance.public_ip
}

output "instance_private_ip" {
  description = "Private IP address of the EC2 instance"
  value       = aws_instance.enclave_instance.private_ip
}

output "log_group_name" {
  description = "CloudWatch log group name"
  value       = aws_cloudwatch_log_group.enclave_logs.name
}

output "enclave_id" {
  description = "Enclave ID"
  value       = var.enclave_id
}

output "architecture" {
  description = "Communication architecture"
  value       = "vsocket-v2"
}