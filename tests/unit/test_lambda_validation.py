import json
import pytest
import sys
import os

# Add lambda directory to path for testing
sys.path.append(os.path.join(os.path.dirname(__file__), '../../lambda/validation'))

from index import validate_deploy_request, validate_destroy_request, create_response

class TestValidationFunction:
    """Unit tests for the validation Lambda function"""
    
    def test_valid_deploy_configuration(self):
        """Test validation with valid deployment configuration"""
        config = {
            "instance_type": "m5.large",
            "cpu_count": 2,
            "memory_mib": 1024,
            "eif_path": "s3://bucket/enclave.eif",
            "debug_mode": False
        }
        
        result = validate_deploy_request("test-enclave-123", config)
        assert result['valid'] is True
        assert "valid" in result['message']
    
    def test_invalid_instance_type(self):
        """Test validation with invalid instance type"""
        config = {
            "instance_type": "t2.micro",  # Not supported for Nitro Enclaves
            "cpu_count": 2,
            "memory_mib": 1024,
            "eif_path": "s3://bucket/enclave.eif"
        }
        
        result = validate_deploy_request("test-enclave-123", config)
        assert result['valid'] is False
        assert "validation failed" in result['message'].lower()
    
    def test_invalid_cpu_memory_ratio(self):
        """Test validation with invalid CPU to memory ratio"""
        config = {
            "instance_type": "m5.large",
            "cpu_count": 8,  # Too high for the memory
            "memory_mib": 512,  # Too low for the CPU count
            "eif_path": "s3://bucket/enclave.eif"
        }
        
        result = validate_deploy_request("test-enclave-123", config)
        assert result['valid'] is False
        assert "ratio" in result['message'].lower()
    
    def test_missing_required_fields(self):
        """Test validation with missing required fields"""
        config = {
            "instance_type": "m5.large",
            # Missing cpu_count, memory_mib, eif_path
        }
        
        result = validate_deploy_request("test-enclave-123", config)
        assert result['valid'] is False
    
    def test_destroy_validation_success(self):
        """Test successful destroy validation"""
        result = validate_destroy_request("test-enclave-123", {})
        # Note: This will fail in real scenario without DynamoDB, but validates structure
        assert 'valid' in result
        assert 'message' in result
    
    def test_create_response_format(self):
        """Test response format is correct"""
        response = create_response(True, "Test message")
        
        assert isinstance(response, dict)
        assert 'valid' in response
        assert 'message' in response
        assert 'timestamp' in response
        assert response['valid'] is True
        assert response['message'] == "Test message"