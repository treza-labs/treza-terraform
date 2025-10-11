# Treza Terraform Infrastructure Makefile
# Provides convenient commands for common operations

.PHONY: help init plan apply destroy validate fmt lint test clean setup-dev setup-prod

# Default environment
ENV ?= dev

# Colors for output
RED    := \033[31m
GREEN  := \033[32m
YELLOW := \033[33m
BLUE   := \033[34m
RESET  := \033[0m

help: ## Show this help message
	@echo "$(BLUE)Treza Terraform Infrastructure$(RESET)"
	@echo "Available commands:"
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*##/ {printf "  $(GREEN)%-15s$(RESET) %s\n", $$1, $$2}' $(MAKEFILE_LIST)

init: ## Initialize Terraform for specified environment
	@echo "$(BLUE)Initializing Terraform for $(ENV) environment...$(RESET)"
	./scripts/setup-environment.sh $(ENV)
	cd terraform && terraform init -backend-config=backend.conf

plan: ## Generate Terraform plan
	@echo "$(BLUE)Generating Terraform plan for $(ENV)...$(RESET)"
	cd terraform && terraform plan -out=tfplan

apply: ## Apply Terraform configuration
	@echo "$(BLUE)Applying Terraform configuration for $(ENV)...$(RESET)"
	cd terraform && terraform apply tfplan

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
	find . -name ".terraform" -type d -exec rm -rf {} + 2>/dev/null || true
	find . -name "*.tfplan" -delete 2>/dev/null || true
	find . -name "terraform.tfstate.backup" -delete 2>/dev/null || true

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

check-env: ## Check environment configuration
	@echo "$(BLUE)Checking $(ENV) environment configuration...$(RESET)"
	@if [ ! -f "terraform/environments/$(ENV).tfvars" ]; then \
		echo "$(RED)Environment file not found: terraform/environments/$(ENV).tfvars$(RESET)"; \
		exit 1; \
	fi
	@echo "$(GREEN)Environment $(ENV) configuration found$(RESET)"

health-check: ## Run infrastructure health check
	@echo "$(BLUE)Running health check for $(ENV) environment...$(RESET)"
	./scripts/health-check.sh $(ENV)

# Development shortcuts
dev-deploy: ENV=dev
dev-deploy: deploy ## Deploy to dev environment

staging-deploy: ENV=staging  
staging-deploy: deploy ## Deploy to staging environment

prod-deploy: ENV=prod
prod-deploy: deploy ## Deploy to prod environment
