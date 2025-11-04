# Contributing to Treza Terraform Infrastructure

Thank you for your interest in contributing to the Treza Terraform Infrastructure project! This document provides guidelines and best practices for contributing.

## 📋 Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Workflow](#development-workflow)
- [Coding Standards](#coding-standards)
- [Testing Requirements](#testing-requirements)
- [Pull Request Process](#pull-request-process)
- [Commit Message Guidelines](#commit-message-guidelines)
- [Security](#security)

## Code of Conduct

This project adheres to a code of conduct that all contributors are expected to follow:

- Be respectful and inclusive
- Welcome newcomers and help them get started
- Focus on what is best for the community
- Show empathy towards other community members

## Getting Started

### Prerequisites

Before contributing, ensure you have:

- AWS CLI configured with appropriate permissions
- Terraform >= 1.6.0
- Docker (for building containers)
- Python 3.10+ (for Lambda functions and tests)
- Make (for convenience commands)

### Development Setup

1. **Fork and Clone**
   ```bash
   git clone https://github.com/YOUR_USERNAME/treza-terraform.git
   cd treza-terraform
   ```

2. **Install Development Tools**
   ```bash
   # macOS
   brew install tflint tfsec checkov shellcheck terraform-docs
   
   # Ubuntu
   apt-get install shellcheck
   
   # Python tools
   pip install pre-commit pytest
   ```

3. **Setup Pre-commit Hooks**
   ```bash
   make setup-dev
   ```

4. **Create a Feature Branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

## Development Workflow

### 1. Make Your Changes

- Follow the [coding standards](#coding-standards) below
- Keep changes focused and atomic
- Write clear, self-documenting code
- Add comments for complex logic

### 2. Test Your Changes

```bash
# Validate Terraform
make validate-all ENV=dev

# Run linting
make lint

# Run security scans
make security-scan

# Run tests
make test

# Test specific environment
make plan ENV=dev
```

### 3. Update Documentation

- Update README.md if adding new features
- Update CHANGELOG.md following [Keep a Changelog](https://keepachangelog.com/)
- Add/update module documentation
- Include inline comments for complex logic

### 4. Commit Your Changes

Follow our [commit message guidelines](#commit-message-guidelines):

```bash
git add .
git commit -m "feat: add new security group module"
```

### 5. Push and Create PR

```bash
git push origin feature/your-feature-name
```

Then create a Pull Request using our [PR template](.github/PULL_REQUEST_TEMPLATE.md).

## Coding Standards

### Terraform

- **Formatting**: Run `terraform fmt -recursive` before committing
- **Naming**: Use lowercase with underscores (snake_case)
- **Variables**: Always include description and type
- **Outputs**: Document what each output represents
- **Modules**: Keep modules focused and reusable

**Example:**
```hcl
variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}
```

### Python (Lambda Functions)

- Follow PEP 8 style guidelines
- Use type hints where possible
- Keep functions small and focused
- Include docstrings for all functions
- Handle errors gracefully

**Example:**
```python
def validate_enclave_config(config: dict) -> tuple[bool, str]:
    """
    Validate enclave configuration.
    
    Args:
        config: Configuration dictionary to validate
        
    Returns:
        Tuple of (is_valid, error_message)
    """
    if not config.get('instance_type'):
        return False, "instance_type is required"
    return True, ""
```

### Shell Scripts

- Use bash shebang: `#!/bin/bash`
- Enable strict mode: `set -euo pipefail`
- Quote variables: `"${var}"`
- Check command availability before use
- Provide helpful error messages

**Example:**
```bash
#!/bin/bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

main() {
    if ! command -v terraform &> /dev/null; then
        echo "Error: terraform is not installed"
        exit 1
    fi
    # ... rest of script
}

main "$@"
```

### Documentation

- Use clear, concise language
- Include code examples
- Add diagrams for complex workflows
- Keep README.md up to date
- Document breaking changes clearly

## Testing Requirements

All contributions must include appropriate tests:

### Terraform Testing

1. **Validation**
   ```bash
   terraform validate
   ```

2. **Formatting**
   ```bash
   terraform fmt -check -recursive
   ```

3. **Static Analysis**
   ```bash
   tflint --recursive
   tfsec .
   checkov -d .
   ```

### Python Testing

1. **Unit Tests**
   ```bash
   cd tests
   pytest unit/ -v
   ```

2. **Coverage** (aim for >80%)
   ```bash
   pytest --cov=lambda --cov-report=html
   ```

### Integration Testing

Test in a non-production environment before submitting:

```bash
# Deploy to dev environment
make deploy ENV=dev

# Run health checks
make health-check ENV=dev

# View logs
./scripts/view-logs.sh dev
```

## Pull Request Process

### PR Checklist

Before submitting a PR, ensure:

- [ ] Code follows project style guidelines
- [ ] All tests pass locally
- [ ] Documentation is updated
- [ ] CHANGELOG.md is updated
- [ ] Commits follow commit message guidelines
- [ ] PR description is complete and clear
- [ ] No secrets or sensitive data are included
- [ ] Breaking changes are clearly documented

### Review Process

1. **Automated Checks**: CI/CD workflows must pass
2. **Code Review**: At least one maintainer approval required
3. **Testing**: Changes tested in dev/staging environment
4. **Documentation**: All changes properly documented

### After Approval

- Squash commits if requested
- Ensure CI/CD passes
- Maintainer will merge when ready

## Commit Message Guidelines

We follow [Conventional Commits](https://www.conventionalcommits.org/):

### Format

```
<type>(<scope>): <subject>

<body>

<footer>
```

### Types

- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Formatting, missing semicolons, etc.
- `refactor`: Code restructuring without functional changes
- `test`: Adding or updating tests
- `chore`: Maintenance tasks
- `perf`: Performance improvements
- `ci`: CI/CD changes
- `build`: Build system changes

### Examples

```bash
# Feature
git commit -m "feat(networking): add VPC endpoint for S3"

# Bug fix
git commit -m "fix(lambda): handle missing environment variable"

# Breaking change
git commit -m "feat(ecs)!: change task definition structure

BREAKING CHANGE: ECS task definitions now require new cpu_units parameter"

# Multiple types
git commit -m "feat(monitoring): add CloudWatch dashboard
- Add dashboard with key metrics
- Include alarm widgets
- Add log insights queries"
```

### Scope

Common scopes:
- `networking`: VPC, security groups, endpoints
- `iam`: Roles, policies, permissions
- `lambda`: Lambda functions
- `ecs`: ECS and Fargate
- `monitoring`: CloudWatch, alarms
- `ci`: CI/CD workflows
- `docs`: Documentation
- `scripts`: Helper scripts

## Security

### Reporting Security Issues

**Do not open public issues for security vulnerabilities.**

Instead:
1. Go to the [Security tab](https://github.com/treza-labs/treza-terraform/security)
2. Click "Report a vulnerability"
3. Provide detailed information about the vulnerability

### Security Guidelines

- Never commit secrets, keys, or credentials
- Use AWS Secrets Manager or Parameter Store for secrets
- Follow least privilege principle for IAM
- Enable encryption at rest and in transit
- Scan for vulnerabilities regularly
- Keep dependencies updated

### Sensitive Data

Before committing:
- Run `git diff` to review changes
- Check for AWS account IDs, ARNs, IPs
- Remove test data with real information
- Use placeholder values in examples

## Project Structure

```
treza-terraform/
├── terraform/           # Main configuration
│   └── environments/   # Environment-specific configs
├── modules/            # Reusable modules
├── lambda/             # Lambda function code
├── docker/             # Docker configurations
├── scripts/            # Utility scripts
└── tests/              # Test suites
```

### Adding New Modules

When creating a new module:

1. Create module directory under `modules/`
2. Include: `main.tf`, `variables.tf`, `outputs.tf`, `README.md`
3. Add validation for inputs
4. Document all variables and outputs
5. Include usage examples
6. Add tests

## Communication

- **Issues**: Use GitHub Issues for bugs and features
- **Discussions**: Use GitHub Discussions for questions
- **PRs**: Use Pull Requests for code contributions
- **Security**: Use private security advisories

## Recognition

Contributors will be recognized in:
- CHANGELOG.md for significant contributions
- GitHub contributors page
- Project documentation

## Questions?

If you have questions about contributing:
1. Check existing documentation
2. Search closed issues and PRs
3. Ask in GitHub Discussions
4. Open a new issue with the question label

## License

By contributing, you agree that your contributions will be licensed under the same license as the project (MIT License).

---

Thank you for contributing to Treza Terraform Infrastructure! 🎉

