import pytest
import os
import sys

# Add lambda directories to Python path for testing
test_dir = os.path.dirname(__file__)
project_root = os.path.dirname(test_dir)

lambda_dirs = [
    os.path.join(project_root, 'lambda', 'enclave_trigger'),
    os.path.join(project_root, 'lambda', 'validation'),
    os.path.join(project_root, 'lambda', 'error_handler')
]

for lambda_dir in lambda_dirs:
    if os.path.exists(lambda_dir):
        sys.path.insert(0, lambda_dir)

@pytest.fixture(scope="session")
def aws_credentials():
    """Mock AWS credentials for testing"""
    os.environ['AWS_ACCESS_KEY_ID'] = 'testing'
    os.environ['AWS_SECRET_ACCESS_KEY'] = 'testing'
    os.environ['AWS_SECURITY_TOKEN'] = 'testing'
    os.environ['AWS_SESSION_TOKEN'] = 'testing'
    os.environ['AWS_DEFAULT_REGION'] = 'us-west-2'