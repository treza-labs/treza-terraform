# GitHub Actions Deployment Instructions

## 🚀 Deploy Treza Infrastructure via GitHub Actions

### Prerequisites
You need to set up GitHub repository secrets for AWS access.

### Step 1: Configure GitHub Secrets

Go to your GitHub repository: `https://github.com/treza-labs/treza-terraform/settings/secrets/actions`

Add these repository secrets:

1. **AWS_ACCESS_KEY_ID**: Your AWS access key
2. **AWS_SECRET_ACCESS_KEY**: Your AWS secret key  
3. **AWS_ACCOUNT_ID**: Your AWS account ID (e.g., `314146326535`)

### Step 2: Run the Deployment

1. Go to **Actions** tab in your GitHub repository
2. Click on **"Deploy Treza Infrastructure"** workflow
3. Click **"Run workflow"**
4. Select:
   - **Environment**: `dev` (for testing)
   - **Auto approve**: `true` (for automatic deployment)
5. Click **"Run workflow"**

### Step 3: Monitor Progress

The workflow will:
- ✅ Create AWS backend resources (if needed)
- ✅ Build Lambda functions
- ✅ Deploy complete infrastructure
- ✅ Build and push Docker image
- ✅ Provide deployment summary

### Step 4: Verify Deployment

After successful deployment, check AWS Console:

1. **Lambda Functions**: Search for `treza-dev-*`
2. **Step Functions**: Look for `treza-dev-deployment`
3. **ECS**: Check `treza-dev-infrastructure` cluster
4. **VPC**: Verify `treza-dev-vpc` was created
5. **CloudWatch**: Check dashboards and logs

### Step 5: Integration with Your App

Once deployed, update your app integration:

1. **Get your DynamoDB table name** from your treza-app
2. **Update the configuration**:
   ```bash
   # Edit terraform/terraform.tfvars
   existing_dynamodb_table_name = "your-actual-table-name"
   ```
3. **Redeploy** with the updated configuration

### Expected Timeline

- **GitHub Actions deployment**: 10-15 minutes
- **Full infrastructure**: All AWS resources created
- **Ready for testing**: Immediately after deployment

### Troubleshooting

If deployment fails:

1. **Check GitHub Actions logs** for detailed error messages
2. **Verify AWS permissions** - the IAM user needs full access for deployment
3. **Check AWS quotas** - ensure you have capacity for new resources
4. **Review Terraform logs** in the Actions output

### Next Steps After Deployment

1. **Test Lambda functions** in AWS Console
2. **Verify Step Functions** workflows
3. **Test Docker container** can run Terraform
4. **Connect to your treza-app** DynamoDB table
5. **Run end-to-end enclave creation test**

## 🎯 Ready for Enclave Creation!

Once deployed, your web app can trigger enclave creation by writing to DynamoDB:

```json
{
  "id": "test-enclave-001",
  "status": "PENDING_DEPLOY",
  "configuration": {
    "instance_type": "m5.large",
    "cpu_count": 2,
    "memory_mib": 1024,
    "eif_path": "s3://your-bucket/enclave.eif"
  }
}
```

The infrastructure will automatically handle the rest! 🚀
