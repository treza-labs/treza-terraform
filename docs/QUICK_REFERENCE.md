# Quick Reference Guide

Quick commands and references for common tasks.

## 📋 Quick Commands

### Essential Commands

```bash
# Show help
make help

# Check current status
make status ENV=dev

# View version information
make version-info

# Health check
make health-check ENV=dev

# View logs
make logs ENV=dev
```

### Deployment

```bash
# Initialize environment
make init ENV=dev

# Validate everything
make validate-all ENV=dev

# Generate plan
make plan ENV=dev

# Apply changes
make apply ENV=dev

# Quick deploy (validate + plan)
make quick-deploy ENV=dev
```

### State Management

```bash
# List resources
make state-list

# Show resource details
make state-show RESOURCE=aws_vpc.main

# Refresh state
make refresh ENV=dev

# Backup state
make backup-state
```

### Advanced Operations

```bash
# Detect drift
make drift-detect ENV=dev

# Import resource
make import-resource RESOURCE=aws_vpc.main ID=vpc-123456

# Generate dependency graph
make graph

# Estimate costs
make cost-estimate

# Open Terraform console
make console
```

## 🔧 Environment Variables

```bash
# Set environment
export ENV=dev              # or staging, prod

# Enable Terraform debug
export TF_LOG=DEBUG
export TF_LOG_PATH=./terraform-debug.log

# Enable AWS CLI debug
export AWS_CLI_DEBUG=1

# Set AWS region
export AWS_DEFAULT_REGION=us-west-2
```

## 📁 Important File Locations

```
Project Structure:
├── terraform/                      # Main Terraform code
│   ├── environments/              # Environment configs
│   │   ├── dev.tfvars            # Dev variables
│   │   ├── staging.tfvars        # Staging variables
│   │   └── prod.tfvars           # Prod variables
│   └── modules/                   # Reusable modules
├── scripts/                       # Helper scripts
│   ├── deploy.sh                 # Deployment script
│   ├── destroy.sh                # Destroy script
│   ├── version.sh                # Version management
│   └── view-logs.sh              # Log viewer
├── examples/                      # Deployment examples
└── docs/                          # Documentation
```

## 🚀 Common Workflows

### Initial Setup

```bash
# 1. Clone repository
git clone https://github.com/treza-labs/treza-terraform.git
cd treza-terraform

# 2. Copy configuration
cp examples/basic-setup/terraform.tfvars.example terraform/terraform.tfvars

# 3. Create backend
./scripts/create-backend.sh dev

# 4. Deploy
make deploy ENV=dev
```

### Making Changes

```bash
# 1. Create branch
git checkout -b feature/my-feature

# 2. Make changes
# Edit terraform files...

# 3. Validate
make validate-all ENV=dev

# 4. Plan
make plan ENV=dev

# 5. Apply
make apply ENV=dev

# 6. Commit
git add .
git commit -m "feat: add my feature"
git push
```

### Updating Infrastructure

```bash
# 1. Pull latest
git pull

# 2. Check for drift
make drift-detect ENV=dev

# 3. Plan changes
make plan ENV=dev

# 4. Apply updates
make apply ENV=dev

# 5. Verify
make health-check ENV=dev
```

### Troubleshooting

```bash
# View logs
make logs ENV=dev

# Check specific component
./scripts/view-logs.sh dev ecs-runner --follow

# Filter for errors
./scripts/view-logs.sh dev all --filter ERROR

# Run health check
make health-check ENV=dev

# Check state
make state-list
```

## 📊 Cost Estimates

| Environment | Monthly Cost |
|-------------|--------------|
| Development | ~$50         |
| Staging     | ~$100        |
| Production  | ~$250        |

```bash
# Estimate costs
make cost-estimate
```

## 🔒 Security Checklist

- [ ] AWS credentials configured
- [ ] Backend bucket encrypted
- [ ] State locking enabled
- [ ] IAM roles follow least privilege
- [ ] VPC Flow Logs enabled (optional)
- [ ] CloudTrail enabled
- [ ] Security groups restrictive
- [ ] Secrets in Secrets Manager
- [ ] MFA enabled for AWS account

## ⚡ Performance Tips

### Speed Up Deployments

```bash
# Use larger ECS task
terraform_runner_cpu    = 2048
terraform_runner_memory = 4096

# Increase timeouts
deployment_timeout_seconds = 3600
```

### Reduce Costs

```bash
# Use smaller resources
terraform_runner_cpu    = 512
terraform_runner_memory = 1024

# Shorter log retention
log_retention_days = 7

# Single NAT Gateway (dev only)
# Edit modules/networking/main.tf
```

## 🆘 Emergency Procedures

### Infrastructure Down

```bash
# 1. Check health
make health-check ENV=prod

# 2. View logs
./scripts/view-logs.sh prod all --filter ERROR --since 1h

# 3. Check AWS Console
# - CloudWatch dashboards
# - ECS task status
# - Lambda errors
# - Step Function executions

# 4. If needed, redeploy
make apply ENV=prod
```

### State File Corruption

```bash
# 1. Backup current state
make backup-state

# 2. List state versions
aws s3api list-object-versions \
  --bucket YOUR_BUCKET \
  --prefix env/terraform.tfstate

# 3. Download previous version
aws s3api get-object \
  --bucket YOUR_BUCKET \
  --key env/terraform.tfstate \
  --version-id VERSION_ID \
  terraform.tfstate.restored

# 4. Restore and apply
cp terraform.tfstate.restored terraform/terraform.tfstate
make apply ENV=prod
```

### Rollback Deployment

```bash
# 1. Revert to previous git commit
git log --oneline -5
git checkout COMMIT_HASH

# 2. Apply previous configuration
make plan ENV=prod
make apply ENV=prod

# 3. Or restore from state backup
make backup-state
```

## 📞 Getting Help

### Documentation

```bash
# Main README
cat README.md

# FAQ
cat docs/FAQ.md

# Troubleshooting
cat docs/TROUBLESHOOTING.md

# Architecture
cat docs/ARCHITECTURE.md
```

### Community

- **Issues**: https://github.com/treza-labs/treza-terraform/issues
- **Discussions**: https://github.com/treza-labs/treza-terraform/discussions
- **Security**: See SECURITY.md

### Useful Links

- AWS Console: https://console.aws.amazon.com/
- Terraform Docs: https://www.terraform.io/docs
- AWS Nitro Enclaves: https://aws.amazon.com/ec2/nitro/nitro-enclaves/

## 🔑 Keyboard Shortcuts (Makefile)

```bash
make <TAB><TAB>              # Show all available commands
make help                    # Show categorized help
make status ENV=dev          # Quick status
make logs ENV=dev            # Interactive logs
make version-info            # Show versions
```

## 🧪 Testing

```bash
# Validate configuration
make validate ENV=dev

# Format code
make fmt

# Run linting
make lint

# Security scan
make security-scan

# Run tests
make test

# All validations
make validate-all ENV=dev
```

## 📦 Version Management

```bash
# Check current version
./scripts/version.sh current

# Bump version
./scripts/version.sh bump patch    # 2.0.0 -> 2.0.1
./scripts/version.sh bump minor    # 2.0.0 -> 2.1.0
./scripts/version.sh bump major    # 2.0.0 -> 3.0.0

# Create tag
./scripts/version.sh tag

# Set specific version
./scripts/version.sh set 2.1.0
```

## 🎯 Pro Tips

1. **Always test in dev first** before deploying to production
2. **Use `make quick-deploy`** to validate + plan without applying
3. **Enable debug logging** when troubleshooting: `export TF_LOG=DEBUG`
4. **Backup state** before major changes: `make backup-state`
5. **Monitor costs** weekly with AWS Cost Explorer
6. **Review logs** regularly: `make logs ENV=prod`
7. **Keep dependencies updated** with Dependabot PRs
8. **Use version tags** for production deployments
9. **Document custom changes** in your fork
10. **Follow conventional commits** for clear history

## 📝 Cheat Sheet

```bash
# Quick deploy to dev
make deploy ENV=dev

# Check production health
make health-check ENV=prod

# View error logs
./scripts/view-logs.sh prod all --filter ERROR

# Estimate costs
make cost-estimate

# Generate graph
make graph

# Show outputs
make output

# Destroy dev environment
./scripts/destroy.sh dev --dry-run
./scripts/destroy.sh dev
```

---

**Bookmark this page** for quick reference! 🔖

