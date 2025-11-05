# Security Policy

## 🔒 Security Commitment

The Treza Terraform Infrastructure project takes security seriously. We appreciate your efforts to responsibly disclose any security vulnerabilities you find.

## 📋 Supported Versions

We provide security updates for the following versions:

| Version | Supported          | Status |
| ------- | ------------------ | ------ |
| 2.x.x   | ✅ Yes             | Active Development |
| 1.x.x   | ⚠️ Limited Support | Security Fixes Only |
| < 1.0   | ❌ No              | End of Life |

## 🚨 Reporting a Vulnerability

**Please do NOT report security vulnerabilities through public GitHub issues.**

### Preferred Method: GitHub Security Advisories

1. Navigate to the [Security tab](https://github.com/treza-labs/treza-terraform/security/advisories)
2. Click "Report a vulnerability"
3. Fill out the vulnerability report form with:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if known)

### Alternative Method: Email

If you prefer email, send details to: **security@treza-labs.com**

Include:
- Type of vulnerability
- Full paths of source file(s) related to the vulnerability
- Location of the affected source code (tag/branch/commit)
- Step-by-step instructions to reproduce the issue
- Proof-of-concept or exploit code (if possible)
- Impact of the vulnerability

## ⏱️ Response Timeline

- **Initial Response**: Within 48 hours
- **Status Update**: Within 5 business days
- **Fix Timeline**: Depends on severity
  - Critical: 7 days
  - High: 14 days
  - Medium: 30 days
  - Low: 90 days

## 🎯 Scope

### In Scope

Security vulnerabilities in:
- Terraform configurations and modules
- IAM policies and permissions
- Lambda function code
- Docker container configurations
- CI/CD workflows
- Dependency vulnerabilities
- Security group configurations
- Encryption and secrets management
- Network security configurations

### Out of Scope

- Vulnerabilities in third-party dependencies (report to upstream)
- Social engineering attacks
- Physical security issues
- Denial of Service (DoS) attacks against AWS infrastructure
- Issues in unsupported versions

## 🏆 Security Best Practices

### For Contributors

When contributing code:

1. **Never Commit Secrets**
   - Use AWS Secrets Manager or Parameter Store
   - Run `git diff` before committing
   - Enable pre-commit hooks with `detect-secrets`

2. **Follow Least Privilege**
   - IAM policies should grant minimal required permissions
   - Use resource-specific ARNs, avoid wildcards
   - Document why each permission is needed

3. **Enable Encryption**
   - All data at rest must be encrypted
   - Use TLS/HTTPS for data in transit
   - Enable S3 bucket encryption
   - Use encrypted DynamoDB tables

4. **Validate Inputs**
   - Validate all Terraform variables
   - Sanitize Lambda function inputs
   - Use type constraints and validation rules

5. **Keep Dependencies Updated**
   - Review Dependabot PRs promptly
   - Test security updates in dev/staging first
   - Monitor for CVEs in dependencies

### For Deployers

When deploying infrastructure:

1. **Secure Backend**
   - Use S3 backend with versioning enabled
   - Enable S3 bucket encryption
   - Use DynamoDB state locking
   - Restrict bucket access with IAM policies

2. **Network Security**
   - Deploy in private subnets
   - Use VPC endpoints for AWS services
   - Restrict security group rules
   - Enable VPC Flow Logs

3. **Monitoring**
   - Enable CloudTrail logging
   - Set up CloudWatch alarms
   - Monitor for suspicious activities
   - Review logs regularly

4. **Access Control**
   - Use IAM roles, not access keys
   - Enable MFA for privileged accounts
   - Rotate credentials regularly
   - Use temporary credentials

5. **Secrets Management**
   - Never store secrets in tfvars files
   - Use AWS Secrets Manager
   - Enable automatic rotation
   - Audit secret access

## 🔍 Security Testing

### Automated Scans

Our CI/CD pipeline includes:
- **tfsec**: Terraform security scanning
- **Checkov**: Policy-as-code validation
- **detect-secrets**: Secret detection
- **TFLint**: Terraform linting with security rules
- **Dependabot**: Dependency vulnerability scanning

### Manual Reviews

Security-sensitive changes require:
- Code review by security team (@treza-labs/security)
- Testing in isolated environment
- Documentation of security implications

## 📚 Security Resources

### AWS Security Best Practices
- [AWS Security Best Practices](https://aws.amazon.com/architecture/security-identity-compliance/)
- [AWS Nitro Enclaves Security](https://docs.aws.amazon.com/enclaves/latest/user/security.html)
- [AWS Well-Architected Framework - Security Pillar](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/welcome.html)

### Terraform Security
- [Terraform Security Best Practices](https://developer.hashicorp.com/terraform/tutorials/configuration-language/sensitive-variables)
- [tfsec Documentation](https://aquasecurity.github.io/tfsec/)
- [Checkov Policies](https://www.checkov.io/5.Policy%20Index/terraform.html)

### Tools
- [detect-secrets](https://github.com/Yelp/detect-secrets)
- [git-secrets](https://github.com/awslabs/git-secrets)
- [AWS IAM Policy Simulator](https://policysim.aws.amazon.com/)

## 🛡️ Known Security Considerations

### Terraform State Files

⚠️ **Warning**: Terraform state files may contain sensitive information.

Mitigations:
- Use encrypted S3 backend
- Enable versioning for recovery
- Restrict access with IAM policies
- Never commit state files to git

### ECS Task Execution

Terraform runners execute in ECS with:
- Private subnet deployment
- VPC endpoints for AWS services
- IAM role with least privilege
- Network isolation from internet

### Lambda Functions

Lambda functions follow security best practices:
- Environment variables for configuration only
- Secrets fetched from AWS Secrets Manager
- Minimal IAM permissions
- VPC deployment where needed

### Nitro Enclaves

Enclaves are deployed with:
- Isolated compute environment
- Cryptographic attestation
- No persistent storage
- Network isolation

## 🔄 Security Updates

We announce security updates through:
- GitHub Security Advisories
- GitHub Releases with security tags
- CHANGELOG.md with security notes

Subscribe to repository notifications for security alerts.

## 📜 Compliance

This project implements controls aligned with:
- AWS Well-Architected Framework
- CIS AWS Foundations Benchmark
- NIST Cybersecurity Framework
- SOC 2 Type II controls (infrastructure design)

## 🤝 Security Acknowledgments

We appreciate security researchers who help us maintain a secure project. Acknowledged contributors will be listed here with permission.

### Hall of Fame

*No vulnerabilities reported yet. Be the first!*

## 📞 Contact

- **Security Issues**: Use GitHub Security Advisories or security@treza-labs.com
- **General Questions**: Open a [GitHub Discussion](https://github.com/treza-labs/treza-terraform/discussions)
- **Non-Security Bugs**: Open a [GitHub Issue](https://github.com/treza-labs/treza-terraform/issues)

---

**Last Updated**: November 2024  
**Version**: 1.0.0

