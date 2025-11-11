# Treza Terraform Infrastructure

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Terraform](https://img.shields.io/badge/Terraform-%3E%3D1.6.0-623CE4?logo=terraform)](https://www.terraform.io/)
[![AWS](https://img.shields.io/badge/AWS-Nitro%20Enclaves-FF9900?logo=amazon-aws)](https://aws.amazon.com/ec2/nitro/nitro-enclaves/)
[![CI/CD](https://img.shields.io/github/actions/workflow/status/treza-labs/treza-terraform/terraform-ci.yml?branch=main&label=CI%2FCD)](https://github.com/treza-labs/treza-terraform/actions)
[![Security](https://img.shields.io/badge/Security-tfsec%20%7C%20Checkov-blue)](./SECURITY.md)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](./CONTRIBUTING.md)
[![Code of Conduct](https://img.shields.io/badge/Code%20of%20Conduct-Contributor%20Covenant-purple)](./CODE_OF_CONDUCT.md)

A comprehensive Terraform infrastructure for deploying AWS Nitro Enclaves using an event-driven architecture with DynamoDB Streams, Step Functions, and ECS. **Now featuring fully automated shared security group management and optimized user data handling.**

## 🏗️ Architecture Overview

```
DynamoDB Stream → Lambda Trigger → Step Functions → ECS Terraform Runner → AWS Nitro Enclaves
                                      ↓
                              Update DynamoDB Status
```

### Key Components

- **DynamoDB Streams**: Event-driven triggers for enclave lifecycle management
- **Step Functions**: Orchestrate long-running deployment and cleanup workflows  
- **ECS Fargate**: Run Terraform in a secure, containerized environment
- **Lambda Functions**: Handle validation, error processing, and workflow coordination
- **Terraform Modules**: Reusable, production-ready infrastructure components
- **🆕 Shared Security Groups**: Automated VPC endpoint access for all enclaves
- **🆕 Optimized User Data**: Efficient bootstrap scripts under AWS size limits

## 📋 Prerequisites

- AWS CLI configured with appropriate permissions
- Terraform >= 1.6.0
- Docker (for building the Terraform runner container)
- An existing DynamoDB table from treza-app for enclave management
- Make (for convenient commands)

### 🛠️ Developer Setup (Optional but Recommended)
```bash
# Install development tools
pip install pre-commit
brew install tflint tfsec checkov shellcheck terraform-docs  # macOS
# or
apt-get install shellcheck  # Ubuntu

# Setup development environment
make setup-dev
```

## 🚀 Quick Start

### Option 1: Using Examples (Recommended)

We provide ready-to-use examples for different scenarios:

```bash
# Basic development setup (~$50/month)
cd examples/basic-setup
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars and deploy

# Production-ready setup (~$200-300/month)
cd examples/production-ready
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars and deploy
```

See the [examples directory](./examples/) for detailed guides and more options.

### Option 2: Manual Configuration

```bash
git clone <your-repo-url>
cd treza-terraform

# Copy and customize variables
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

### 2. Configure and Create Backend

The backend infrastructure (S3 bucket and DynamoDB table) can be created using our enhanced script:

```bash
# Preview what will be created (dry-run mode)
./scripts/create-backend.sh dev --dry-run

# Create backend resources for development
./scripts/create-backend.sh dev

# Create backend resources for production
./scripts/create-backend.sh prod
```

The script automatically:
- Creates S3 bucket with versioning and encryption enabled
- Blocks public access to the bucket
- Creates DynamoDB table for state locking
- Applies appropriate tags
- Shows cost estimation
- Provides detailed resource summary

Alternatively, manually create a backend configuration file:

```bash
# terraform/backend.conf
bucket         = "your-terraform-state-bucket"
key            = "treza/terraform.tfstate"
region         = "us-west-2"
dynamodb_table = "terraform-locks"
```

### 3. Deploy Infrastructure

```bash
cd terraform

# Initialize with backend configuration
terraform init -backend-config=backend.conf

# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply
```

### 4. Build and Deploy Docker Container

```bash
# Build with correct architecture for ECS Fargate
docker build --platform linux/amd64 -f docker/terraform-runner/Dockerfile -t treza-dev-terraform-runner:latest .

# Tag and push to ECR
docker tag treza-dev-terraform-runner:latest YOUR_ECR_REPO:latest
docker push YOUR_ECR_REPO:latest
```

## 📁 Repository Structure

```
treza-terraform/
├── terraform/              # Main Terraform configuration
├── modules/                 # Reusable Terraform modules
│   ├── networking/         # 🆕 Enhanced VPC with shared security groups
│   ├── iam/               # IAM roles and policies
│   ├── dynamodb/          # DynamoDB streams configuration
│   ├── lambda/            # Lambda function definitions
│   ├── ecs/               # 🆕 ECS with shared security group support
│   ├── step-functions/    # 🆕 Separate deployment and cleanup workflows
│   ├── monitoring/        # CloudWatch dashboards and alarms
│   └── state-backend/     # Terraform state management
├── lambda/                 # Lambda function source code
│   ├── enclave_trigger/   # DynamoDB stream processor
│   ├── validation/        # Configuration validator
│   └── error_handler/     # Error processor
├── docker/                # Docker containers and scripts
│   ├── terraform-runner/  # 🆕 Optimized containerized Terraform runner
│   │   ├── terraform-configs/ # Enclave deployment configurations
│   │   │   ├── main.tf              # Uses shared security groups
│   │   │   ├── user_data_bootstrap.sh # 🆕 Compact bootstrap script
│   │   │   └── variables.tf         # Enhanced with security group vars
│   │   └── scripts/       # Enhanced build and deployment scripts
│   └── scripts/          # Build and deployment scripts
├── tests/                 # Testing framework

└── README.md             # This file
```

## 🔧 Configuration

### Required Variables

Create a `terraform/terraform.tfvars` file with:

```hcl
# Core Configuration
aws_region    = "us-west-2"
environment   = "dev"
project_name  = "treza"

# Existing DynamoDB table from treza-app
existing_dynamodb_table_name = "your-treza-enclaves-table"

# Networking
vpc_cidr           = "10.0.0.0/16"
availability_zones = ["us-west-2a", "us-west-2b"]

# ECS Configuration
terraform_runner_cpu    = 1024
terraform_runner_memory = 2048

# Timeouts (seconds)
deployment_timeout_seconds = 1800  # 30 minutes
destroy_timeout_seconds    = 1200  # 20 minutes
```

### Optional Configuration

```hcl
# Additional tags
additional_tags = {
  Team        = "infrastructure"
  CostCenter  = "engineering"
}

# Monitoring
log_retention_days = 30
```

## 🧪 Testing

### Local Testing

```bash
# Validate Terraform configuration
cd terraform
terraform validate

# Test Docker container locally with correct architecture
docker build --platform linux/amd64 -f docker/terraform-runner/Dockerfile -t test-runner .

# Run unit tests
make test

# Run integration tests (requires AWS credentials)
make test-integration ENV=dev

# Run all tests
make test-all ENV=dev
```

### Integration Testing

Our comprehensive integration test suite validates:
- ✅ VPC infrastructure (subnets, NAT gateways, endpoints)
- ✅ ECS clusters and task definitions
- ✅ Lambda functions (trigger, validation, error handler)
- ✅ Step Functions (deployment and cleanup workflows)
- ✅ CloudWatch monitoring and logging
- ✅ IAM roles and policies
- ✅ Security groups and network configuration
- ✅ DynamoDB tables

```bash
# Run integration tests
make test-integration ENV=dev

# Run specific test class
cd tests
pytest integration/test_infrastructure.py::TestVPCInfrastructure -v

# Run with detailed output
pytest integration/ -v --tb=short
```

### Cost Monitoring

Monitor and alert on infrastructure costs:

```bash
# Check costs for environment
make cost-alert ENV=dev

# Check all environments
./scripts/cost-alert.sh -e all

# Set custom threshold
./scripts/cost-alert.sh -e prod -t 1000

# With Slack notifications
./scripts/cost-alert.sh -e all --slack-webhook YOUR_WEBHOOK_URL

# Dry run (no alerts)
./scripts/cost-alert.sh -e dev --dry-run
```

### Automated Testing

Scheduled workflows run automatically:
- **Daily integration tests** (6 AM UTC)
- **Cost monitoring** (daily)
- **Health checks** (daily)
- **Auto-creates issues** on failures

## 📊 Monitoring & Logging

The infrastructure includes comprehensive monitoring and advanced log viewing capabilities:

- **CloudWatch Dashboard**: Real-time metrics for Step Functions and ECS
- **Alarms**: Automatic alerts for failures and performance issues
- **Log Insights**: Structured queries for troubleshooting
- **🆕 Application Log Monitoring**: Automatic CloudWatch Logs setup for all enclaves
- **🆕 Status Tracking**: Clear status progression through deployment and cleanup
- **🆕 Advanced Log Viewer**: Enhanced log viewing with filtering, real-time following, and export

Access the dashboard at: `https://console.aws.amazon.com/cloudwatch/home?region=us-west-2#dashboards:`

### Enhanced Log Viewing

The enhanced `view-logs.sh` script provides powerful log viewing capabilities:

```bash
# Interactive menu (easiest way)
./scripts/view-logs.sh dev

# Follow logs in real-time (like tail -f)
./scripts/view-logs.sh dev lambda-trigger --follow
./scripts/view-logs.sh prod ecs-runner -f

# Filter logs by pattern
./scripts/view-logs.sh dev all --filter ERROR
./scripts/view-logs.sh prod lambda-error --filter "stack trace"

# Custom time ranges
./scripts/view-logs.sh dev ecs-runner --since 30m
./scripts/view-logs.sh prod all --since 2h

# Export logs to file
./scripts/view-logs.sh dev all --export dev-logs-$(date +%Y%m%d).txt
./scripts/view-logs.sh prod lambda-trigger --since 1d --export prod-trigger.log

# Combine options
./scripts/view-logs.sh dev ecs-runner --since 1h --filter ERROR --lines 100
```

**Features**:
- 📡 **Real-time following**: Stream logs as they appear
- 🔍 **Advanced filtering**: Search for specific patterns or error messages
- ⏰ **Time range selection**: View logs from specific time periods (30m, 1h, 2d, etc.)
- 💾 **Log export**: Save logs to files for analysis or archiving
- 🎛️ **Interactive mode**: Easy-to-use menu with configurable options
- 🎨 **Color-coded output**: Clear visual distinction for different log types

## 🔒 Security

**See [SECURITY.md](SECURITY.md) for our complete security policy and vulnerability reporting process.**

### 🆕 Enhanced IAM Principles

- **Least Privilege**: Each component has minimal required permissions
- **Resource Isolation**: Terraform runners operate in isolated environments
- **Audit Trail**: All actions logged to CloudWatch
- **🆕 Shared Security Groups**: Centralized security management
- **🆕 VPC Endpoint Security**: Automatic secure access to AWS services
- **🆕 Automated Dependency Updates**: Dependabot monitors for vulnerabilities
- **🆕 Security Scanning**: Continuous tfsec and Checkov analysis

### 🆕 Network Security Improvements

- **Private Subnets**: Terraform runners isolated from internet
- **🆕 VPC Endpoints**: Comprehensive endpoints for S3, DynamoDB, ECR, CloudWatch, SSM
- **🆕 Shared Security Groups**: Consistent security policies across all enclaves
- **🆕 Automated Access**: No manual security group management required

## 🗑️ Infrastructure Teardown

The enhanced destroy script provides safe infrastructure destruction with comprehensive visibility:

```bash
# Preview what would be destroyed (recommended first step)
./scripts/destroy.sh dev --dry-run

# See resource inventory and cost savings
# No actual changes are made

# Actually destroy infrastructure
./scripts/destroy.sh dev
```

### Destroy Script Features:

- **🔍 Dry-Run Mode**: Preview destruction without making changes
- **📊 Resource Inventory**: See exactly what will be destroyed
- **💰 Cost Savings**: Estimated monthly savings after destruction
- **🔒 Safety Confirmations**: Multi-step confirmation for production
- **📋 Detailed Summary**: Resource breakdown by type
- **⚠️ Extra Protection**: Production requires additional confirmation

### Before Destroying:

1. **Backup Critical Data**: Export any important configurations
2. **Review Resources**: Use dry-run to see what will be destroyed
3. **Confirm Environment**: Double-check you're targeting the right environment
4. **Consider Costs**: Review estimated savings vs. rebuild time

## 📚 Documentation

### Core Documentation
- **[README.md](README.md)** - Main documentation (you are here)
- **[QUICK_REFERENCE.md](docs/QUICK_REFERENCE.md)** - ⚡ Quick commands and cheat sheet
- **[ARCHITECTURE.md](docs/ARCHITECTURE.md)** - 📐 Detailed architecture diagrams
- **[FAQ.md](docs/FAQ.md)** - ❓ Frequently Asked Questions (50+ Q&As)
- **[TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)** - 🔧 Comprehensive troubleshooting guide

### Project Governance
- **[CONTRIBUTING.md](CONTRIBUTING.md)** - 🤝 Contribution guidelines
- **[SECURITY.md](SECURITY.md)** - 🔒 Security policy and vulnerability reporting
- **[CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)** - 💜 Community standards
- **[CHANGELOG.md](CHANGELOG.md)** - 📝 Version history and release notes

### Practical Guides
- **[Examples](examples/)** - 🚀 Ready-to-deploy configurations
  - [Basic Setup](examples/basic-setup/) - Development (~$50/month)
  - [Production Ready](examples/production-ready/) - High availability (~$200-300/month)
  - [Multi-Environment](examples/multi-environment/) - Complete workflow (~$500/month)

## 🚨 Troubleshooting

For detailed troubleshooting, see our **[Troubleshooting Guide](docs/TROUBLESHOOTING.md)** and **[FAQ](docs/FAQ.md)**.

### 🆕 Common Issues and Solutions

1. **🆕 Application Logs Not Appearing**
   ```bash
   # Check if enclave is using shared security group
   aws ec2 describe-instances --filters "Name=tag:Name,Values=*enclave*" \
     --query 'Reservations[].Instances[].SecurityGroups'
   
   # Verify VPC endpoint security group rules
   aws ec2 describe-security-groups --group-ids sg-ENDPOINT_SG_ID
   ```

2. **🆕 User Data Size Limit Exceeded**
   ```bash
   # Check user_data_bootstrap.sh size
   wc -c docker/terraform-runner/terraform-configs/user_data_bootstrap.sh
   # Should be < 16KB when base64 encoded
   ```

3. **🆕 Docker Architecture Mismatch**
   ```bash
   # Always build for linux/amd64 for ECS Fargate
   docker build --platform linux/amd64 -f docker/terraform-runner/Dockerfile .
   ```

4. **🆕 Wrong Step Function for Termination**
   ```bash
   # Verify cleanup Step Function definition
   aws stepfunctions describe-state-machine \
     --state-machine-arn "arn:aws:states:REGION:ACCOUNT:stateMachine:treza-dev-cleanup" \
     --query 'definition' | jq '.Comment'
   # Should show "Treza Enclave Cleanup Workflow"
   ```

5. **Terraform Plugin Timeout**
   ```bash
   # Clear and reinitialize
   rm -rf .terraform .terraform.lock.hcl
   terraform init
   ```

6. **Lambda Function Build Errors**
   ```bash
   # Check lambda source directories exist
   ls -la lambda/*/
   ```

7. **ECS Task Failures**
   ```bash
   # Check CloudWatch logs
   aws logs describe-log-groups --log-group-name-prefix "/ecs/treza"
   ```

### Debug Mode

Enable debug logging by setting:
```bash
export TF_LOG=DEBUG
export AWS_CLI_DEBUG=1
```

## 🔄 CI/CD

### GitHub Actions

The repository includes comprehensive GitHub Actions workflows for:

- **Terraform CI/CD** (`terraform-ci.yml`):
  - Terraform format checking and validation
  - Module validation across all modules
  - Security scanning with tfsec and Checkov
  - Code linting with TFLint and ShellCheck
  - Docker architecture validation (linux/amd64)
  - Python unit tests
  - Documentation completeness checks
  - Automated CI summary in PR comments

- **Dependency Review** (`dependency-review.yml`):
  - Automated dependency vulnerability scanning on PRs
  - Security severity checks
  - PR comment summaries

- **Release Automation** (`release.yml`):
  - Automatic GitHub releases on version tags
  - Changelog extraction and formatting
  - Release notes generation

- **Terraform Documentation** (`terraform-docs.yml`):
  - Auto-generate documentation for modules
  - Keep README.md in sync with code changes
  - Automatic PR updates

- **Cost Estimation** (`cost-estimation.yml`):
  - Infrastructure cost analysis on PRs
  - Resource change impact assessment
  - Cost optimization recommendations

- **Version Management** (`auto-tag.yml`, `validate-version.yml`):
  - Automated version tagging from CHANGELOG
  - Version format validation on PRs
  - Manual version tagging via workflow dispatch

All workflows run automatically on push and pull requests to ensure code quality, security, and cost awareness.

### Manual Deployment

For manual deployments:

```bash
# Using scripts directly
./scripts/deploy.sh staging
./scripts/deploy.sh production

# Using Make commands (recommended)
make deploy ENV=staging
make deploy ENV=prod

# 🆕 Enhanced Make commands with comprehensive validation
make help                    # Show all available commands with categorized help
make init ENV=dev           # Initialize environment with validation
make plan ENV=dev           # Generate plan with environment-specific configs
make validate-all ENV=dev   # Run comprehensive validation checks
make pre-deploy ENV=prod    # Pre-deployment checks with production safeguards
make switch-env ENV=staging # Switch between environments seamlessly
make show-env               # Show current environment status
make validate-aws           # Validate AWS credentials and permissions
make validate-backend       # Test backend connectivity
make compare-backends       # Compare backend configurations across all environments
make validate-config        # Validate Terraform configuration
make fmt                    # Format Terraform files
make lint                   # Run linting tools
make security-scan          # Run security scans
make health-check ENV=dev   # Check infrastructure health
make clean                  # Clean temporary files

# 🆕 Additional utility scripts
./scripts/create-backend.sh dev --dry-run  # Preview backend creation (no changes)
./scripts/create-backend.sh prod           # Create backend infrastructure
./scripts/destroy.sh dev --dry-run         # Preview infrastructure destruction (safe)
./scripts/destroy.sh staging               # Destroy staging infrastructure
./scripts/health-check.sh dev              # Infrastructure health check
./scripts/switch-environment.sh staging    # Environment switching utility
./scripts/import-existing-resources.sh dev # Import existing AWS resources
./scripts/compare-backends.sh              # Compare backend configs across environments

# 🆕 New Developer Experience Features
make validate-all ENV=staging  # Comprehensive validation before deployment
make pre-deploy ENV=prod       # Production-safe deployment with confirmations
make switch-env ENV=dev        # Quick environment switching with validation
```

## 🔧 Architecture Deep Dive

### 🆕 Shared Security Group System

```mermaid
graph TB
    A[Enclave Request] --> B[Lambda Trigger]
    B --> C[Step Functions]
    C --> D[ECS Terraform Runner]
    D --> E[EC2 Instance]
    E --> F[Shared Security Group]
    F --> G[VPC Endpoints]
    G --> H[CloudWatch Logs]
    H --> I[Application Logs Visible]
```

### 🆕 Enhanced Step Functions Flow

```mermaid
graph LR
    A[PENDING_DEPLOY] --> B[Deployment SF]
    B --> C[DEPLOYING]
    C --> D[DEPLOYED]
    
    E[PENDING_DESTROY] --> F[Cleanup SF]
    F --> G[DESTROYING]
    G --> H[DESTROYED]
```

## 📚 Additional Resources

- [AWS Nitro Enclaves Documentation](https://docs.aws.amazon.com/enclaves/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest)
- [Step Functions Documentation](https://docs.aws.amazon.com/step-functions/)

## 🤝 Contributing

We welcome contributions! Please read:
- [Contributing Guidelines](CONTRIBUTING.md) - How to contribute
- [Code of Conduct](CODE_OF_CONDUCT.md) - Our community standards
- [Security Policy](SECURITY.md) - How to report vulnerabilities

### Quick Contribution Guide

1. **Fork** the repository
2. **Create** a feature branch (`git checkout -b feature/amazing-feature`)
3. **Make** your changes following our coding standards
4. **Test** your changes thoroughly
5. **Commit** using [Conventional Commits](https://www.conventionalcommits.org/) format
6. **Push** to your fork (`git push origin feature/amazing-feature`)
7. **Open** a Pull Request using our [PR template](.github/PULL_REQUEST_TEMPLATE.md)

### Development Setup

```bash
# Install development tools
make setup-dev

# Install pre-commit hooks
pre-commit install

# Run validation before committing
make validate-all ENV=dev
```

### 🆕 Development Guidelines

- Follow [CONTRIBUTING.md](CONTRIBUTING.md) guidelines
- Use [Conventional Commits](https://www.conventionalcommits.org/) for commit messages
- Always build Docker images with `--platform linux/amd64`
- Keep user_data scripts under 16KB when base64 encoded
- Use shared security group `sg-0766bf09d75f2eeff` for all enclaves
- Test both deployment and cleanup workflows
- Run pre-commit hooks before pushing
- Update CHANGELOG.md for notable changes

### Code Quality Tools

- **TFLint**: Terraform linting (`.tflint.hcl`)
- **Pre-commit**: Automated checks before commits
- **GitHub Actions**: CI/CD validation on every PR
- **Security Scanning**: tfsec and Checkov integration
- **Version Management**: Automated semantic versioning (`./scripts/version.sh`)

### Release Management

Create new releases easily:

```bash
# Check current version
./scripts/version.sh current

# Bump version (updates CHANGELOG.md)
./scripts/version.sh bump patch   # 2.0.0 -> 2.0.1
./scripts/version.sh bump minor   # 2.0.0 -> 2.1.0
./scripts/version.sh bump major   # 2.0.0 -> 3.0.0

# Commit changes and push
git add CHANGELOG.md
git commit -m "chore: prepare release v2.1.0"
git push

# Tag is created automatically via GitHub Actions
# Or manually create tag:
./scripts/version.sh tag
```

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

---

**Created**: December 2024  
**Status**: Production Ready  
**Version**: 2.0.0 - **Fully Automated Lifecycle Management**  
**CI/CD**: Automated with GitHub Actions  
**Changelog**: See [CHANGELOG.md](CHANGELOG.md) for version history