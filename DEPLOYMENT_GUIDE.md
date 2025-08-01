# Treza Terraform Infrastructure - Deployment Guide

## 🚀 Quick Deployment Checklist

### Prerequisites ✅
- [ ] AWS CLI configured with appropriate permissions
- [ ] Terraform >= 1.6.0 installed  
- [ ] Docker installed (for container builds)
- [ ] Existing DynamoDB table from treza-app

### Step 1: Environment Configuration

1. **Configure Terraform Variables**
   ```bash
   cp terraform/terraform.tfvars.example terraform/terraform.tfvars
   # Edit terraform.tfvars with your specific values
   ```

2. **Configure Backend State**
   ```bash
   cp terraform/backend.conf.example terraform/backend.conf
   # Edit backend.conf with your S3 bucket details
   ```

3. **Key Variables to Set**
   ```hcl
   # In terraform/terraform.tfvars
   existing_dynamodb_table_name = "your-treza-enclaves-table"
   aws_region = "your-aws-region"
   environment = "dev" # or staging/prod
   ```

### Step 2: Deploy Infrastructure

```bash
# Navigate to terraform directory
cd terraform

# Initialize Terraform with your backend
terraform init -backend-config=backend.conf

# Review the deployment plan
terraform plan

# Deploy the infrastructure  
terraform apply
```

### Step 3: Build and Deploy Container

```bash
# Return to project root
cd ..

# Set environment variables
export AWS_REGION=us-west-2  # Your region
export IMAGE_NAME=treza-dev-terraform-runner

# Build and push Docker image
./docker/scripts/build-and-push.sh
```

### Step 4: Verify Deployment

1. **Check AWS Resources**
   - Step Functions: AWS Console → Step Functions
   - Lambda Functions: AWS Console → Lambda
   - ECS Cluster: AWS Console → ECS
   - CloudWatch Dashboard: Check terraform outputs

2. **Test the Workflow**
   ```bash
   # Update a record in your DynamoDB table with:
   # status: "PENDING_DEPLOY"
   # This should trigger the deployment workflow
   ```

## 🔧 Environment-Specific Configurations

### Development Environment
```hcl
environment = "dev"
terraform_runner_cpu = 1024
terraform_runner_memory = 2048
log_retention_days = 7
```

### Staging Environment  
```hcl
environment = "staging"
terraform_runner_cpu = 2048
terraform_runner_memory = 4096
log_retention_days = 14
```

### Production Environment
```hcl
environment = "prod"
terraform_runner_cpu = 4096
terraform_runner_memory = 8192
log_retention_days = 30
```

## 🔒 Security Checklist

- [ ] IAM roles follow least privilege principle
- [ ] S3 state bucket has encryption enabled
- [ ] DynamoDB state locking table configured
- [ ] VPC endpoints configured for cost optimization
- [ ] Security groups restrict access appropriately
- [ ] Lambda functions have minimal permissions

## 📊 Monitoring Setup

After deployment, you'll have:

1. **CloudWatch Dashboard**: Overview of Step Functions and ECS metrics
2. **CloudWatch Alarms**: Automated alerts for failures
3. **Log Insights**: Structured queries for troubleshooting
4. **Distributed Tracing**: End-to-end workflow visibility

Access via: `terraform output cloudwatch_dashboard_url`

## 🚨 Troubleshooting

### Common Issues

1. **Backend Configuration Error**
   ```bash
   # Check your backend.conf file
   cat terraform/backend.conf
   # Ensure S3 bucket exists and you have access
   ```

2. **ECR Push Permissions**
   ```bash
   # Check AWS credentials
   aws sts get-caller-identity
   # Ensure ECR permissions in your AWS account
   ```

3. **DynamoDB Table Not Found**
   ```bash
   # Verify table exists
   aws dynamodb describe-table --table-name your-table-name
   ```

4. **Terraform Plugin Timeout**
   ```bash
   # Clean and retry
   rm -rf .terraform .terraform.lock.hcl
   terraform init -backend-config=backend.conf
   ```

### Debug Mode

Enable detailed logging:
```bash
export TF_LOG=DEBUG
export AWS_CLI_DEBUG=1
terraform apply
```

## 🔄 Workflow Testing

### Test Enclave Deployment

1. **Add test record to DynamoDB**:
   ```json
   {
     "id": "test-enclave-001",
     "status": "PENDING_DEPLOY", 
     "configuration": {
       "instance_type": "m5.large",
       "cpu_count": 2,
       "memory_mib": 1024,
       "eif_path": "s3://your-bucket/test.eif"
     }
   }
   ```

2. **Monitor Step Functions**:
   - AWS Console → Step Functions
   - Watch the execution progress
   - Check CloudWatch logs for details

3. **Verify Deployment**:
   - Check DynamoDB for status updates
   - Monitor ECS tasks in AWS Console
   - Review CloudWatch dashboard metrics

### Test Cleanup

1. **Update record for cleanup**:
   ```json
   {
     "id": "test-enclave-001", 
     "status": "PENDING_DESTROY"
   }
   ```

2. **Monitor cleanup workflow**:
   - Check Step Functions console
   - Verify resources are cleaned up
   - Confirm status updated to "DESTROYED"

## 📈 Performance Optimization

### Cost Optimization
- VPC endpoints reduce NAT Gateway costs
- Fargate Spot instances for non-critical workloads
- CloudWatch log retention optimization
- Lambda concurrency limits

### Performance Tuning
- ECS task CPU/memory based on workload
- Step Functions timeout configuration
- Lambda timeout and memory allocation
- CloudWatch alarm thresholds

## 🔄 Maintenance

### Regular Tasks
- [ ] Monitor CloudWatch dashboards
- [ ] Review Lambda function logs
- [ ] Check Step Functions execution history
- [ ] Update container images periodically
- [ ] Review and update IAM permissions

### Updates
```bash
# Update infrastructure
terraform plan
terraform apply

# Update container image
./docker/scripts/build-and-push.sh
```

---

## 🎯 Next Steps After Deployment

1. **Integration Testing**: Test with real enclave workloads
2. **CI/CD Pipeline**: Automate deployments with GitHub Actions  
3. **Monitoring Enhancement**: Add custom metrics and alerts
4. **Security Hardening**: Regular security reviews and updates
5. **Documentation**: Update runbooks and operational procedures

For support, refer to the main [README.md](README.md) or create an issue in the repository.