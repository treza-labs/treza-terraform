# Multi-Environment Example

Complete setup demonstrating how to manage multiple environments (dev, staging, production) with proper isolation, progressive deployment strategies, and environment-specific configurations.

## 🎯 Overview

This example shows how to:
- Manage separate dev, staging, and production environments
- Use environment-specific configurations
- Implement progressive deployment strategies
- Maintain proper isolation between environments
- Share common infrastructure patterns

**Total Estimated Cost**: ~$500/month (all environments)
**Deployment Time**: ~45 minutes per environment

## 📊 Environment Comparison

| Feature | Development | Staging | Production |
|---------|-------------|---------|------------|
| **Purpose** | Active development | Pre-production testing | Live workloads |
| **Availability Zones** | 2 | 2 | 3 |
| **ECS Resources** | 512 CPU / 1024 MB | 1024 CPU / 2048 MB | 2048 CPU / 4096 MB |
| **Log Retention** | 7 days | 14 days | 90 days |
| **Timeouts** | 20 min deploy / 15 min destroy | 30 min deploy / 20 min destroy | 60 min deploy / 40 min destroy |
| **VPC CIDR** | 10.0.0.0/16 | 10.1.0.0/16 | 10.2.0.0/16 |
| **AWS Region** | us-west-2 | us-west-2 | us-east-1 |
| **Cost** | ~$50/month | ~$100/month | ~$250/month |
| **Backups** | None | Daily | Hourly + Cross-region |
| **Monitoring** | Basic | Standard | Comprehensive |

## 🏗️ Architecture

### Environment Isolation

```
┌─────────────────────────────────────────────────────────────┐
│                     AWS Account                              │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────┐ │
│  │  Development    │  │    Staging      │  │ Production  │ │
│  │  us-west-2      │  │   us-west-2     │  │  us-east-1  │ │
│  │                 │  │                 │  │             │ │
│  │  VPC: 10.0/16   │  │  VPC: 10.1/16   │  │ VPC: 10.2/16│ │
│  │  State: dev     │  │  State: staging │  │ State: prod │ │
│  │  DDB: *-dev     │  │  DDB: *-staging │  │ DDB: *-prod │ │
│  └─────────────────┘  └─────────────────┘  └─────────────┘ │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## 🚀 Deployment Strategy

### Phase 1: Development Environment

```bash
# 1. Create backend
./scripts/create-backend.sh dev

# 2. Configure
cp examples/multi-environment/dev.tfvars terraform/terraform.tfvars
cp examples/multi-environment/backend-dev.conf terraform/backend.conf

# 3. Deploy
cd terraform
terraform init -backend-config=backend.conf
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars

# 4. Verify
make health-check ENV=dev
```

### Phase 2: Staging Environment

```bash
# 1. Create backend
./scripts/create-backend.sh staging

# 2. Switch environment
./scripts/switch-environment.sh staging

# 3. Deploy
terraform init -backend-config=environments/backend-staging.conf
terraform plan -var-file=environments/staging.tfvars
terraform apply -var-file=environments/staging.tfvars

# 4. Verify
make health-check ENV=staging
```

### Phase 3: Production Environment

```bash
# 1. Create backend (different region)
./scripts/create-backend.sh prod

# 2. Switch environment
./scripts/switch-environment.sh prod

# 3. Pre-deployment validation
make validate-all ENV=prod
make pre-deploy ENV=prod

# 4. Deploy (requires approval)
terraform apply -var-file=environments/prod.tfvars

# 5. Verify
make health-check ENV=prod
```

## 📝 Configuration Files

### Development (dev.tfvars)

```hcl
# Development Environment - Optimized for fast iteration
aws_region   = "us-west-2"
environment  = "dev"
project_name = "treza"

existing_dynamodb_table_name = "treza-enclaves-dev"

vpc_cidr = "10.0.0.0/16"
availability_zones = ["us-west-2a", "us-west-2b"]

# Minimal resources for cost savings
terraform_runner_cpu    = 512
terraform_runner_memory = 1024

deployment_timeout_seconds = 1200
destroy_timeout_seconds    = 900

log_retention_days = 7

additional_tags = {
  Environment = "Development"
  ManagedBy   = "Terraform"
  Team        = "Engineering"
}
```

### Staging (staging.tfvars)

```hcl
# Staging Environment - Production-like for testing
aws_region   = "us-west-2"
environment  = "staging"
project_name = "treza"

existing_dynamodb_table_name = "treza-enclaves-staging"

vpc_cidr = "10.1.0.0/16"
availability_zones = ["us-west-2a", "us-west-2b"]

# Moderate resources
terraform_runner_cpu    = 1024
terraform_runner_memory = 2048

deployment_timeout_seconds = 1800
destroy_timeout_seconds    = 1200

log_retention_days = 14

additional_tags = {
  Environment = "Staging"
  ManagedBy   = "Terraform"
  Team        = "Engineering"
}
```

### Production (prod.tfvars)

```hcl
# Production Environment - High availability
aws_region   = "us-east-1"  # Different region
environment  = "prod"
project_name = "treza"

existing_dynamodb_table_name = "treza-enclaves-prod"

vpc_cidr = "10.2.0.0/16"
availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]

# Production-grade resources
terraform_runner_cpu    = 2048
terraform_runner_memory = 4096

deployment_timeout_seconds = 3600
destroy_timeout_seconds    = 2400

log_retention_days = 90

additional_tags = {
  Environment  = "Production"
  ManagedBy    = "Terraform"
  Team         = "Engineering"
  Compliance   = "SOC2"
  BackupPolicy = "Daily"
}
```

## 🔄 Workflow: Code Promotion

### 1. Develop in Dev

```bash
# Make changes
git checkout -b feature/my-feature

# Test in dev
make deploy ENV=dev
make health-check ENV=dev

# Verify functionality
./scripts/view-logs.sh dev --follow
```

### 2. Test in Staging

```bash
# Merge to main/develop branch
git checkout main
git merge feature/my-feature

# Deploy to staging
make deploy ENV=staging

# Run integration tests
./tests/integration/run-tests.sh staging

# Monitor for 24-48 hours
./scripts/view-logs.sh staging --filter ERROR
```

### 3. Promote to Production

```bash
# Create release tag
./scripts/version.sh bump minor
git push --tags

# Deploy to production during maintenance window
make pre-deploy ENV=prod
make deploy ENV=prod

# Monitor closely
./scripts/view-logs.sh prod --follow

# Verify health
make health-check ENV=prod
```

## 🔐 Security Considerations

### Environment Isolation

1. **Separate State Backends**: Each environment has its own S3 bucket
2. **Separate VPCs**: No network connectivity between environments
3. **Separate IAM Roles**: Least privilege per environment
4. **Separate KMS Keys**: Different encryption keys per environment

### Access Control

```hcl
# Development: Team members have full access
# Staging: Requires approval for changes
# Production: Restricted to senior engineers + approval
```

### Secrets Management

```bash
# Different secrets per environment
aws secretsmanager create-secret \
  --name treza/dev/database-password \
  --secret-string "dev-password"

aws secretsmanager create-secret \
  --name treza/prod/database-password \
  --secret-string "strong-prod-password"
```

## 📊 Monitoring Strategy

### Development
- Basic CloudWatch dashboards
- Error alerts only
- 7-day log retention

### Staging
- Standard CloudWatch dashboards
- Error and warning alerts
- 14-day log retention
- Weekly cost reviews

### Production
- Comprehensive CloudWatch dashboards
- Multi-level alerts (critical, warning, info)
- 90-day log retention
- SNS notifications to on-call
- PagerDuty integration
- Daily cost reviews

## 💰 Cost Management

### Monthly Cost Breakdown

**Development** (~$50/month):
- VPC & NAT: ~$35
- ECS Tasks: ~$5
- Lambda: ~$2
- CloudWatch: ~$3
- Other: ~$5

**Staging** (~$100/month):
- VPC & NAT: ~$35
- ECS Tasks: ~$20
- Lambda: ~$5
- CloudWatch: ~$10
- VPC Endpoints: ~$20
- Other: ~$10

**Production** (~$250/month):
- VPC & NAT: ~$96 (3 AZs)
- ECS Tasks: ~$60
- Lambda: ~$10
- CloudWatch: ~$30
- VPC Endpoints: ~$30
- Backups: ~$10
- Other: ~$14

**Total**: ~$400-500/month (all environments)

### Cost Optimization

```bash
# Destroy dev environment overnight
# (Use EventBridge + Lambda to automate)

# Scale down staging on weekends
# (Adjust task CPU/memory on schedule)

# Review and optimize production monthly
./scripts/health-check.sh prod --cost-analysis
```

## 🧪 Testing Strategy

### Development Testing
- Unit tests
- Local integration tests
- Manual testing

### Staging Testing
- Full integration test suite
- Load testing
- Security scanning
- User acceptance testing (UAT)

### Production Testing
- Smoke tests after deployment
- Canary deployments (advanced)
- Continuous monitoring

## 🔧 Maintenance

### Regular Tasks

**Weekly**:
```bash
# Review all environments
for env in dev staging prod; do
  echo "Checking $env..."
  make health-check ENV=$env
done

# Review Dependabot PRs
# Deploy to dev first, then staging, then prod
```

**Monthly**:
```bash
# Update Terraform modules
terraform init -upgrade

# Review and optimize costs
aws ce get-cost-and-usage --time-period Start=2024-01-01,End=2024-01-31

# Rotate credentials
# Audit IAM policies
# Review CloudWatch retention
```

### Disaster Recovery

**Backup Strategy**:
- Dev: No backups (recreate from code)
- Staging: Daily state backups
- Production: Hourly state backups + cross-region replication

**Recovery**:
```bash
# Restore from backup
aws s3 cp s3://backup-bucket/prod/terraform.tfstate terraform.tfstate

# Redeploy
terraform apply
```

## 🚨 Troubleshooting

### Different Behaviors Across Environments

1. Check configuration differences:
```bash
diff environments/dev.tfvars environments/prod.tfvars
```

2. Verify backend state:
```bash
terraform state list
```

3. Compare resource configurations:
```bash
terraform show -json | jq '.values'
```

### State Drift

```bash
# Check for drift
terraform plan -refresh=true

# Refresh state
terraform apply -refresh-only

# If severe, import resources
terraform import aws_vpc.main vpc-xxx
```

## 📚 Additional Resources

- [AWS Multi-Environment Best Practices](https://aws.amazon.com/blogs/architecture/)
- [Terraform Workspaces](https://www.terraform.io/docs/language/state/workspaces.html)
- [Environment-Specific Variables](https://www.terraform-best-practices.com/)

## 📞 Support

Questions about multi-environment setup?
- Check [FAQ](../../docs/FAQ.md)
- Review [Troubleshooting Guide](../../docs/TROUBLESHOOTING.md)
- Open [GitHub Discussion](https://github.com/treza-labs/treza-terraform/discussions)

---

**Pro Tip**: Always test infrastructure changes in dev → staging → prod order. Never skip staging!

