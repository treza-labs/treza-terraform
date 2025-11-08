# Frequently Asked Questions (FAQ)

## General Questions

### What is Treza Terraform Infrastructure?

Treza Terraform Infrastructure is a comprehensive, production-ready Terraform configuration for deploying AWS Nitro Enclaves using an event-driven architecture. It automates the entire lifecycle of enclave deployments using DynamoDB Streams, Step Functions, and ECS Fargate.

### Who should use this project?

This project is ideal for:
- Teams deploying confidential computing workloads on AWS
- Organizations requiring isolated execution environments
- Developers building secure, event-driven infrastructure
- Companies needing automated enclave lifecycle management

### What are the prerequisites?

- AWS account with appropriate permissions
- Terraform >= 1.6.0
- AWS CLI configured
- Docker (for building container images)
- An existing DynamoDB table from treza-app for enclave management

### How much does it cost to run?

Costs vary by deployment size:
- **Development**: ~$50/month (basic-setup example)
- **Staging**: ~$100-150/month
- **Production**: ~$200-300/month (production-ready example)

See the [examples directory](../examples/) for detailed cost breakdowns.

## Deployment Questions

### How long does deployment take?

- **Basic setup**: ~15 minutes
- **Production-ready**: ~30 minutes
- **Multi-environment**: ~45 minutes per environment

Actual times vary based on AWS region and resource availability.

### Can I deploy to multiple regions?

Yes! You can deploy to any AWS region. However, each region requires:
- Separate Terraform state backend
- Region-specific configuration
- ECR repository in each region for container images

### Do I need to deploy all three environments?

No. Start with development only and add staging/production as needed. Each environment is independent.

### Can I use existing VPCs?

The current configuration creates new VPCs. To use existing VPCs, you would need to:
1. Import existing VPC resources
2. Modify the networking module
3. Adjust security group configurations

This is an advanced customization - we recommend using new VPCs for isolation.

## Configuration Questions

### What DynamoDB table does this use?

This infrastructure expects an existing DynamoDB table created by the treza-app. The table should contain enclave deployment requests with the following attributes:
- Primary key for unique enclave identification
- Status field for tracking lifecycle
- Configuration fields for enclave parameters

### How do I change the VPC CIDR?

Edit your `terraform.tfvars`:
```hcl
vpc_cidr = "10.1.0.0/16"  # Change to your desired CIDR
```

Ensure it doesn't conflict with existing networks.

### Can I adjust ECS task resources?

Yes! In `terraform.tfvars`:
```hcl
terraform_runner_cpu    = 1024  # 0.25-4 vCPU (256-4096)
terraform_runner_memory = 2048  # 512-30720 MB
```

Memory must be compatible with CPU allocation (see [AWS ECS documentation](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-cpu-memory-error.html)).

### How do I change log retention?

In `terraform.tfvars`:
```hcl
log_retention_days = 30  # Options: 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
```

Longer retention increases costs but may be required for compliance.

## Operations Questions

### How do I view logs?

Use our enhanced log viewer:
```bash
# Interactive menu
./scripts/view-logs.sh dev

# Specific component
./scripts/view-logs.sh dev ecs-runner

# Follow in real-time
./scripts/view-logs.sh dev lambda-trigger --follow

# Filter by pattern
./scripts/view-logs.sh dev all --filter ERROR
```

### How do I check infrastructure health?

```bash
make health-check ENV=dev
# or
./scripts/health-check.sh dev
```

### How do I update the infrastructure?

```bash
# Pull latest changes
git pull

# Review changes
terraform plan -var-file=environments/dev.tfvars

# Apply updates
terraform apply -var-file=environments/dev.tfvars
```

Always test in development before updating production!

### How do I add a new environment?

1. Create new tfvars file: `terraform/environments/myenv.tfvars`
2. Create backend config: `terraform/environments/backend-myenv.conf`
3. Create backend resources: `./scripts/create-backend.sh myenv`
4. Deploy: `make deploy ENV=myenv`

### How do I rollback a deployment?

Using Terraform state:
```bash
# List state versions
aws s3api list-object-versions \
  --bucket your-state-bucket \
  --prefix env/terraform.tfstate

# Download previous version
aws s3api get-object \
  --bucket your-state-bucket \
  --key env/terraform.tfstate \
  --version-id VERSION_ID \
  previous.tfstate

# Restore (carefully!)
cp previous.tfstate terraform.tfstate
terraform apply
```

## Security Questions

### Is this secure for production?

Yes! The infrastructure implements:
- ✅ AWS Well-Architected Framework best practices
- ✅ Least privilege IAM policies
- ✅ Private subnet deployment
- ✅ VPC endpoints for AWS services
- ✅ Encrypted state backend
- ✅ Security scanning (tfsec, Checkov)

See [SECURITY.md](../SECURITY.md) for detailed security practices.

### How do I report security vulnerabilities?

**Do not open public issues.** Instead:
1. Use [GitHub Security Advisories](https://github.com/treza-labs/treza-terraform/security/advisories)
2. Or email: security@treza-labs.com

See our [Security Policy](../SECURITY.md) for details.

### Are secrets stored in Terraform state?

Some sensitive values may appear in state files. That's why:
- State is stored in encrypted S3 buckets
- Access is restricted via IAM policies
- State files are never committed to git
- Use AWS Secrets Manager for application secrets

### How do I rotate credentials?

Infrastructure credentials (IAM roles):
- Automatically rotated by AWS
- No manual rotation needed

Application secrets:
- Use AWS Secrets Manager with automatic rotation
- See AWS documentation for specific services

## Troubleshooting Questions

### My deployment is failing, what should I check?

Common issues checklist:
1. ✅ AWS credentials configured: `aws sts get-caller-identity`
2. ✅ Backend exists: `aws s3 ls s3://your-state-bucket`
3. ✅ DynamoDB table exists: `aws dynamodb describe-table --table-name TABLE`
4. ✅ No CIDR conflicts: Check existing VPCs
5. ✅ Sufficient IAM permissions
6. ✅ Terraform version: `terraform version` (>= 1.6.0)

See [Troubleshooting Guide](./TROUBLESHOOTING.md) for detailed solutions.

### Why are my Lambda functions timing out?

Possible causes:
1. **Network issues**: Check VPC configuration and endpoints
2. **Cold starts**: First invocation takes longer
3. **Memory limits**: Increase Lambda memory allocation
4. **External dependencies**: Check API/service availability

Increase timeout in Lambda configuration if needed.

### Why can't I see enclave logs?

Enclaves need access to CloudWatch Logs via:
1. **Security group**: Must use shared security group
2. **VPC endpoint**: CloudWatch Logs endpoint must exist
3. **IAM role**: Enclave needs CloudWatch Logs permissions
4. **Network**: Private subnet with route to endpoint

Verify all components are correctly configured.

### ECS tasks are failing to start, why?

Common causes:
1. **Docker image**: Can't pull from ECR (check permissions)
2. **Resources**: Insufficient CPU/memory in region
3. **Networking**: Can't reach ECR endpoint
4. **Task role**: Insufficient IAM permissions

Check ECS task stopped reason in AWS Console for specifics.

## Cost Questions

### Why is my bill higher than expected?

Common cost drivers:
1. **NAT Gateways**: $0.045/hour per gateway + data transfer
2. **VPC Endpoints**: $0.01/hour per endpoint
3. **ECS Tasks**: Running longer than expected
4. **CloudWatch Logs**: High log volume or long retention
5. **Data Transfer**: Cross-AZ or inter-region transfers

Use AWS Cost Explorer to identify specific resources.

### How can I reduce costs?

**Development**:
- Use single NAT Gateway
- Reduce log retention (3-7 days)
- Smaller ECS tasks (512 CPU / 1024 MB)
- Single availability zone

**All Environments**:
- Delete unused resources: `terraform destroy`
- Use S3 lifecycle policies
- Review and optimize CloudWatch retention
- Monitor with AWS Cost Anomaly Detection

### Are there any free tier benefits?

Some services included in AWS Free Tier:
- Lambda: 1M requests/month
- CloudWatch: 5GB logs, 10 custom metrics
- DynamoDB: 25GB storage
- S3: 5GB storage

Free tier is per account, not per deployment.

### What about data transfer costs?

Data transfer within the same AZ is free. Costs apply for:
- Cross-AZ: $0.01/GB
- Internet egress: $0.09/GB (first 10TB)
- Cross-region: $0.02/GB

Use VPC endpoints to avoid internet egress charges.

## CI/CD Questions

### How do I integrate with my CI/CD pipeline?

The project includes GitHub Actions workflows. For other CI/CD:

```bash
# Validation
terraform fmt -check -recursive
terraform validate
tfsec .

# Plan
terraform plan -out=plan.tfplan

# Apply
terraform apply plan.tfplan
```

Set these environment variables:
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_DEFAULT_REGION`

### Do I need to run Terraform locally?

No. You can use:
- **Terraform Cloud**: Remote state and execution
- **GitHub Actions**: Included workflows
- **GitLab CI/CD**: Adapt GitHub Actions workflows
- **Jenkins**: Traditional pipeline setup

### How do I prevent manual changes?

1. **Prevent console changes**: Use IAM policies
2. **Detect drift**: Run `terraform plan` regularly
3. **Enable CloudTrail**: Audit all changes
4. **Use AWS Config**: Compliance monitoring

## Support Questions

### Where can I get help?

- **Documentation**: Start with [README.md](../README.md)
- **Examples**: Check [examples/](../examples/)
- **Issues**: [GitHub Issues](https://github.com/treza-labs/treza-terraform/issues)
- **Discussions**: [GitHub Discussions](https://github.com/treza-labs/treza-terraform/discussions)
- **Security**: See [SECURITY.md](../SECURITY.md)

### How do I contribute?

We welcome contributions! See [CONTRIBUTING.md](../CONTRIBUTING.md) for:
- Development setup
- Coding standards
- Pull request process
- Commit message guidelines

### Is there a Slack/Discord community?

We primarily use GitHub Discussions. For real-time chat, check if there's a pinned discussion with community links.

### Can I hire someone to help with deployment?

While we don't provide official consulting, you can:
1. Post in GitHub Discussions
2. Hire AWS consultants familiar with Terraform
3. Contact AWS Professional Services
4. Engage HashiCorp partners

## Version Questions

### What version should I use?

Use the latest stable release (check [Releases](https://github.com/treza-labs/treza-terraform/releases)):
- Production: Use tagged releases only
- Development: Can use `main` branch

### How do I upgrade to a new version?

```bash
# Check current version
./scripts/version.sh current

# Pull latest
git fetch --tags
git checkout v2.1.0  # or desired version

# Review changes
cat CHANGELOG.md

# Test in dev first
cd terraform
terraform init -upgrade
terraform plan
terraform apply
```

### Is there a migration guide?

Major version changes include migration guides. Check:
1. CHANGELOG.md for breaking changes
2. Release notes on GitHub
3. Migration guides in docs/

### How do I stay updated?

- **Watch** the GitHub repository
- **Subscribe** to releases
- **Enable** Dependabot alerts
- **Review** CHANGELOG.md regularly

---

**Still have questions?** Open a [GitHub Discussion](https://github.com/treza-labs/treza-terraform/discussions)!

