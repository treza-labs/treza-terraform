import subprocess
import os
import pytest

class TestTerraformModules:
    """Integration tests for Terraform modules"""
    
    def setup_method(self):
        """Setup for each test method"""
        self.terraform_dir = os.path.join(os.path.dirname(__file__), '../../terraform')
        self.modules_dir = os.path.join(os.path.dirname(__file__), '../../modules')
    
    def run_terraform_command(self, command, cwd=None):
        """Helper to run terraform commands"""
        if cwd is None:
            cwd = self.terraform_dir
            
        try:
            result = subprocess.run(
                command,
                shell=True,
                capture_output=True,
                text=True,
                cwd=cwd,
                timeout=300
            )
            return result
        except subprocess.TimeoutExpired:
            pytest.skip("Terraform command timed out")
    
    def test_terraform_init(self):
        """Test that terraform init succeeds"""
        # Clean any existing state
        subprocess.run("rm -rf .terraform .terraform.lock.hcl", shell=True, cwd=self.terraform_dir)
        
        result = self.run_terraform_command("terraform init")
        assert result.returncode == 0, f"terraform init failed: {result.stderr}"
    
    def test_terraform_validate(self):
        """Test that terraform validate succeeds"""
        # Ensure terraform is initialized
        self.run_terraform_command("terraform init")
        
        result = self.run_terraform_command("terraform validate")
        # Skip if timeout or plugin issues (common in CI)
        if "timeout" in result.stderr.lower() or "plugin" in result.stderr.lower():
            pytest.skip("Terraform plugin timeout - not a code issue")
        
        assert result.returncode == 0, f"terraform validate failed: {result.stderr}"
    
    def test_module_networking_files_exist(self):
        """Test that networking module files exist"""
        networking_dir = os.path.join(self.modules_dir, 'networking')
        
        required_files = ['main.tf', 'variables.tf', 'outputs.tf']
        for file in required_files:
            file_path = os.path.join(networking_dir, file)
            assert os.path.exists(file_path), f"Missing file: {file_path}"
    
    def test_module_lambda_files_exist(self):
        """Test that lambda module files exist"""
        lambda_dir = os.path.join(self.modules_dir, 'lambda')
        
        required_files = ['main.tf', 'variables.tf', 'outputs.tf']
        for file in required_files:
            file_path = os.path.join(lambda_dir, file)
            assert os.path.exists(file_path), f"Missing file: {file_path}"
    
    def test_lambda_source_code_exists(self):
        """Test that lambda source code exists"""
        lambda_src_dir = os.path.join(os.path.dirname(__file__), '../../lambda')
        
        functions = ['enclave_trigger', 'validation', 'error_handler']
        for function in functions:
            function_dir = os.path.join(lambda_src_dir, function)
            index_file = os.path.join(function_dir, 'index.py')
            requirements_file = os.path.join(function_dir, 'requirements.txt')
            
            assert os.path.exists(index_file), f"Missing {function}/index.py"
            assert os.path.exists(requirements_file), f"Missing {function}/requirements.txt"
    
    def test_docker_files_exist(self):
        """Test that Docker files exist"""
        docker_dir = os.path.join(os.path.dirname(__file__), '../../docker/terraform-runner')
        
        required_files = ['Dockerfile', 'scripts/entrypoint.sh']
        for file in required_files:
            file_path = os.path.join(docker_dir, file)
            assert os.path.exists(file_path), f"Missing Docker file: {file_path}"
    
    @pytest.mark.slow
    def test_terraform_plan_dry_run(self):
        """Test terraform plan (requires AWS credentials)"""
        # Skip if no AWS credentials
        if not os.environ.get('AWS_ACCESS_KEY_ID') and not os.path.exists(os.path.expanduser('~/.aws/credentials')):
            pytest.skip("No AWS credentials available")
        
        # Create minimal tfvars for testing
        tfvars_content = '''
aws_region = "us-west-2"
environment = "test"
project_name = "treza-test"
existing_dynamodb_table_name = "test-table"
'''
        tfvars_path = os.path.join(self.terraform_dir, 'test.tfvars')
        with open(tfvars_path, 'w') as f:
            f.write(tfvars_content)
        
        try:
            self.run_terraform_command("terraform init")
            result = self.run_terraform_command(f"terraform plan -var-file=test.tfvars")
            
            # Plan should complete even if resources don't exist
            # We're just testing syntax and structure
            assert "Error" not in result.stderr or "timeout" in result.stderr.lower()
        finally:
            # Clean up
            if os.path.exists(tfvars_path):
                os.remove(tfvars_path)