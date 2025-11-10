# Architecture Documentation

This document provides detailed architecture diagrams and explanations for the Treza Terraform Infrastructure project.

## 📋 Table of Contents

- [High-Level Architecture](#high-level-architecture)
- [Component Architecture](#component-architecture)
- [Network Architecture](#network-architecture)
- [Deployment Flow](#deployment-flow)
- [Security Architecture](#security-architecture)
- [Data Flow](#data-flow)

## High-Level Architecture

```mermaid
graph TB
    subgraph "Event Source"
        DB[DynamoDB Table<br/>Enclave Requests]
        STREAM[DynamoDB Stream]
    end
    
    subgraph "Event Processing"
        LAMBDA[Lambda Trigger<br/>Stream Processor]
        VALIDATE[Lambda Validation]
    end
    
    subgraph "Orchestration"
        SF_DEPLOY[Step Function<br/>Deployment Workflow]
        SF_CLEANUP[Step Function<br/>Cleanup Workflow]
    end
    
    subgraph "Execution"
        ECS[ECS Fargate<br/>Terraform Runner]
        TF[Terraform<br/>Enclave Deployment]
    end
    
    subgraph "AWS Services"
        EC2[EC2 Instance<br/>Nitro Enclave]
        CW[CloudWatch<br/>Logs & Metrics]
        SSM[Systems Manager<br/>Parameters]
    end
    
    DB -->|Stream| STREAM
    STREAM -->|Trigger| LAMBDA
    LAMBDA -->|Validate| VALIDATE
    VALIDATE -->|Start| SF_DEPLOY
    LAMBDA -->|Terminate| SF_CLEANUP
    
    SF_DEPLOY -->|Run Task| ECS
    SF_CLEANUP -->|Run Task| ECS
    ECS -->|Execute| TF
    TF -->|Deploy| EC2
    
    ECS -->|Write| CW
    EC2 -->|Logs| CW
    TF -->|Read| SSM
    
    style DB fill:#f9f,stroke:#333
    style EC2 fill:#9f9,stroke:#333
    style ECS fill:#99f,stroke:#333
    style SF_DEPLOY fill:#ff9,stroke:#333
    style SF_CLEANUP fill:#ff9,stroke:#333
```

### Key Components

1. **DynamoDB Stream** - Captures changes to enclave request table
2. **Lambda Trigger** - Processes stream events and routes to workflows
3. **Lambda Validation** - Validates enclave configurations
4. **Step Functions** - Orchestrates long-running workflows
5. **ECS Fargate** - Runs Terraform in isolated containers
6. **Terraform** - Deploys and manages enclave infrastructure
7. **EC2 Nitro Enclaves** - Secure compute environments

## Component Architecture

### Lambda Functions

```mermaid
graph LR
    subgraph "Lambda Layer"
        L1[Enclave Trigger]
        L2[Validation]
        L3[Error Handler]
        L4[Status Monitor]
    end
    
    subgraph "Shared Layer"
        LAYER[Common Libraries<br/>boto3, jsonschema]
    end
    
    subgraph "External Dependencies"
        DB[(DynamoDB)]
        SF[Step Functions]
        CW[CloudWatch]
    end
    
    L1 -.->|Uses| LAYER
    L2 -.->|Uses| LAYER
    L3 -.->|Uses| LAYER
    L4 -.->|Uses| LAYER
    
    L1 -->|Read/Write| DB
    L1 -->|Start| SF
    L2 -->|Validate| DB
    L3 -->|Log| CW
    L4 -->|Query| DB
    
    style LAYER fill:#e0e0e0,stroke:#333
```

### Step Functions Workflows

```mermaid
stateDiagram-v2
    [*] --> ValidateRequest
    
    ValidateRequest --> StartDeployment: Valid
    ValidateRequest --> HandleError: Invalid
    
    StartDeployment --> RunTerraform
    RunTerraform --> UpdateStatus
    UpdateStatus --> NotifySuccess
    NotifySuccess --> [*]
    
    RunTerraform --> HandleError: Failure
    HandleError --> UpdateStatus
    UpdateStatus --> [*]
```

## Network Architecture

```mermaid
graph TB
    subgraph "AWS Region"
        subgraph "VPC 10.0.0.0/16"
            subgraph "Public Subnets"
                NAT1[NAT Gateway<br/>AZ-1]
                NAT2[NAT Gateway<br/>AZ-2]
            end
            
            subgraph "Private Subnets"
                ECS1[ECS Tasks<br/>AZ-1]
                ECS2[ECS Tasks<br/>AZ-2]
                EC2_1[Enclaves<br/>AZ-1]
                EC2_2[Enclaves<br/>AZ-2]
            end
            
            subgraph "VPC Endpoints"
                EP_S3[S3 Endpoint]
                EP_DDB[DynamoDB Endpoint]
                EP_ECR[ECR Endpoint]
                EP_CW[CloudWatch Endpoint]
                EP_SSM[SSM Endpoint]
            end
            
            SG[Shared Security Group]
        end
    end
    
    IGW[Internet Gateway]
    
    NAT1 -->|Route| IGW
    NAT2 -->|Route| IGW
    
    ECS1 -->|Route| NAT1
    ECS2 -->|Route| NAT2
    
    ECS1 -.->|Private| EP_S3
    ECS1 -.->|Private| EP_ECR
    ECS1 -.->|Private| EP_CW
    
    EC2_1 -.->|Uses| SG
    EC2_2 -.->|Uses| SG
    
    SG -.->|Access| EP_CW
    SG -.->|Access| EP_SSM
    
    style SG fill:#f99,stroke:#333,stroke-width:3px
    style EP_S3 fill:#9f9,stroke:#333
    style EP_DDB fill:#9f9,stroke:#333
    style EP_ECR fill:#9f9,stroke:#333
    style EP_CW fill:#9f9,stroke:#333
    style EP_SSM fill:#9f9,stroke:#333
```

### Network Flow

1. **ECS Tasks** run in private subnets
2. **NAT Gateways** provide internet access for outbound traffic
3. **VPC Endpoints** enable private access to AWS services
4. **Shared Security Group** grants enclaves access to endpoints
5. **No direct internet** access for enclaves

## Deployment Flow

```mermaid
sequenceDiagram
    participant User
    participant DDB as DynamoDB
    participant Stream as DynamoDB Stream
    participant Lambda as Lambda Trigger
    participant SF as Step Functions
    participant ECS as ECS Fargate
    participant TF as Terraform
    participant AWS as AWS Resources
    
    User->>DDB: Insert enclave request
    DDB->>Stream: Stream event
    Stream->>Lambda: Trigger
    Lambda->>Lambda: Parse event
    Lambda->>SF: Start workflow
    
    SF->>ECS: Launch task
    ECS->>TF: Execute terraform apply
    TF->>AWS: Create enclave resources
    AWS-->>TF: Resources created
    TF-->>ECS: Success
    ECS-->>SF: Task complete
    SF->>DDB: Update status: DEPLOYED
    DDB-->>User: Status visible
```

### Deployment Steps

1. User inserts deployment request in DynamoDB
2. Stream triggers Lambda function
3. Lambda validates and starts Step Function
4. Step Function launches ECS Fargate task
5. ECS task runs Terraform apply
6. Terraform creates enclave infrastructure
7. Status updates flow back to DynamoDB
8. User sees deployment status

## Security Architecture

```mermaid
graph TB
    subgraph "IAM Roles & Policies"
        R1[Lambda Execution Role]
        R2[ECS Task Role]
        R3[ECS Execution Role]
        R4[Enclave IAM Role]
        
        P1[Lambda Policy<br/>Least Privilege]
        P2[ECS Policy<br/>Terraform Operations]
        P3[ECR Pull Policy]
        P4[Enclave Policy<br/>Limited Access]
    end
    
    subgraph "Network Security"
        SG1[ECS Security Group]
        SG2[Shared Enclave SG]
        NACL[Network ACLs]
    end
    
    subgraph "Data Security"
        KMS[KMS Encryption]
        SM[Secrets Manager]
        SSM[Parameter Store]
    end
    
    subgraph "Audit & Monitoring"
        CT[CloudTrail]
        CW[CloudWatch Logs]
        CFG[AWS Config]
    end
    
    R1 -.->|Attached| P1
    R2 -.->|Attached| P2
    R3 -.->|Attached| P3
    R4 -.->|Attached| P4
    
    SG1 -->|Controls| ECS
    SG2 -->|Controls| Enclave
    
    KMS -->|Encrypts| S3
    KMS -->|Encrypts| EBS
    SM -->|Stores| Secrets
    SSM -->|Stores| Config
    
    CT -->|Logs| API_Calls
    CW -->|Logs| Application
    CFG -->|Monitors| Compliance
    
    style KMS fill:#f99,stroke:#333,stroke-width:2px
    style SG2 fill:#f99,stroke:#333,stroke-width:2px
```

### Security Layers

1. **Identity & Access Management**
   - Least privilege IAM roles
   - Service-to-service authentication
   - No hardcoded credentials

2. **Network Security**
   - Private subnet deployment
   - Security group isolation
   - VPC endpoints for AWS services
   - No direct internet access

3. **Data Protection**
   - Encryption at rest (KMS)
   - Encryption in transit (TLS)
   - Secrets Manager for credentials
   - Parameter Store for configuration

4. **Audit & Compliance**
   - CloudTrail for API auditing
   - CloudWatch Logs for application logs
   - AWS Config for compliance monitoring
   - VPC Flow Logs for network traffic

## Data Flow

### Deployment Request Flow

```
┌─────────────────────────────────────────────────────────────┐
│                     Deployment Request                       │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    ┌──────────────────┐
                    │  DynamoDB Table  │
                    │  Status: PENDING │
                    └──────────────────┘
                              │
                              ▼ Stream Event
                    ┌──────────────────┐
                    │  Lambda Trigger  │
                    │  Parse & Route   │
                    └──────────────────┘
                              │
                    ┌─────────┴─────────┐
                    ▼                   ▼
          ┌──────────────────┐  ┌──────────────────┐
          │ Validation       │  │ Start Workflow   │
          │ Check Schema     │  │ Step Functions   │
          └──────────────────┘  └──────────────────┘
                    │                   │
                    └─────────┬─────────┘
                              ▼
                    ┌──────────────────┐
                    │   ECS Fargate    │
                    │ Status: DEPLOYING│
                    └──────────────────┘
                              │
                              ▼
                    ┌──────────────────┐
                    │    Terraform     │
                    │  Apply Changes   │
                    └──────────────────┘
                              │
                              ▼
                    ┌──────────────────┐
                    │ EC2 + Enclave    │
                    │ Status: DEPLOYED │
                    └──────────────────┘
                              │
                              ▼
                    ┌──────────────────┐
                    │  Update Status   │
                    │  in DynamoDB     │
                    └──────────────────┘
```

### Status Lifecycle

```mermaid
stateDiagram-v2
    [*] --> PENDING_DEPLOY: User Request
    
    PENDING_DEPLOY --> DEPLOYING: Workflow Started
    DEPLOYING --> DEPLOYED: Success
    DEPLOYING --> FAILED: Error
    
    DEPLOYED --> PENDING_DESTROY: Terminate Request
    PENDING_DESTROY --> DESTROYING: Cleanup Started
    DESTROYING --> DESTROYED: Success
    DESTROYING --> FAILED: Error
    
    FAILED --> PENDING_DEPLOY: Retry
    FAILED --> PENDING_DESTROY: Cleanup
    
    DESTROYED --> [*]
```

## Infrastructure as Code

### Terraform Module Structure

```
terraform/
├── main.tf                 # Root module
├── variables.tf           # Input variables
├── outputs.tf            # Output values
└── modules/
    ├── networking/       # VPC, subnets, endpoints
    ├── iam/             # IAM roles and policies
    ├── lambda/          # Lambda functions
    ├── ecs/             # ECS cluster and tasks
    ├── step-functions/  # Workflow definitions
    ├── monitoring/      # CloudWatch dashboards
    └── dynamodb/        # DynamoDB configuration
```

### Module Dependencies

```mermaid
graph TD
    ROOT[Root Module]
    
    NET[Networking Module]
    IAM[IAM Module]
    DDB[DynamoDB Module]
    LAMBDA[Lambda Module]
    ECS[ECS Module]
    SF[Step Functions Module]
    MON[Monitoring Module]
    
    ROOT -->|Creates| NET
    ROOT -->|Creates| IAM
    ROOT -->|Configures| DDB
    
    LAMBDA -->|Depends on| IAM
    LAMBDA -->|Depends on| NET
    LAMBDA -->|Depends on| DDB
    
    ECS -->|Depends on| NET
    ECS -->|Depends on| IAM
    
    SF -->|Depends on| IAM
    SF -->|Depends on| ECS
    SF -->|Depends on| LAMBDA
    
    MON -->|Monitors| LAMBDA
    MON -->|Monitors| ECS
    MON -->|Monitors| SF
    
    style ROOT fill:#9cf,stroke:#333,stroke-width:3px
```

## Scaling Architecture

### Horizontal Scaling

```mermaid
graph TB
    subgraph "Load Distribution"
        LB[Load Balancer<br/>Optional]
    end
    
    subgraph "Auto Scaling"
        ASG[ECS Service<br/>Auto Scaling]
        
        T1[Task 1]
        T2[Task 2]
        T3[Task 3]
        TN[Task N...]
    end
    
    subgraph "Backend"
        DDB[(DynamoDB<br/>On-Demand)]
        S3[(S3<br/>Unlimited)]
    end
    
    LB -->|Distribute| ASG
    ASG -->|Manages| T1
    ASG -->|Manages| T2
    ASG -->|Manages| T3
    ASG -->|Manages| TN
    
    T1 -->|Access| DDB
    T2 -->|Access| DDB
    T3 -->|Access| DDB
    TN -->|Access| DDB
    
    T1 -->|Store| S3
    T2 -->|Store| S3
    T3 -->|Store| S3
    TN -->|Store| S3
    
    style ASG fill:#ff9,stroke:#333,stroke-width:2px
```

### Performance Characteristics

| Component | Throughput | Latency | Scalability |
|-----------|-----------|---------|-------------|
| DynamoDB Stream | 1000 records/sec | < 1 second | Auto-scales |
| Lambda Trigger | 1000 concurrent | < 100ms | Auto-scales |
| Step Functions | 4000/sec | Varies | Auto-scales |
| ECS Fargate | 100s of tasks | Varies | Manual/Auto |
| Terraform | Sequential | 5-30 min | Parallel runs |

## Disaster Recovery

### Backup Strategy

```mermaid
graph LR
    subgraph "Primary Region"
        P_STATE[Terraform State<br/>S3 + Versioning]
        P_DDB[DynamoDB<br/>Point-in-Time]
        P_LOGS[CloudWatch Logs<br/>Exported]
    end
    
    subgraph "Backup Region"
        B_STATE[S3 Replica<br/>Cross-Region]
        B_DDB[DynamoDB Backup<br/>On-Demand]
        B_LOGS[S3 Archive<br/>Long-term]
    end
    
    P_STATE -->|Replicate| B_STATE
    P_DDB -->|Backup| B_DDB
    P_LOGS -->|Export| B_LOGS
    
    style P_STATE fill:#9f9,stroke:#333
    style B_STATE fill:#99f,stroke:#333
```

## Cost Architecture

### Cost Breakdown by Component

```
Monthly Cost Estimate (Development)

VPC & Networking        │████████████████░░░░░░░░ $35 (70%)
ECS Fargate             │██░░░░░░░░░░░░░░░░░░░░░░  $5 (10%)
Lambda Functions        │█░░░░░░░░░░░░░░░░░░░░░░░  $2 (4%)
CloudWatch              │█░░░░░░░░░░░░░░░░░░░░░░░  $3 (6%)
DynamoDB                │█░░░░░░░░░░░░░░░░░░░░░░░  $2 (4%)
Other Services          │█░░░░░░░░░░░░░░░░░░░░░░░  $3 (6%)
                        └─────────────────────────
                        Total: ~$50/month
```

### Cost Optimization Opportunities

1. **NAT Gateways** - Largest cost driver
   - Use single NAT for dev
   - Consider NAT instances
   - Use VPC endpoints

2. **ECS Fargate** - Usage-based
   - Right-size task resources
   - Spot pricing for non-critical
   - Optimize runtime

3. **CloudWatch Logs** - Storage-based
   - Shorter retention for dev
   - Export to S3
   - Filter before logging

## References

- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest)
- [AWS Nitro Enclaves](https://docs.aws.amazon.com/enclaves/)

---

**Last Updated**: November 2024  
**Version**: 2.0.0

