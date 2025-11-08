# Troubleshooting Guide

This guide provides solutions for common issues you might encounter when deploying and operating Treza Terraform infrastructure.

## 📋 Table of Contents

- [Pre-Deployment Issues](#pre-deployment-issues)
- [Deployment Issues](#deployment-issues)
- [Runtime Issues](#runtime-issues)
- [Performance Issues](#performance-issues)
- [Cost Issues](#cost-issues)
- [Debugging Tools](#debugging-tools)

## Pre-Deployment Issues

### Issue: AWS Credentials Not Configured

**Symptoms**:
```
Error: error configuring Terraform AWS Provider: no valid credential sources
```

**Solution**:
```bash
# Check credentials
aws sts get-caller-identity

# If not configured, set credentials
aws configure

# Or use environment variables
export AWS_ACCESS_KEY_ID="YOUR_KEY"
export AWS_SECRET_ACCESS_KEY="YOUR_SECRET"
export AWS_DEFAULT_REGION="us-west-2"
```

### Issue: Insufficient IAM Permissions

**Symptoms**:
```
Error: creating VPC: UnauthorizedOperation
Error: creating Lambda: AccessDeniedException
```

**Solution**:
1. Verify your IAM user/role has required permissions:
```bash
# Check your identity
aws sts get-caller-identity

# Test specific permissions
aws ec2 describe-vpcs --max-results 1
aws lambda list-functions --max-items 1
```

2. Required IAM permissions (minimum):
- `ec2:*` - VPC and networking
- `ecs:*` - ECS cluster and tasks
- `lambda:*` - Lambda functions
- `states:*` - Step Functions
- `iam:*` - IAM roles and policies
- `logs:*` - CloudWatch Logs
- `dynamodb:*` - DynamoDB operations
- `s3:*` - S3 bucket operations

3. For production, use least privilege policies (see `modules/iam/`)

### Issue: Backend Bucket Doesn't Exist

**Symptoms**:
```
Error: Failed to get existing workspaces: S3 bucket does not exist
```

**Solution**:
```bash
# Create backend infrastructure
./scripts/create-backend.sh dev

# Or manually create
aws s3 mb s3://your-terraform-state-bucket
aws dynamodb create-table \
  --table-name terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST
```

### Issue: DynamoDB Table Not Found

**Symptoms**:
```
Error: reading DynamoDB Table: ResourceNotFoundException
```

**Solution**:
1. Ensure treza-app is deployed first with DynamoDB table
2. Verify table name in `terraform.tfvars`:
```bash
aws dynamodb describe-table --table-name treza-enclaves-dev
```
3. Update `existing_dynamodb_table_name` in your configuration

### Issue: VPC CIDR Conflicts

**Symptoms**:
```
Error: creating VPC: InvalidVpcRange: The specified CIDR block overlaps
```

**Solution**:
```bash
# List existing VPCs
aws ec2 describe-vpcs --query 'Vpcs[*].[VpcId,CidrBlock]'

# Choose non-overlapping CIDR
# Change in terraform.tfvars
vpc_cidr = "10.1.0.0/16"  # or any available range
```

## Deployment Issues

### Issue: Terraform State Lock

**Symptoms**:
```
Error: Error locking state: ConditionalCheckFailedException
```

**Solution**:
```bash
# Check for stale lock
aws dynamodb get-item \
  --table-name terraform-locks \
  --key '{"LockID":{"S":"your-state-bucket/env/terraform.tfstate-md5"}}'

# If lock is stale (deployment failed), force unlock
terraform force-unlock LOCK_ID

# Prevention: Always use CTRL+C gracefully, never kill -9
```

### Issue: Module Download Timeout

**Symptoms**:
```
Error: Failed to download module
Error: timeout while waiting for plugin to start
```

**Solution**:
```bash
# Clear module cache
rm -rf .terraform/modules

# Reinitialize
terraform init

# If behind proxy, set environment
export HTTPS_PROXY=http://proxy:8080
terraform init
```

### Issue: Resource Already Exists

**Symptoms**:
```
Error: creating Security Group: InvalidGroup.Duplicate
Error: creating IAM Role: EntityAlreadyExists
```

**Solution**:
```bash
# Import existing resource
terraform import module.networking.aws_security_group.example sg-12345

# Or delete manually and retry
aws ec2 delete-security-group --group-id sg-12345

# Or change resource name
```

### Issue: Docker Build Failures

**Symptoms**:
```
Error: docker build failed
Error: unable to prepare context
```

**Solution**:
```bash
# Ensure Docker is running
docker ps

# Clean Docker cache
docker system prune -a

# Build with correct platform
docker build --platform linux/amd64 -f docker/terraform-runner/Dockerfile .

# Check disk space
df -h
```

### Issue: ECR Push Failures

**Symptoms**:
```
Error: denied: Your authorization token has expired
Error: unable to push image
```

**Solution**:
```bash
# Re-authenticate to ECR
aws ecr get-login-password --region us-west-2 | \
  docker login --username AWS --password-stdin ACCOUNT.dkr.ecr.us-west-2.amazonaws.com

# Ensure ECR repository exists
aws ecr describe-repositories --repository-names treza-dev-terraform-runner

# Create if missing
aws ecr create-repository --repository-name treza-dev-terraform-runner
```

## Runtime Issues

### Issue: Lambda Functions Timing Out

**Symptoms**:
- Lambda execution exceeds timeout
- Partial processing of events
- Step Functions showing Lambda timeouts

**Solution**:
1. Check Lambda logs:
```bash
./scripts/view-logs.sh dev lambda-trigger --since 1h
```

2. Increase timeout in module configuration:
```hcl
# modules/lambda/main.tf
timeout = 300  # Increase from 60 to 300 seconds
```

3. Check network connectivity:
   - Verify VPC endpoints exist
   - Ensure security groups allow outbound traffic
   - Check NAT Gateway is working

4. Optimize Lambda code:
   - Reduce cold start time
   - Optimize dependencies
   - Use Lambda layers for common code

### Issue: ECS Tasks Failing to Start

**Symptoms**:
```
Task stopped with reason: CannotPullContainerError
Task stopped with reason: OutOfMemoryError
```

**Solution**:

**For CannotPullContainerError**:
```bash
# Check task execution role has ECR permissions
aws iam get-role-policy \
  --role-name treza-dev-ecs-task-execution-role \
  --policy-name ECRAccess

# Verify ECR endpoint exists
aws ec2 describe-vpc-endpoints --filters "Name=service-name,Values=com.amazonaws.REGION.ecr.dkr"

# Check image exists
aws ecr describe-images \
  --repository-name treza-dev-terraform-runner \
  --image-ids imageTag=latest
```

**For OutOfMemoryError**:
```bash
# Increase task memory
# In terraform.tfvars
terraform_runner_memory = 4096  # Double the memory
```

### Issue: Step Functions Execution Failures

**Symptoms**:
- Step Functions execution shows "Failed" status
- Workflow stuck in "Running" state
- Timeout errors

**Solution**:
1. Check execution details:
```bash
aws stepfunctions describe-execution \
  --execution-arn "arn:aws:states:REGION:ACCOUNT:execution:NAME:ID"
```

2. View execution history:
```bash
aws stepfunctions get-execution-history \
  --execution-arn "arn:aws:states:REGION:ACCOUNT:execution:NAME:ID" \
  --max-results 100
```

3. Common fixes:
   - Increase timeout in Step Function definition
   - Check ECS task IAM permissions
   - Verify ECS cluster has capacity
   - Check CloudWatch logs for task errors

### Issue: Enclave Logs Not Appearing

**Symptoms**:
- Enclaves deployed but no CloudWatch logs
- Missing application logs

**Solution**:
1. Verify security group configuration:
```bash
# Check if enclave uses shared security group
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=*enclave*" \
  --query 'Reservations[*].Instances[*].SecurityGroups'
```

2. Ensure CloudWatch Logs endpoint exists:
```bash
aws ec2 describe-vpc-endpoints \
  --filters "Name=service-name,Values=com.amazonaws.REGION.logs"
```

3. Verify IAM permissions:
   - Enclave role needs `logs:CreateLogGroup`, `logs:CreateLogStream`, `logs:PutLogEvents`

4. Check enclave user data script:
   - Verify CloudWatch agent is installed
   - Check agent configuration
   - Review bootstrap logs

### Issue: High Error Rates

**Symptoms**:
- Multiple Lambda errors
- Frequent ECS task failures
- Step Functions repeatedly failing

**Solution**:
1. Check CloudWatch dashboard:
```bash
# Access dashboard
aws cloudwatch get-dashboard --dashboard-name treza-dev
```

2. Review error patterns:
```bash
./scripts/view-logs.sh dev all --filter ERROR --since 1h
```

3. Common causes:
   - External API timeouts
   - AWS service limits reached
   - Invalid input data
   - Network connectivity issues

4. Set up alerts:
```hcl
# Add to modules/monitoring/main.tf
resource "aws_cloudwatch_metric_alarm" "high_errors" {
  alarm_name          = "high-error-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}
```

## Performance Issues

### Issue: Slow Deployments

**Symptoms**:
- Enclave deployments taking > 30 minutes
- ECS tasks slow to start

**Solution**:
1. Increase ECS task resources:
```hcl
terraform_runner_cpu    = 2048
terraform_runner_memory = 4096
```

2. Optimize Docker image:
```bash
# Multi-stage build
# Minimize layers
# Use .dockerignore
```

3. Check NAT Gateway metrics:
```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/NATGateway \
  --metric-name BytesOutToSource \
  --dimensions Name=NatGatewayId,Value=nat-xxx \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-01-02T00:00:00Z \
  --period 3600 \
  --statistics Average
```

### Issue: High Lambda Duration

**Symptoms**:
- Lambda executions > 10 seconds
- High costs from Lambda duration

**Solution**:
1. Analyze Lambda performance:
```bash
aws logs filter-log-events \
  --log-group-name /aws/lambda/treza-dev-enclave-trigger \
  --filter-pattern "[report_type=REPORT, ...]" \
  --limit 100
```

2. Optimize:
   - Increase memory (improves CPU allocation)
   - Remove unused dependencies
   - Use Lambda layers
   - Implement connection pooling
   - Cache frequently used data

3. Consider Lambda SnapStart (Java only)

## Cost Issues

### Issue: Unexpectedly High Costs

**Symptoms**:
- AWS bill higher than estimated
- Cost anomaly alerts

**Solution**:
1. Check Cost Explorer:
```bash
# CLI requires cost explorer to be enabled
aws ce get-cost-and-usage \
  --time-period Start=2024-01-01,End=2024-01-31 \
  --granularity MONTHLY \
  --metrics UnblendedCost \
  --group-by Type=SERVICE
```

2. Common cost drivers:
   - **NAT Gateways**: $32/month each + data transfer
   - **ECS tasks**: Running too long
   - **CloudWatch Logs**: High volume or long retention
   - **Data Transfer**: Cross-AZ or internet egress
   - **VPC Endpoints**: $7/month each

3. Cost optimization:
```bash
# Review and destroy unused resources
./scripts/destroy.sh dev --dry-run

# Reduce log retention
# In terraform.tfvars
log_retention_days = 7  # Instead of 90

# Use single NAT Gateway for dev
# Edit modules/networking/main.tf
```

### Issue: Data Transfer Charges

**Symptoms**:
- High "Data Transfer" line items
- Unexpected egress costs

**Solution**:
1. Use VPC endpoints (already configured)
2. Stay within same AZ when possible
3. Check for unnecessary internet egress:
```bash
# Review VPC Flow Logs
aws logs filter-log-events \
  --log-group-name /aws/vpc/flowlogs \
  --filter-pattern "[version, account, eni, source, destination, srcport, destport, protocol, packets, bytes, start, end, action=ACCEPT, status]" \
  --limit 100
```

## Debugging Tools

### Enable Terraform Debug Logging

```bash
export TF_LOG=DEBUG
export TF_LOG_PATH=./terraform-debug.log
terraform apply
```

### Enable AWS CLI Debug

```bash
export AWS_CLI_DEBUG=1
aws ec2 describe-vpcs
```

### Check Resource Dependencies

```bash
# Generate dependency graph
terraform graph | dot -Tsvg > graph.svg
```

### Validate Terraform Configuration

```bash
# Format check
terraform fmt -check -recursive

# Validation
terraform validate

# Security scan
tfsec .
checkov -d .

# Linting
tflint --recursive
```

### Monitor Real-Time Logs

```bash
# Follow all logs
./scripts/view-logs.sh dev all --follow

# Filter for errors
./scripts/view-logs.sh dev all --filter ERROR --follow

# Specific component
./scripts/view-logs.sh dev ecs-runner --follow --since 30m
```

### Health Check

```bash
# Overall health
make health-check ENV=dev

# Or detailed script
./scripts/health-check.sh dev
```

### AWS Resource Inspector

```bash
# Check VPC configuration
aws ec2 describe-vpcs --filters "Name=tag:Environment,Values=dev"

# Check running ECS tasks
aws ecs list-tasks --cluster treza-dev

# Check Lambda functions
aws lambda list-functions --query 'Functions[?starts_with(FunctionName, `treza-dev`)]'

# Check Step Functions
aws stepfunctions list-state-machines
```

## Getting Additional Help

If you're still experiencing issues:

1. **Check existing issues**: [GitHub Issues](https://github.com/treza-labs/treza-terraform/issues)
2. **Search discussions**: [GitHub Discussions](https://github.com/treza-labs/treza-terraform/discussions)
3. **Review FAQ**: [FAQ.md](./FAQ.md)
4. **Open new issue**: Provide:
   - Error messages (redact sensitive info)
   - Terraform version
   - AWS region
   - Steps to reproduce
   - Relevant logs

## Prevention Best Practices

1. **Always test in dev first**
2. **Run `terraform plan` before `apply`**
3. **Use version control** for all changes
4. **Enable CloudTrail** for audit trail
5. **Set up alerts** for critical metrics
6. **Regular backups** of state files
7. **Review costs** weekly
8. **Keep dependencies updated**
9. **Document custom changes**
10. **Follow security best practices**

---

**Remember**: When in doubt, check the logs! 📝

