# Basic Setup Example

A minimal configuration for getting started with Treza Terraform infrastructure. Perfect for development, testing, and proof-of-concept deployments.

## 🎯 Overview

This example deploys:
- VPC with 2 availability zones
- Basic networking (public/private subnets)
- ECS cluster with minimal resources
- Lambda functions for workflow management
- Step Functions for orchestration
- Basic monitoring and logging

**Estimated Monthly Cost**: ~$50 USD
**Deployment Time**: ~15 minutes

## 📋 Prerequisites

- AWS CLI configured
- Terraform >= 1.6.0
- An existing DynamoDB table from treza-app
- Docker for container builds

## 🚀 Quick Start

### 1. Copy Configuration

```bash
cd examples/basic-setup
cp terraform.tfvars.example terraform.tfvars
```

### 2. Edit Configuration

Edit `terraform.tfvars` with your values:

```hcl
aws_region    = "us-west-2"
environment   = "dev"
project_name  = "treza"

# Your existing DynamoDB table
existing_dynamodb_table_name = "treza-enclaves-dev"

# Network configuration
vpc_cidr           = "10.0.0.0/16"
availability_zones = ["us-west-2a", "us-west-2b"]

# Minimal ECS resources for development
terraform_runner_cpu    = 512
terraform_runner_memory = 1024

# Short timeouts for faster iterations
deployment_timeout_seconds = 1200  # 20 minutes
destroy_timeout_seconds    = 900   # 15 minutes

# Short log retention to reduce costs
log_retention_days = 7
```

### 3. Create Backend

```bash
cd ../../
./scripts/create-backend.sh dev
```

### 4. Deploy

```bash
cd terraform
terraform init -backend-config=environments/backend-dev.conf
terraform plan -var-file=environments/dev.tfvars
terraform apply -var-file=environments/dev.tfvars
```

## 📊 What Gets Deployed

### Networking
- **VPC**: 10.0.0.0/16 with DNS enabled
- **Public Subnets**: 2 subnets for NAT gateways
- **Private Subnets**: 2 subnets for ECS tasks
- **VPC Endpoints**: S3, DynamoDB, ECR, CloudWatch, SSM

### Compute
- **ECS Cluster**: Fargate-based cluster
- **Task Definitions**: Terraform runner (512 CPU / 1024 MB)
- **Shared Security Group**: For enclave access to AWS services

### Serverless
- **Lambda Functions**:
  - Enclave trigger (DynamoDB Stream processor)
  - Validation function
  - Error handler
  - Status monitor
- **Step Functions**: Deployment and cleanup workflows

### Storage & State
- **DynamoDB**: Uses existing table from treza-app
- **S3 Backend**: For Terraform state (created separately)
- **DynamoDB Lock Table**: For state locking

### Monitoring
- **CloudWatch Logs**: 7-day retention
- **CloudWatch Dashboard**: Basic metrics
- **Alarms**: Essential alerts only

## 💰 Cost Breakdown

Approximate monthly costs (us-west-2):

| Resource | Cost |
|----------|------|
| VPC & Networking | ~$5 |
| NAT Gateways (2) | ~$32 |
| ECS Fargate Tasks | ~$5 (based on usage) |
| Lambda Functions | ~$1 (based on usage) |
| CloudWatch Logs | ~$3 |
| DynamoDB | Varies (existing table) |
| **Total** | **~$50/month** |

## 🔧 Customization

### Reduce Costs Further

1. **Single NAT Gateway** (development only):
   ```hcl
   # Manually edit modules/networking/main.tf
   # Use single NAT gateway for all private subnets
   ```

2. **Reduce Log Retention**:
   ```hcl
   log_retention_days = 3
   ```

3. **Smaller Task Sizes** (if workload allows):
   ```hcl
   terraform_runner_cpu    = 256
   terraform_runner_memory = 512
   ```

### Increase Resources

For better performance:

```hcl
terraform_runner_cpu    = 1024
terraform_runner_memory = 2048
deployment_timeout_seconds = 1800
```

## 🧪 Testing

After deployment, test the infrastructure:

```bash
# Check infrastructure health
make health-check ENV=dev

# View logs
./scripts/view-logs.sh dev

# Test enclave deployment (if you have the treza-app running)
# Insert a test record in DynamoDB
```

## 🔒 Security Considerations

This basic setup includes:
- ✅ Private subnet deployment
- ✅ VPC endpoints for AWS services
- ✅ Encrypted state backend
- ✅ IAM least privilege
- ✅ Security group isolation

**Not included** (consider for production):
- Multi-region deployment
- Advanced monitoring and alerting
- Compliance logging
- Enhanced security scanning

## 📈 Next Steps

Once comfortable with the basic setup:

1. **Add Monitoring**: Expand CloudWatch dashboards
2. **Increase Resilience**: Add more availability zones
3. **Optimize Costs**: Review and adjust resource usage
4. **Scale Up**: Move to production-ready example
5. **Multi-Environment**: Set up staging and production

## 🔄 Maintenance

Regular maintenance tasks:

```bash
# Update dependencies
git pull
terraform init -upgrade

# Review and apply changes
terraform plan
terraform apply

# Check for security updates
./scripts/health-check.sh dev
```

## 🗑️ Cleanup

To destroy the infrastructure:

```bash
# Preview what will be destroyed
./scripts/destroy.sh dev --dry-run

# Destroy infrastructure
./scripts/destroy.sh dev
```

**Important**: This will destroy all resources. Make sure to backup any important data.

## 🐛 Troubleshooting

### Common Issues

1. **Error: DynamoDB table not found**
   - Ensure treza-app is deployed first
   - Verify table name in `terraform.tfvars`

2. **Error: Insufficient IAM permissions**
   - Check AWS credentials: `aws sts get-caller-identity`
   - Ensure your IAM user/role has required permissions

3. **Error: VPC CIDR conflict**
   - Change `vpc_cidr` to avoid conflicts

4. **Timeout errors**
   - Increase timeout values in `terraform.tfvars`

## 📞 Support

- [GitHub Issues](https://github.com/treza-labs/treza-terraform/issues)
- [Documentation](../../README.md)
- [Security Policy](../../SECURITY.md)

---

**Ready for production?** Check out the [production-ready example](../production-ready/) for a more robust configuration.

