# GitHub Actions Configuration

## Required Secrets

Configure these secrets in your GitHub repository settings:

### AWS Credentials
- `AWS_ACCESS_KEY_ID` - AWS access key for deployment
- `AWS_SECRET_ACCESS_KEY` - AWS secret key for deployment  
- `AWS_ACCOUNT_ID` - Your AWS account ID (12-digit number)

## Optional Variables

Configure these variables in your GitHub repository settings for customization:

### AWS Configuration
- `AWS_REGION` - AWS region for deployments (defaults to `us-west-2`)

## Setting Up Secrets and Variables

1. Go to your GitHub repository
2. Click **Settings** → **Secrets and variables** → **Actions**
3. Add the required secrets under the **Secrets** tab
4. Add optional variables under the **Variables** tab

## Security Best Practices

### AWS Credentials
- Use IAM roles with minimal required permissions
- Consider using OIDC (OpenID Connect) instead of long-lived access keys
- Rotate credentials regularly
- Use separate AWS accounts for different environments

### Environment Isolation
- Use different AWS accounts for prod vs dev/staging
- Configure environment-specific secrets if needed
- Enable branch protection rules for production deployments

## Workflow Triggers

The deployment workflow runs on:
- **Push to main branch** - Automatically deploys to dev environment
- **Manual trigger** - Choose environment (dev/staging/prod) and auto-approve option

## Environment-Specific Configuration

Each environment uses its own configuration files:
- `terraform/environments/dev.tfvars`
- `terraform/environments/staging.tfvars` 
- `terraform/environments/prod.tfvars`

The workflow automatically selects the correct configuration based on the chosen environment.
