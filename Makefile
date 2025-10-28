# Treza Terraform Infrastructure Makefile
# Provides convenient commands for common operations

.PHONY: help init plan apply destroy validate fmt lint test clean setup-dev setup-prod validate-env validate-backend validate-config validate-all pre-deploy status logs

# Default environment
ENV ?= dev

# Colors for output
RED    := \033[31m
GREEN  := \033[32m
YELLOW := \033[33m
BLUE   := \033[34m
PURPLE := \033[35m
CYAN   := \033[36m
RESET  := \033[0m

# Configuration paths
TERRAFORM_DIR := terraform
ENV_FILE := $(TERRAFORM_DIR)/environments/$(ENV).tfvars
BACKEND_FILE := $(TERRAFORM_DIR)/environments/backend-$(ENV).conf
TFVARS_FILE := $(TERRAFORM_DIR)/terraform.tfvars
BACKEND_CONF := $(TERRAFORM_DIR)/backend.conf

help: ## Show this help message
	@echo "$(BLUE)Treza Terraform Infrastructure$(RESET)"
	@echo "Current environment: $(CYAN)$(ENV)$(RESET)"
	@echo ""
	@echo "$(PURPLE)Core Commands:$(RESET)"
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*##/ && !/validate-|pre-|dev-|staging-|prod-/ {printf "  $(GREEN)%-20s$(RESET) %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo ""
	@echo "$(PURPLE)Validation Commands:$(RESET)"
	@awk 'BEGIN {FS = ":.*##"} /^validate-.*:.*##/ {printf "  $(CYAN)%-20s$(RESET) %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo ""
	@echo "$(PURPLE)Environment Shortcuts:$(RESET)"
	@awk 'BEGIN {FS = ":.*##"} /^(dev-|staging-|prod-).*:.*##/ {printf "  $(YELLOW)%-20s$(RESET) %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo ""
	@echo "$(PURPLE)Usage Examples:$(RESET)"
	@echo "  make validate-all ENV=staging  # Validate staging environment"
	@echo "  make pre-deploy ENV=prod       # Pre-deployment checks for production"
	@echo "  make dev-deploy               # Quick deploy to dev environment"

init: validate-env validate-backend ## Initialize Terraform for specified environment
	@echo "$(BLUE)Initializing Terraform for $(ENV) environment...$(RESET)"
	@cp $(ENV_FILE) $(TFVARS_FILE)
	@cp $(BACKEND_FILE) $(BACKEND_CONF)
	@cd $(TERRAFORM_DIR) && terraform init -backend-config=backend.conf
	@echo "$(GREEN)✅ Terraform initialized for $(ENV) environment$(RESET)"

plan: init ## Generate Terraform plan
	@echo "$(BLUE)Generating Terraform plan for $(ENV)...$(RESET)"
	@cd $(TERRAFORM_DIR) && terraform plan -var-file=terraform.tfvars -out=tfplan-$(ENV)
	@echo "$(GREEN)✅ Plan generated: tfplan-$(ENV)$(RESET)"

apply: ## Apply Terraform configuration
	@echo "$(BLUE)Applying Terraform configuration for $(ENV)...$(RESET)"
	@if [ ! -f "$(TERRAFORM_DIR)/tfplan-$(ENV)" ]; then \
		echo "$(RED)❌ No plan file found. Run 'make plan ENV=$(ENV)' first$(RESET)"; \
		exit 1; \
	fi
	@cd $(TERRAFORM_DIR) && terraform apply tfplan-$(ENV)
	@echo "$(GREEN)✅ Infrastructure deployed successfully$(RESET)"

deploy: ## Full deployment (init + plan + apply)
	@echo "$(BLUE)Deploying to $(ENV) environment...$(RESET)"
	./scripts/deploy.sh $(ENV)

destroy: ## Destroy infrastructure
	@echo "$(RED)Destroying $(ENV) infrastructure...$(RESET)"
	./scripts/destroy.sh $(ENV)

validate: ## Validate Terraform configuration
	@echo "$(BLUE)Validating Terraform configuration...$(RESET)"
	cd terraform && terraform validate
	cd modules && find . -name "*.tf" -exec dirname {} \; | sort -u | xargs -I {} terraform -chdir={} validate

fmt: ## Format Terraform files
	@echo "$(BLUE)Formatting Terraform files...$(RESET)"
	terraform fmt -recursive .

lint: ## Run linting tools
	@echo "$(BLUE)Running linting tools...$(RESET)"
	@if command -v tflint >/dev/null 2>&1; then \
		tflint --recursive; \
	else \
		echo "$(YELLOW)tflint not installed, skipping...$(RESET)"; \
	fi
	@if command -v shellcheck >/dev/null 2>&1; then \
		find scripts -name "*.sh" -exec shellcheck {} \;; \
	else \
		echo "$(YELLOW)shellcheck not installed, skipping...$(RESET)"; \
	fi

test: ## Run tests
	@echo "$(BLUE)Running tests...$(RESET)"
	@if [ -f "tests/requirements.txt" ]; then \
		cd tests && python -m pytest -v; \
	else \
		echo "$(YELLOW)No tests found, skipping...$(RESET)"; \
	fi

build-lambda: ## Build Lambda functions
	@echo "$(BLUE)Building Lambda functions...$(RESET)"
	./modules/lambda/build-functions.sh

build-docker: ## Build Docker images
	@echo "$(BLUE)Building Docker images...$(RESET)"
	./docker/scripts/build-and-push.sh

clean: ## Clean temporary files
	@echo "$(BLUE)Cleaning temporary files...$(RESET)"
	@find . -name ".terraform" -type d -exec rm -rf {} + 2>/dev/null || true
	@find . -name "tfplan-*" -delete 2>/dev/null || true
	@find . -name "*.tfplan" -delete 2>/dev/null || true
	@find . -name "terraform.tfstate.backup" -delete 2>/dev/null || true
	@find . -name ".terraform.lock.hcl" -delete 2>/dev/null || true
	@rm -f $(TERRAFORM_DIR)/terraform.tfvars 2>/dev/null || true
	@rm -f $(TERRAFORM_DIR)/backend.conf 2>/dev/null || true
	@echo "$(GREEN)✅ Cleanup complete$(RESET)"

setup-dev: ## Setup development environment
	@echo "$(BLUE)Setting up development environment...$(RESET)"
	@if command -v pre-commit >/dev/null 2>&1; then \
		pre-commit install; \
		echo "$(GREEN)Pre-commit hooks installed$(RESET)"; \
	else \
		echo "$(YELLOW)pre-commit not installed. Install with: pip install pre-commit$(RESET)"; \
	fi

setup-prod: ## Setup production environment
	@echo "$(BLUE)Setting up production environment...$(RESET)"
	$(MAKE) ENV=prod init

docs: ## Generate documentation
	@echo "$(BLUE)Generating documentation...$(RESET)"
	@if command -v terraform-docs >/dev/null 2>&1; then \
		terraform-docs markdown table --output-file README.md .; \
		find modules -name "*.tf" -exec dirname {} \; | sort -u | xargs -I {} terraform-docs markdown table --output-file {}/README.md {}; \
	else \
		echo "$(YELLOW)terraform-docs not installed, skipping...$(RESET)"; \
	fi

security-scan: ## Run security scans
	@echo "$(BLUE)Running security scans...$(RESET)"
	@if command -v tfsec >/dev/null 2>&1; then \
		tfsec .; \
	else \
		echo "$(YELLOW)tfsec not installed, skipping...$(RESET)"; \
	fi
	@if command -v checkov >/dev/null 2>&1; then \
		checkov -d . --framework terraform; \
	else \
		echo "$(YELLOW)checkov not installed, skipping...$(RESET)"; \
	fi

check-env: validate-env ## Check environment configuration (alias for validate-env)
	@echo "$(GREEN)✅ Environment $(ENV) configuration validated$(RESET)"

health-check: ## Run infrastructure health check
	@echo "$(BLUE)Running health check for $(ENV) environment...$(RESET)"
	./scripts/health-check.sh $(ENV)

switch-env: ## Switch to specified environment (usage: make switch-env ENV=staging)
	@echo "$(BLUE)Switching to $(ENV) environment...$(RESET)"
	./scripts/switch-environment.sh $(ENV)

show-env: ## Show current environment status
	@echo "$(BLUE)Current environment status:$(RESET)"
	./scripts/switch-environment.sh status

logs: ## View logs from infrastructure components (interactive)
	@./scripts/view-logs.sh $(ENV)

status: ## Show comprehensive infrastructure status
	@echo "$(BLUE)═══════════════════════════════════════════════════════════$(RESET)"
	@echo "$(CYAN)       Treza Infrastructure Status Dashboard$(RESET)"
	@echo "$(BLUE)═══════════════════════════════════════════════════════════$(RESET)"
	@echo ""
	@echo "$(PURPLE)Environment Configuration:$(RESET)"
	@echo "  Target Environment: $(CYAN)$(ENV)$(RESET)"
	@if [ -f "$(TFVARS_FILE)" ]; then \
		echo "  Status: $(GREEN)✅ Configured$(RESET)"; \
		REGION=$$(grep '^aws_region' $(TFVARS_FILE) | cut -d'=' -f2 | tr -d ' "'); \
		PROJECT=$$(grep '^project_name' $(TFVARS_FILE) | cut -d'=' -f2 | tr -d ' "'); \
		if [ -n "$$REGION" ]; then echo "  Region: $$REGION"; fi; \
		if [ -n "$$PROJECT" ]; then echo "  Project: $$PROJECT"; fi; \
	else \
		echo "  Status: $(YELLOW)⚠️  Not initialized$(RESET)"; \
	fi
	@echo ""
	@echo "$(PURPLE)AWS Account:$(RESET)"
	@if aws sts get-caller-identity >/dev/null 2>&1; then \
		ACCOUNT_ID=$$(aws sts get-caller-identity --query Account --output text 2>/dev/null); \
		USER_ARN=$$(aws sts get-caller-identity --query Arn --output text 2>/dev/null); \
		REGION=$$(aws configure get region 2>/dev/null || echo "not set"); \
		echo "  Account ID: $$ACCOUNT_ID"; \
		echo "  Identity: $$USER_ARN"; \
		echo "  Default Region: $$REGION"; \
		echo "  Status: $(GREEN)✅ Authenticated$(RESET)"; \
	else \
		echo "  Status: $(RED)❌ Not authenticated$(RESET)"; \
	fi
	@echo ""
	@echo "$(PURPLE)Backend Configuration:$(RESET)"
	@if [ -f "$(BACKEND_CONF)" ]; then \
		BUCKET=$$(grep '^bucket' $(BACKEND_CONF) | cut -d'=' -f2 | tr -d ' "'); \
		REGION=$$(grep '^region' $(BACKEND_CONF) | cut -d'=' -f2 | tr -d ' "'); \
		TABLE=$$(grep '^dynamodb_table' $(BACKEND_CONF) | cut -d'=' -f2 | tr -d ' "'); \
		echo "  S3 Bucket: $$BUCKET"; \
		echo "  DynamoDB Table: $$TABLE"; \
		echo "  Region: $$REGION"; \
		if aws s3 ls "s3://$$BUCKET" --region "$$REGION" >/dev/null 2>&1; then \
			STATE_SIZE=$$(aws s3 ls "s3://$$BUCKET" --region "$$REGION" --recursive --summarize 2>/dev/null | grep "Total Size" | awk '{print $$3}'); \
			if [ -n "$$STATE_SIZE" ]; then \
				STATE_SIZE_MB=$$((STATE_SIZE / 1024 / 1024)); \
				echo "  State Size: $${STATE_SIZE_MB}MB"; \
			fi; \
			echo "  Status: $(GREEN)✅ Backend accessible$(RESET)"; \
		else \
			echo "  Status: $(RED)❌ Backend not accessible$(RESET)"; \
		fi; \
	else \
		echo "  Status: $(YELLOW)⚠️  Not configured$(RESET)"; \
	fi
	@echo ""
	@echo "$(PURPLE)Terraform State:$(RESET)"
	@if [ -d "$(TERRAFORM_DIR)/.terraform" ]; then \
		echo "  Initialization: $(GREEN)✅ Initialized$(RESET)"; \
		if [ -f "$(TERRAFORM_DIR)/.terraform/terraform.tfstate" ]; then \
			BACKEND_TYPE=$$(grep -o '"type":"[^"]*"' $(TERRAFORM_DIR)/.terraform/terraform.tfstate 2>/dev/null | cut -d'"' -f4); \
			if [ -n "$$BACKEND_TYPE" ]; then echo "  Backend Type: $$BACKEND_TYPE"; fi; \
		fi; \
		WORKSPACE=$$(cd $(TERRAFORM_DIR) && terraform workspace show 2>/dev/null || echo "default"); \
		if [ -n "$$WORKSPACE" ]; then echo "  Workspace: $$WORKSPACE"; fi; \
	else \
		echo "  Initialization: $(YELLOW)⚠️  Not initialized$(RESET)"; \
		echo "  Run: $(CYAN)make init ENV=$(ENV)$(RESET)"; \
	fi
	@echo ""
	@echo "$(PURPLE)Available Environments:$(RESET)"
	@for env in dev staging prod; do \
		if [ -f "$(TERRAFORM_DIR)/environments/$$env.tfvars" ]; then \
			if [ "$$env" = "$(ENV)" ]; then \
				echo "  $(GREEN)▶$(RESET) $$env (active)"; \
			else \
				echo "    $$env"; \
			fi; \
		fi; \
	done
	@echo ""
	@echo "$(PURPLE)Quick Commands:$(RESET)"
	@echo "  Initialize:     $(CYAN)make init ENV=$(ENV)$(RESET)"
	@echo "  Plan changes:   $(CYAN)make plan ENV=$(ENV)$(RESET)"
	@echo "  Deploy:         $(CYAN)make deploy ENV=$(ENV)$(RESET)"
	@echo "  Validate all:   $(CYAN)make validate-all ENV=$(ENV)$(RESET)"
	@echo ""
	@echo "$(BLUE)═══════════════════════════════════════════════════════════$(RESET)"

validate-env: ## Validate environment configuration exists
	@echo "$(BLUE)Validating $(ENV) environment configuration...$(RESET)"
	@if [ ! -f "$(ENV_FILE)" ]; then \
		echo "$(RED)❌ Environment file not found: $(ENV_FILE)$(RESET)"; \
		echo "$(YELLOW)Available environments:$(RESET)"; \
		ls -1 $(TERRAFORM_DIR)/environments/*.tfvars 2>/dev/null | sed 's/.*environments\//  - /' | sed 's/\.tfvars//' || echo "  No environment files found"; \
		exit 1; \
	fi
	@echo "$(GREEN)✅ Environment file found: $(ENV_FILE)$(RESET)"

validate-backend: ## Validate backend configuration exists and is accessible
	@echo "$(BLUE)Validating backend configuration for $(ENV)...$(RESET)"
	@if [ ! -f "$(BACKEND_FILE)" ]; then \
		echo "$(RED)❌ Backend file not found: $(BACKEND_FILE)$(RESET)"; \
		echo "$(YELLOW)Available backend configs:$(RESET)"; \
		ls -1 $(TERRAFORM_DIR)/environments/backend-*.conf 2>/dev/null | sed 's/.*environments\//  - /' || echo "  No backend files found"; \
		exit 1; \
	fi
	@echo "$(GREEN)✅ Backend file found: $(BACKEND_FILE)$(RESET)"
	@echo "$(BLUE)Testing backend connectivity...$(RESET)"
	@BUCKET=$$(grep '^bucket' $(BACKEND_FILE) | cut -d'"' -f2 | tr -d ' '); \
	REGION=$$(grep '^region' $(BACKEND_FILE) | cut -d'"' -f2 | tr -d ' '); \
	TABLE=$$(grep '^dynamodb_table' $(BACKEND_FILE) | cut -d'"' -f2 | tr -d ' '); \
	if [ -z "$$BUCKET" ] || [ -z "$$REGION" ] || [ -z "$$TABLE" ]; then \
		echo "$(RED)❌ Invalid backend configuration format$(RESET)"; \
		exit 1; \
	fi; \
	if aws s3 ls "s3://$$BUCKET" --region "$$REGION" >/dev/null 2>&1; then \
		echo "$(GREEN)✅ S3 bucket accessible: $$BUCKET$(RESET)"; \
	else \
		echo "$(RED)❌ S3 bucket not accessible: $$BUCKET$(RESET)"; \
		exit 1; \
	fi; \
	if aws dynamodb describe-table --table-name "$$TABLE" --region "$$REGION" >/dev/null 2>&1; then \
		echo "$(GREEN)✅ DynamoDB table accessible: $$TABLE$(RESET)"; \
	else \
		echo "$(RED)❌ DynamoDB table not accessible: $$TABLE$(RESET)"; \
		exit 1; \
	fi

compare-backends: ## Compare backend configurations across all environments
	@echo "$(BLUE)Comparing backend configurations...$(RESET)"
	@./scripts/compare-backends.sh

validate-config: ## Validate Terraform configuration files
	@echo "$(BLUE)Validating Terraform configuration...$(RESET)"
	@cd $(TERRAFORM_DIR) && terraform fmt -check=true -diff=true
	@cd $(TERRAFORM_DIR) && terraform validate
	@echo "$(GREEN)✅ Terraform configuration is valid$(RESET)"
	@echo "$(BLUE)Checking for required variables...$(RESET)"
	@if [ -f "$(ENV_FILE)" ]; then \
		MISSING_VARS=""; \
		for var in aws_region environment project_name existing_dynamodb_table_name vpc_cidr availability_zones; do \
			if ! grep -q "^$$var" $(ENV_FILE); then \
				MISSING_VARS="$$MISSING_VARS $$var"; \
			fi; \
		done; \
		if [ -n "$$MISSING_VARS" ]; then \
			echo "$(RED)❌ Missing required variables:$$MISSING_VARS$(RESET)"; \
			exit 1; \
		else \
			echo "$(GREEN)✅ All required variables present$(RESET)"; \
		fi; \
	fi

validate-aws: ## Validate AWS credentials and permissions
	@echo "$(BLUE)Validating AWS credentials and permissions...$(RESET)"
	@if ! aws sts get-caller-identity >/dev/null 2>&1; then \
		echo "$(RED)❌ AWS credentials not configured or invalid$(RESET)"; \
		exit 1; \
	fi
	@ACCOUNT_ID=$$(aws sts get-caller-identity --query Account --output text); \
	USER_ARN=$$(aws sts get-caller-identity --query Arn --output text); \
	echo "$(GREEN)✅ AWS credentials valid$(RESET)"; \
	echo "  Account: $$ACCOUNT_ID"; \
	echo "  Identity: $$USER_ARN"
	@echo "$(BLUE)Checking required AWS permissions...$(RESET)"
	@REGION=$$(aws configure get region || echo "us-west-2"); \
	ERRORS=0; \
	for service in ec2 ecs lambda stepfunctions dynamodb s3 iam logs; do \
		case $$service in \
			ec2) ACTION="ec2:DescribeVpcs" ;; \
			ecs) ACTION="ecs:ListClusters" ;; \
			lambda) ACTION="lambda:ListFunctions" ;; \
			stepfunctions) ACTION="states:ListStateMachines" ;; \
			dynamodb) ACTION="dynamodb:ListTables" ;; \
			s3) ACTION="s3:ListAllMyBuckets" ;; \
			iam) ACTION="iam:ListRoles" ;; \
			logs) ACTION="logs:DescribeLogGroups" ;; \
		esac; \
		if aws $$service $${ACTION#*:} --region $$REGION >/dev/null 2>&1; then \
			echo "$(GREEN)✅ $$service permissions OK$(RESET)"; \
		else \
			echo "$(RED)❌ $$service permissions missing$(RESET)"; \
			ERRORS=$$((ERRORS + 1)); \
		fi; \
	done; \
	if [ $$ERRORS -gt 0 ]; then \
		echo "$(RED)❌ $$ERRORS permission check(s) failed$(RESET)"; \
		exit 1; \
	fi

validate-all: validate-env validate-backend validate-aws validate-config ## Run all validation checks
	@echo "$(GREEN)🎉 All validations passed for $(ENV) environment!$(RESET)"

pre-deploy: validate-all ## Run comprehensive pre-deployment checks
	@echo "$(BLUE)Running pre-deployment checks for $(ENV)...$(RESET)"
	@if [ "$(ENV)" = "prod" ]; then \
		echo "$(YELLOW)⚠️  Production deployment detected!$(RESET)"; \
		echo "$(YELLOW)Please confirm the following:$(RESET)"; \
		echo "  1. All changes have been tested in staging"; \
		echo "  2. Deployment has been approved"; \
		echo "  3. Maintenance window is active (if required)"; \
		echo "  4. Rollback plan is prepared"; \
		read -p "Continue with production deployment? (yes/no): " confirm; \
		if [ "$$confirm" != "yes" ]; then \
			echo "$(YELLOW)Deployment cancelled$(RESET)"; \
			exit 1; \
		fi; \
	fi
	@echo "$(BLUE)Generating deployment plan...$(RESET)"
	@cd $(TERRAFORM_DIR) && terraform plan -var-file=../$(ENV_FILE) -out=tfplan-$(ENV)
	@echo "$(GREEN)✅ Pre-deployment checks complete$(RESET)"
	@echo "$(BLUE)Ready to deploy with: make apply ENV=$(ENV)$(RESET)"

# Development shortcuts
dev-deploy: ENV=dev
dev-deploy: deploy ## Deploy to dev environment

staging-deploy: ENV=staging  
staging-deploy: deploy ## Deploy to staging environment

prod-deploy: ENV=prod
prod-deploy: deploy ## Deploy to prod environment
