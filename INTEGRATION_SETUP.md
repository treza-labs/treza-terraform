# 🔗 Treza App Integration Setup

This guide will help you configure the treza-app to work with the deployed infrastructure.

## 📋 Prerequisites

- ✅ Infrastructure deployed successfully via GitHub Actions
- ✅ DynamoDB table `treza-enclaves` created
- ✅ Lambda functions deployed and connected to DynamoDB streams

## 🔧 Step 1: Configure Environment Variables

Create a `.env.local` file in the `treza-app` directory:

```bash
cd /Users/adaro/PROJECTS/TREZA/DEV/treza-app
```

Create `.env.local` with the following content:

```bash
# AWS Configuration - Use treza-admin credentials
AWS_REGION=us-west-2
AWS_ACCESS_KEY_ID=your-aws-access-key-here
AWS_SECRET_ACCESS_KEY=your-aws-secret-key-here

# DynamoDB Table Names (matching deployed infrastructure)
DYNAMODB_ENCLAVES_TABLE=treza-enclaves
DYNAMODB_TASKS_TABLE=treza-tasks
DYNAMODB_API_KEYS_TABLE=treza-api-keys

# Next.js Configuration
NEXTAUTH_URL=http://localhost:3000
NEXTAUTH_SECRET=treza-dev-secret-key-change-in-production

# Privy Configuration (optional)
NEXT_PUBLIC_PRIVY_APP_ID=your-privy-app-id-here

# GitHub OAuth (optional - for repository connections)
GITHUB_CLIENT_ID=your-github-client-id-here
GITHUB_CLIENT_SECRET=your-github-client-secret-here
```

## 🚀 Step 2: Install Dependencies and Start App

```bash
# Install dependencies
cd /Users/adaro/PROJECTS/TREZA/DEV/treza-app
npm install

# Start the development server
npm run dev
```

The app will be available at: http://localhost:3000

## 🧪 Step 3: Test End-to-End Enclave Creation

1. **Open the app**: Navigate to http://localhost:3000
2. **Sign in**: Use the authentication system
3. **Go to Platform**: Navigate to the platform/enclaves section
4. **Create an Enclave**:
   - Click "Create Enclave"
   - Fill in name and description
   - Select AWS Nitro provider
   - Choose us-west-2 region
   - Configure instance type
   - Click "Create"

## 🔍 Step 4: Monitor the Deployment Process

### Watch DynamoDB:
```bash
# Check if enclave was created in DynamoDB
aws dynamodb scan --table-name treza-enclaves --profile treza-admin
```

### Monitor Lambda Logs:
```bash
# Check Lambda trigger logs
aws logs tail /aws/lambda/treza-dev-enclave-trigger --follow --profile treza-admin

# Check validation logs
aws logs tail /aws/lambda/treza-dev-validation --follow --profile treza-admin
```

### Monitor Step Functions:
1. Go to AWS Console → Step Functions
2. Look for executions of `treza-dev-deployment`
3. Watch the execution progress

## 📊 Expected Workflow:

1. **App Creates Enclave** → Status: `PENDING_DEPLOY`
2. **DynamoDB Stream Triggers** → Lambda: `enclave-trigger`
3. **Validation Lambda** → Validates enclave configuration
4. **Step Functions Starts** → Orchestrates deployment
5. **ECS Task Runs** → Terraform runner deploys actual AWS resources
6. **Status Updates** → `DEPLOYING` → `ACTIVE` or `FAILED`

## 🚫 Troubleshooting:

### If enclave creation fails:
- Check AWS credentials in `.env.local`
- Verify table name matches `treza-enclaves`
- Check browser console for errors

### If Lambda isn't triggering:
- Verify DynamoDB streams are enabled
- Check Lambda permissions
- Look at CloudWatch logs

### If Step Functions aren't starting:
- Check Step Functions execution role permissions
- Verify ECS cluster is running
- Check Step Functions logs in CloudWatch

## 🎯 Success Indicators:

- ✅ Enclave appears in the app with `PENDING_DEPLOY` status
- ✅ Status changes to `DEPLOYING` then `ACTIVE`
- ✅ CloudWatch logs show Lambda executions
- ✅ Step Functions execution completes successfully
- ✅ New AWS resources appear in your account (EC2 instance for Nitro Enclave)

## 📝 Code Changes Made:

1. **Updated DynamoDB table names** to use environment variables
2. **Changed status values** to match infrastructure expectations:
   - `pending` → `PENDING_DEPLOY`
   - Added: `DEPLOYING`, `FAILED`, `PENDING_DESTROY`
3. **Updated UI** to display new status values correctly

Ready to test! 🚀
