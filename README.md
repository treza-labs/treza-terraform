# Treza Terraform Infrastructure Repository

🏗️ **Infrastructure as Code for Treza Enclave Deployments**

This repository manages the AWS infrastructure for deploying Nitro Enclaves triggered by the [treza-app](../treza-app) through an event-driven architecture.

## 🚀 Quick Start

```bash
# Clone the repository
git clone <repository-url>
cd treza-terraform

# Initialize Terraform
cd terraform
terraform init

# Plan deployment
terraform plan

# Apply infrastructure
terraform apply
```

## 🏗️ Architecture Overview

```
DynamoDB Stream → Lambda Trigger → Step Functions → ECS Terraform Runner → AWS Nitro Enclave
                                      ↓
                              Update DynamoDB Status
```

### Key Components

- **DynamoDB Streams**: Event-driven triggers from treza-app enclave operations
- **Lambda Functions**: Process stream events and handle validation/preparation
- **Step Functions**: Orchestrate long-running deployment workflows
- **ECS Fargate**: Execute Terraform in containerized environment
- **Terraform Modules**: Reusable infrastructure components for Nitro Enclaves

## 📁 Repository Structure

```
treza-terraform/
├── terraform/          # Main Terraform configuration
├── modules/            # Reusable Terraform modules
├── lambda/             # Lambda function source code
├── step-functions/     # Step Functions definitions
├── docker/             # Container definitions and scripts
├── tests/              # Test suite
└── docs/               # Documentation
```

## 🔧 Prerequisites

- AWS CLI configured with appropriate permissions
- Terraform >= 1.6
- Docker (for local testing)
- Python 3.9+ (for Lambda functions)

## 📋 Deployment Process

1. **Automatic Triggers**: Enclave creation in treza-app triggers DynamoDB stream
2. **Validation**: Lambda validates configuration and checks prerequisites  
3. **Orchestration**: Step Functions manages the deployment workflow
4. **Execution**: ECS task runs Terraform to create AWS resources
5. **Status Update**: DynamoDB is updated with deployment results

## 🛠️ Development

See [docs/development.md](docs/development.md) for detailed development guidelines.

## 📊 Monitoring

Infrastructure deployment metrics are available in CloudWatch dashboards.

## 🔗 Related Repositories

- [treza-app](../treza-app) - Main application that triggers deployments

---

**Status**: 🟡 Under Development  
**Last Updated**: December 20, 2024