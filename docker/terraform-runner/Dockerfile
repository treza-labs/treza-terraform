# Use Amazon Linux 2 as base image to match ECS environment
FROM amazonlinux:2023

# Set environment variables
ENV TERRAFORM_VERSION=1.6.6
ENV AWS_CLI_VERSION=2.15.0

# Install system dependencies
RUN yum update -y && \
    yum install -y \
        curl \
        unzip \
        git \
        wget \
        python3 \
        python3-pip \
        jq \
        which \
        tar \
        gzip && \
    yum clean all

# Install Terraform
RUN curl -fsSL https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip -o terraform.zip && \
    unzip terraform.zip && \
    mv terraform /usr/local/bin/ && \
    rm terraform.zip && \
    terraform version

# Install AWS CLI v2
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64-${AWS_CLI_VERSION}.zip" -o "awscliv2.zip" && \
    unzip awscliv2.zip && \
    ./aws/install && \
    rm -rf aws awscliv2.zip

# Create working directory
WORKDIR /terraform

# Copy terraform modules and configuration
COPY docker/terraform-runner/scripts/ /scripts/
COPY docker/terraform-runner/terraform-configs/ /terraform-configs/
COPY modules/ /modules/

# Make scripts executable
RUN chmod +x /scripts/*.sh

# Create terraform workspace directory
RUN mkdir -p /workspace

# Set entrypoint
ENTRYPOINT ["/scripts/entrypoint.sh"]