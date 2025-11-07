# Production-Ready Example

Enterprise-grade configuration with high availability, enhanced security, and comprehensive monitoring. Designed for production workloads and compliance requirements.

## 🎯 Overview

This example deploys:
- Highly available VPC across 3 availability zones
- Production-grade ECS cluster with auto-scaling
- Comprehensive VPC endpoints for all AWS services
- Advanced monitoring, alerting, and dashboards
- Enhanced security controls and logging
- 90-day log retention for compliance

**Estimated Monthly Cost**: ~$200-300 USD
**Deployment Time**: ~30 minutes

## 📋 Prerequisites

- AWS CLI configured with admin access
- Terraform >= 1.6.0
- Production DynamoDB table from treza-app
- Docker for container builds
- Domain/Route53 (optional, for custom endpoints)

## 🚀 Deployment Steps

### 1. Create Backend Infrastructure

```bash
# Create production backend with versioning and encryption
./scripts/create-backend.sh prod
```

### 2. Configure Variables

```bash
cd examples/production-ready
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with production values:

```hcl
aws_region   = "us-east-1"
environment  = "prod"
project_name = "treza"

existing_dynamodb_table_name = "treza-enclaves-prod"

vpc_cidr = "10.2.0.0/16"
availability_zones = [
  "us-east-1a",
  "us-east-1b",
  "us-east-1c"
]

# Production-grade resources
terraform_runner_cpu    = 2048
terraform_runner_memory = 4096

# Generous timeouts for large deployments
deployment_timeout_seconds = 3600  # 1 hour
destroy_timeout_seconds    = 2400  # 40 minutes

# Long retention for compliance
log_retention_days = 90

# Production tags for governance
additional_tags = {
  Environment  = "Production"
  Compliance   = "SOC2"
  CostCenter   = "Infrastructure"
  Owner        = "DevOps-Team"
  BusinessUnit = "Engineering"
}
```

### 3. Validate Configuration

```bash
cd ../../terraform

# Initialize
terraform init -backend-config=environments/backend-prod.conf

# Validate
terraform validate

# Security scan
tfsec .
checkov -d .

# Plan and review
terraform plan -var-file=environments/prod.tfvars -out=prod.tfplan
```

### 4. Deploy (with approval)

```bash
# Review the plan carefully
terraform show prod.tfplan

# Apply with approval
terraform apply prod.tfplan
```

## 📊 Production Architecture

### High Availability
- **3 Availability Zones**: Full redundancy
- **Multi-AZ NAT Gateways**: No single point of failure
- **ECS Service Discovery**: Built-in service mesh
- **Auto-scaling**: Based on CPU/memory metrics

### Security Enhancements
- **VPC Flow Logs**: All network traffic logged
- **AWS Config**: Compliance monitoring
- **CloudTrail**: API call auditing
- **KMS Encryption**: All data encrypted at rest
- **Secrets Manager**: Secure credential storage
- **WAF Integration** (optional): DDoS protection

### Monitoring & Alerting
- **CloudWatch Dashboards**: Real-time metrics
- **SNS Alerts**: Email/SMS notifications
- **Lambda Errors**: Automatic alerting
- **ECS Task Failures**: Immediate notifications
- **Step Function Failures**: Workflow alerts
- **Cost Anomaly Detection**: Budget alerts

## 💰 Cost Breakdown

Approximate monthly costs (us-east-1):

| Resource | Cost |
|----------|------|
| VPC & Networking | ~$8 |
| NAT Gateways (3) | ~$96 |
| ECS Fargate Tasks | ~$50-100 (usage-based) |
| Lambda Functions | ~$5-10 |
| CloudWatch Logs (90 days) | ~$20 |
| VPC Endpoints | ~$30 |
| CloudWatch Alarms | ~$5 |
| KMS Keys | ~$1 |
| **Total** | **~$215-270/month** |

**Cost Optimization Tips**:
- Use Reserved Capacity for predictable workloads (-30%)
- Implement S3 lifecycle policies
- Review and optimize CloudWatch retention
- Consider Savings Plans

## 🔒 Security Best Practices

### Applied in This Example

✅ **Network Security**
- Private subnet deployment only
- VPC endpoints for all AWS services
- Security groups with least privilege
- Network ACLs for additional layer

✅ **Data Security**
- Encrypted EBS volumes
- Encrypted S3 state backend with versioning
- KMS customer managed keys
- Secrets Manager for sensitive data

✅ **Access Control**
- IAM roles with least privilege
- No hardcoded credentials
- MFA enforcement (configure separately)
- Service-to-service auth via IAM roles

✅ **Monitoring & Auditing**
- CloudTrail enabled for all regions
- VPC Flow Logs
- CloudWatch Logs with 90-day retention
- AWS Config for compliance

✅ **Compliance**
- SOC 2 Type II controls
- HIPAA-ready (additional steps required)
- PCI-DSS considerations
- GDPR data protection

### Additional Hardening (Manual Steps)

1. **Enable GuardDuty**
   ```bash
   aws guardduty create-detector --enable
   ```

2. **Configure AWS Config Rules**
   ```bash
   # Use AWS Config managed rules for compliance
   ```

3. **Set Up Security Hub**
   ```bash
   aws securityhub enable-security-hub
   ```

4. **Enable CloudTrail Organization Trail**
   ```bash
   # For multi-account setups
   ```

## 📈 Monitoring & Alerts

### CloudWatch Dashboard

Access at: AWS Console → CloudWatch → Dashboards → `treza-prod`

**Included Metrics**:
- ECS task count and CPU/memory utilization
- Lambda invocations, errors, duration
- Step Functions executions and failures
- DynamoDB consumed capacity
- VPC endpoint data transfer

### Alert Configuration

Default alerts configured:

| Alert | Threshold | Action |
|-------|-----------|--------|
| Lambda Errors | > 5 in 5 min | SNS notification |
| ECS Task Failures | > 3 in 10 min | SNS notification |
| Step Function Failures | Any failure | SNS notification |
| High CPU | > 80% for 10 min | SNS notification |
| High Memory | > 85% for 10 min | SNS notification |

### Custom Alerts

Add custom alerts in `modules/monitoring/main.tf`.

## 🔄 Disaster Recovery

### Backup Strategy

1. **Terraform State**: S3 versioning enabled, cross-region replication
2. **DynamoDB**: Point-in-time recovery enabled
3. **CloudWatch Logs**: Exported to S3 for long-term storage
4. **ECS Configurations**: Stored in git

### Recovery Procedures

**Complete Region Failure**:
```bash
# Switch to backup region
export AWS_REGION=us-west-2

# Redeploy infrastructure
terraform apply -var-file=environments/prod-dr.tfvars
```

**State File Corruption**:
```bash
# Restore from S3 version
aws s3api list-object-versions \
  --bucket treza-terraform-state-prod \
  --prefix prod/terraform.tfstate

# Download specific version
aws s3api get-object \
  --bucket treza-terraform-state-prod \
  --key prod/terraform.tfstate \
  --version-id <VERSION_ID> \
  terraform.tfstate.backup
```

## 🚀 Performance Tuning

### ECS Task Sizing

Monitor and adjust based on actual usage:

```hcl
# Start with
terraform_runner_cpu    = 2048
terraform_runner_memory = 4096

# Scale up if needed
terraform_runner_cpu    = 4096
terraform_runner_memory = 8192
```

### Timeout Optimization

Adjust based on deployment patterns:

```hcl
# Large infrastructure deployments
deployment_timeout_seconds = 5400  # 90 minutes

# Complex cleanup operations
destroy_timeout_seconds = 3600  # 60 minutes
```

## 📊 Compliance & Governance

### Tagging Strategy

All resources tagged with:
```hcl
additional_tags = {
  Environment  = "Production"
  Project      = "Treza"
  ManagedBy    = "Terraform"
  Compliance   = "SOC2"
  CostCenter   = "Infrastructure"
  Owner        = "DevOps-Team"
  BackupPolicy = "Daily"
  DataClass    = "Confidential"
}
```

### Cost Allocation

Use tags for cost tracking:
- Monthly cost reports by Environment
- Breakdown by CostCenter
- Owner accountability

### Audit Trail

- All changes tracked in git
- Terraform plan output saved
- CloudTrail logs all API calls
- State file changes versioned in S3

## 🧪 Testing & Validation

### Pre-Deployment

```bash
# Run all validation
make validate-all ENV=prod

# Security scan
make security-scan

# Cost estimation
infracost breakdown --path .
```

### Post-Deployment

```bash
# Health check
make health-check ENV=prod

# Smoke tests
./scripts/health-check.sh prod

# Monitor initial deployments
./scripts/view-logs.sh prod --follow
```

## 🔄 Maintenance

### Regular Tasks

**Weekly**:
- Review CloudWatch dashboards
- Check for Dependabot PRs
- Review cost reports

**Monthly**:
- Update Terraform modules
- Review and rotate credentials
- Audit IAM policies
- Review and archive old logs

**Quarterly**:
- Disaster recovery drill
- Security audit
- Performance review
- Cost optimization review

### Update Procedure

```bash
# Always test in staging first!

# Pull latest
git pull

# Review changes
git log --oneline -10

# Plan changes
terraform plan

# Apply during maintenance window
terraform apply
```

## 🗑️ Decommissioning

**Important**: Production destruction requires multiple approvals.

```bash
# Dry run first
./scripts/destroy.sh prod --dry-run

# Review what will be destroyed
# Backup critical data

# Destroy (requires confirmation)
./scripts/destroy.sh prod
```

## 📞 Support & Escalation

- **P1 (Critical)**: Page on-call via PagerDuty
- **P2 (High)**: Slack #infrastructure channel
- **P3 (Medium)**: GitHub Issues
- **P4 (Low)**: GitHub Discussions

## 📚 Additional Resources

- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)
- [Terraform Best Practices](https://www.terraform-best-practices.com/)
- [Security Policy](../../SECURITY.md)

---

**Production Checklist**: Use this [checklist](../../docs/production-checklist.md) before going live.

