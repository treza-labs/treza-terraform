# Treza Terraform Examples

This directory contains practical examples for deploying Treza infrastructure in different scenarios.

## 📁 Available Examples

### 1. [Basic Setup](./basic-setup/)
Simple development environment setup for getting started quickly.

**Use Case**: Local development, proof of concept, learning
**Time to Deploy**: ~15 minutes
**Estimated Cost**: ~$50/month

### 2. [Production Ready](./production-ready/)
Production-grade configuration with high availability and security.

**Use Case**: Production workloads, enterprise deployments
**Time to Deploy**: ~30 minutes
**Estimated Cost**: ~$200-300/month

### 3. [Multi-Environment](./multi-environment/)
Complete setup with dev, staging, and production environments.

**Use Case**: Teams with multiple environments, CI/CD pipelines
**Time to Deploy**: ~45 minutes per environment
**Estimated Cost**: ~$500/month (all environments)

## 🚀 Quick Start

1. **Choose an example** that matches your use case
2. **Copy the configuration** to your project
3. **Customize** the variables for your environment
4. **Deploy** using Terraform

```bash
# Example: Deploy basic setup
cd examples/basic-setup
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
terraform init
terraform plan
terraform apply
```

## 📋 Prerequisites

All examples require:
- AWS CLI configured with appropriate credentials
- Terraform >= 1.6.0
- An existing DynamoDB table from treza-app
- Docker (for building container images)

## 🔧 Customization Guide

### Environment Variables

Each example includes a `terraform.tfvars.example` file. Common variables:

```hcl
aws_region    = "us-west-2"           # Your AWS region
environment   = "dev"                  # Environment name
project_name  = "treza"                # Project identifier
vpc_cidr      = "10.0.0.0/16"         # VPC CIDR block

# Reference to existing DynamoDB table
existing_dynamodb_table_name = "treza-enclaves-dev"
```

### Scaling Configuration

Adjust these based on your workload:

```hcl
# ECS Task Resources
terraform_runner_cpu    = 1024  # 0.25-4 vCPU (1024 = 1 vCPU)
terraform_runner_memory = 2048  # 512-30720 MB

# Timeouts
deployment_timeout_seconds = 1800  # 30 minutes
destroy_timeout_seconds    = 1200  # 20 minutes
```

### Cost Optimization

Tips to reduce costs:

1. **Development**:
   - Use smaller ECS task sizes (512 CPU / 1024 memory)
   - Reduce log retention to 7 days
   - Use single availability zone

2. **Staging**:
   - Use moderate ECS task sizes (1024 CPU / 2048 memory)
   - Log retention 14-30 days
   - Two availability zones

3. **Production**:
   - Size based on actual workload
   - Longer log retention (90+ days)
   - Three availability zones for HA

## 🧪 Testing Examples

Before deploying to production, test examples in dev:

```bash
# Validate configuration
terraform validate

# Check what will be created
terraform plan

# Estimate costs (if Infracost is configured)
infracost breakdown --path .

# Deploy with approval
terraform apply
```

## 📊 Example Comparison

| Feature | Basic Setup | Production Ready | Multi-Environment |
|---------|-------------|------------------|-------------------|
| **Availability Zones** | 2 | 3 | 2 (dev) / 3 (prod) |
| **ECS Resources** | 512/1024 | 2048/4096 | Variable |
| **Log Retention** | 7 days | 90 days | 7/14/90 days |
| **VPC Endpoints** | Basic | Comprehensive | Environment-specific |
| **Monitoring** | Basic | Advanced | Full stack |
| **Cost** | ~$50/mo | ~$200-300/mo | ~$500/mo total |
| **Complexity** | ⭐ Low | ⭐⭐⭐ High | ⭐⭐⭐⭐ Advanced |

## 🔒 Security Notes

All examples follow security best practices:
- Private subnet deployment
- Encrypted state backends
- VPC endpoints for AWS services
- IAM least privilege
- Security group isolation

Refer to [SECURITY.md](../SECURITY.md) for detailed security guidelines.

## 💡 Common Modifications

### Change AWS Region

Update in `terraform.tfvars`:
```hcl
aws_region         = "eu-west-1"
availability_zones = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
```

### Adjust VPC CIDR

Ensure no conflicts with existing networks:
```hcl
vpc_cidr = "10.1.0.0/16"  # Change to your desired CIDR
```

### Add Custom Tags

```hcl
additional_tags = {
  Team        = "infrastructure"
  CostCenter  = "engineering"
  Environment = "production"
  Compliance  = "hipaa"
}
```

## 🐛 Troubleshooting

### Common Issues

1. **Backend Bucket Doesn't Exist**
   ```bash
   ./scripts/create-backend.sh dev
   ```

2. **DynamoDB Table Not Found**
   - Ensure the treza-app DynamoDB table exists
   - Check the table name in `terraform.tfvars`

3. **Insufficient Permissions**
   - Verify AWS credentials: `aws sts get-caller-identity`
   - Check required IAM permissions in README.md

4. **VPC CIDR Conflict**
   - Change `vpc_cidr` to avoid conflicts with existing VPCs

## 📚 Additional Resources

- [Main README](../README.md) - Full documentation
- [Contributing Guide](../CONTRIBUTING.md) - How to contribute
- [Deployment Guide](../DEPLOYMENT_GUIDE.md) - Detailed deployment steps
- [Security Policy](../SECURITY.md) - Security guidelines

## 🤝 Contributing Examples

Have a useful configuration? Share it!

1. Create a new directory under `examples/`
2. Include:
   - `README.md` with description
   - `terraform.tfvars.example`
   - `main.tf` (if needed)
   - Architecture diagram (optional)
3. Submit a pull request

## 📞 Support

- **Questions**: [GitHub Discussions](https://github.com/treza-labs/treza-terraform/discussions)
- **Issues**: [GitHub Issues](https://github.com/treza-labs/treza-terraform/issues)
- **Security**: See [SECURITY.md](../SECURITY.md)

---

**Note**: All cost estimates are approximate and may vary based on region, usage patterns, and AWS pricing changes. Use the AWS Pricing Calculator for accurate estimates.

