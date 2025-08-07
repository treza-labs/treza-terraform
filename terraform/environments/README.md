# Environment-Specific Configurations

This directory contains environment-specific configuration files for deploying Treza infrastructure across different environments.

## Quick Start

### Development Environment
```bash
# Copy configuration
cp environments/dev.tfvars terraform.tfvars
cp environments/backend-dev.conf backend.conf

# Edit with your specific values
nano terraform.tfvars
nano backend.conf

# Deploy
terraform init -backend-config=backend.conf
terraform plan -var-file=terraform.tfvars
terraform apply
```

### Staging Environment
```bash
cp environments/staging.tfvars terraform.tfvars
cp environments/backend-staging.conf backend.conf
# Edit and deploy as above
```

### Production Environment
```bash
cp environments/prod.tfvars terraform.tfvars
cp environments/backend-prod.conf backend.conf
# Edit and deploy as above
```

## Environment Differences

| Setting | Dev | Staging | Prod |
|---------|-----|---------|------|
| VPC CIDR | 10.0.0.0/16 | 10.1.0.0/16 | 10.2.0.0/16 |
| AZs | 2 | 3 | 3 |
| ECS CPU | 512 | 1024 | 2048 |
| ECS Memory | 1024 MB | 2048 MB | 4096 MB |
| Log Retention | 7 days | 14 days | 90 days |
| Timeouts | Shorter | Standard | Generous |

## Configuration Files

### Variable Files (*.tfvars)
- `dev.tfvars` - Development environment settings
- `staging.tfvars` - Staging environment settings  
- `prod.tfvars` - Production environment settings

### Backend Files (backend-*.conf)
- `backend-dev.conf` - Development state backend
- `backend-staging.conf` - Staging state backend
- `backend-prod.conf` - Production state backend

## Customization

Before deploying:

1. **Update DynamoDB table names** to match your treza-app tables
2. **Review VPC CIDRs** to avoid conflicts with existing networks
3. **Adjust resource sizing** based on your performance requirements
4. **Update tags** to match your organization's standards
5. **Configure backend buckets** (ensure they exist in your AWS account)

## Security Notes

- Each environment uses separate state buckets for isolation
- Different DynamoDB tables prevent cross-environment interference
- VPC CIDRs are distinct to enable VPC peering if needed
- Tags include environment identification for cost tracking