# Treza Infrastructure → Web App Integration Roadmap

## 🎯 Goal: End-to-End Enclave Creation from Web App

This roadmap shows the steps to get from our current state to a fully functional system where your web app can trigger enclave creation.

## 📊 Current Status: 95% Complete Infrastructure

### ✅ What's Ready
- **Complete Terraform Infrastructure** (8 modules, production-ready)
- **Lambda Functions** (source code + automated builds)
- **Step Functions** (deployment + cleanup workflows)
- **Docker Infrastructure** (Terraform runner containerization)
- **Environment Configurations** (dev/staging/prod)
- **Backend Validation** (automated S3 + DynamoDB setup)
- **GitHub Repository** (clean, documented, CI/CD ready)

### 🎯 What's Needed for End-to-End Testing

## Phase 1: Infrastructure Deployment (30 minutes)

### Step 1: Create Backend Resources
```bash
# This creates the S3 bucket and DynamoDB table for Terraform state
./scripts/create-backend.sh dev
```

**What this does:**
- Creates `treza-terraform-state-dev` S3 bucket (versioned, encrypted)
- Creates `treza-terraform-locks-dev` DynamoDB table
- Configures proper security settings

### Step 2: Deploy Infrastructure
```bash
# This deploys all AWS resources
./scripts/deploy.sh dev
```

**What this creates:**
- VPC with public/private subnets
- ECS cluster for Terraform runner
- Lambda functions (trigger, validation, error handler)
- Step Functions workflows
- IAM roles and policies
- CloudWatch dashboards and alarms
- ECR repository for Docker images

## Phase 2: Integration Setup (30-60 minutes)

### Step 3: Connect to Your Treza App
1. **Update DynamoDB table name** in `terraform/terraform.tfvars`:
   ```hcl
   existing_dynamodb_table_name = "your-actual-treza-app-table"
   ```

2. **Enable DynamoDB Streams** on your existing table:
   ```bash
   aws dynamodb update-table \
     --table-name your-actual-treza-app-table \
     --stream-specification StreamEnabled=true,StreamViewType=NEW_AND_OLD_IMAGES
   ```

3. **Redeploy** to connect to your table:
   ```bash
   terraform apply
   ```

### Step 4: Build and Push Docker Image
```bash
# Build the Terraform runner container
./docker/scripts/build-and-push.sh
```

## Phase 3: End-to-End Testing (30 minutes)

### Step 5: Test the Complete Workflow

1. **Insert test record** in your DynamoDB table:
   ```json
   {
     "id": "test-enclave-001",
     "status": "PENDING_DEPLOY",
     "configuration": {
       "instance_type": "m5.large",
       "cpu_count": 2,
       "memory_mib": 1024,
       "eif_path": "s3://your-bucket/test.eif",
       "debug_mode": true
     },
     "created_at": "2025-01-01T12:00:00Z"
   }
   ```

2. **Monitor the workflow**:
   - DynamoDB Streams triggers Lambda
   - Lambda starts Step Functions
   - Step Functions runs Terraform in ECS
   - Status updates back to DynamoDB

3. **Verify in AWS Console**:
   - Step Functions: Watch execution progress
   - ECS: Monitor task execution
   - CloudWatch: Check logs and metrics
   - EC2: Verify enclave instance creation

## 🚀 Timeline Summary

| Phase | Duration | Tasks | Result |
|-------|----------|-------|---------|
| **Phase 1** | 30 min | Deploy infrastructure | AWS resources ready |
| **Phase 2** | 30-60 min | Connect to treza-app | Integration complete |
| **Phase 3** | 30 min | End-to-end testing | 🎉 **READY FOR PRODUCTION** |

**Total Time: 1.5-2 hours to fully functional system**

## 🔍 Monitoring & Verification

### CloudWatch Dashboard
- Real-time metrics for Step Functions and ECS
- Error rates and execution counts
- Performance monitoring

### Logs Locations
- **Lambda Logs**: `/aws/lambda/treza-dev-*`
- **Step Functions**: `/aws/stepfunctions/treza-dev-deployment`
- **ECS Tasks**: `/ecs/treza-dev-terraform-runner`

### Success Indicators
- ✅ DynamoDB record status: `"DEPLOYING"` → `"DEPLOYED"`
- ✅ EC2 instance created with Nitro Enclave enabled
- ✅ CloudWatch shows successful Step Functions execution
- ✅ No errors in Lambda function logs

## 🛠️ Troubleshooting Guide

### Common Issues & Solutions

1. **Backend creation fails**
   - Check AWS credentials: `aws sts get-caller-identity`
   - Verify permissions for S3 and DynamoDB

2. **Terraform deployment fails**
   - Check Terraform logs for specific errors
   - Verify all required AWS services are available in region

3. **Lambda functions fail**
   - Check CloudWatch logs for detailed error messages
   - Verify IAM permissions for Lambda execution

4. **Step Functions timeout**
   - Check ECS task logs for Terraform execution details
   - Verify network connectivity for Terraform downloads

## 🎯 After Successful Testing

Once end-to-end testing is complete, you can:

1. **Integrate with your web app**:
   - Web app writes to DynamoDB with `status: "PENDING_DEPLOY"`
   - Infrastructure automatically handles the rest

2. **Scale to production**:
   - Run `./scripts/setup-environment.sh prod`
   - Deploy to production environment

3. **Add monitoring**:
   - Set up alerts for failures
   - Configure notifications
   - Add custom metrics

**Result**: Your web app can trigger secure enclave creation with a simple DynamoDB write! 🚀