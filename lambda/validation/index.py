import json
import boto3
import os
import logging
from jsonschema import validate, ValidationError  # Required: jsonschema==4.20.0

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
dynamodb = boto3.resource('dynamodb')

def handler(event, context):
    """
    Lambda function to validate enclave deployment requests.
    Validates configuration and prerequisites before deployment.
    """
    try:
        logger.info(f"Validating deployment request: {json.dumps(event)}")
        
        enclave_id = event.get('enclave_id')
        action = event.get('action')
        configuration = event.get('configuration', '{}')
        
        if not enclave_id:
            return create_response(False, "Missing enclave_id")
        
        if not action:
            return create_response(False, "Missing action")
        
        # Parse configuration
        try:
            config = json.loads(configuration) if isinstance(configuration, str) else configuration
        except json.JSONDecodeError:
            return create_response(False, "Invalid JSON configuration")
        
        # Validate based on action
        if action == 'deploy':
            validation_result = validate_deploy_request(enclave_id, config)
        elif action == 'destroy':
            validation_result = validate_destroy_request(enclave_id, config)
        else:
            validation_result = create_response(False, f"Unknown action: {action}")
        
        logger.info(f"Validation result: {validation_result}")
        return validation_result
        
    except Exception as e:
        logger.error(f"Error during validation: {str(e)}")
        return create_response(False, f"Validation error: {str(e)}")

def validate_deploy_request(enclave_id, config):
    """Validate deployment request"""
    try:
        # Apply default values for required fields if not provided
        config.setdefault("instance_type", "m5.large")
        config.setdefault("cpu_count", 2)
        config.setdefault("memory_mib", 1024)
        config.setdefault("eif_path", "/opt/aws/nitro_enclaves/share/hello.eif")
        config.setdefault("debug_mode", False)
        
        # Define schema for enclave configuration
        config_schema = {
            "type": "object",
            "properties": {
                "instance_type": {
                    "type": "string",
                    "enum": ["m5.large", "m5.xlarge", "m5.2xlarge", "m5.4xlarge", "c5.large", "c5.xlarge", "c5.2xlarge", "c5.4xlarge"]
                },
                "cpu_count": {
                    "type": "integer",
                    "minimum": 2,
                    "maximum": 16
                },
                "memory_mib": {
                    "type": "integer",
                    "minimum": 512,
                    "maximum": 32768
                },
                "eif_path": {
                    "type": "string",
                    "minLength": 1
                },
                "debug_mode": {
                    "type": "boolean"
                }
            },
            "required": ["instance_type", "cpu_count", "memory_mib", "eif_path"],
            "additionalProperties": True
        }
        
        # Validate configuration against schema
        validate(config, config_schema)
        
        # Additional business logic validation
        if config.get('cpu_count', 0) > config.get('memory_mib', 0) / 512:
            return create_response(False, "CPU to memory ratio is invalid")
        
        # Check if enclave already exists and is deployed
        table_name = os.environ.get('DYNAMODB_TABLE_NAME')
        if table_name:
            table = dynamodb.Table(table_name)
            try:
                response = table.get_item(Key={'id': enclave_id})
                if 'Item' in response:
                    current_status = response['Item'].get('status')
                    if current_status in ['DEPLOYED', 'DEPLOYING']:
                        return create_response(False, f"Enclave is already {current_status}")
            except Exception as e:
                logger.warning(f"Could not check existing enclave status: {str(e)}")
        
        return create_response(True, "Deployment request is valid")
        
    except ValidationError as e:
        return create_response(False, f"Configuration validation failed: {e.message}")
    except Exception as e:
        return create_response(False, f"Deployment validation failed: {str(e)}")

def validate_destroy_request(enclave_id, config):
    """Validate destroy request"""
    try:
        # Check if enclave exists and can be destroyed
        table_name = os.environ.get('DYNAMODB_TABLE_NAME')
        if table_name:
            table = dynamodb.Table(table_name)
            try:
                response = table.get_item(Key={'id': enclave_id})
                if 'Item' not in response:
                    return create_response(False, "Enclave does not exist")
                
                current_status = response['Item'].get('status')
                if current_status in ['DESTROYING', 'DESTROYED']:
                    return create_response(False, f"Enclave is already {current_status}")
                
                if current_status == 'DEPLOYING':
                    return create_response(False, "Cannot destroy enclave while it's being deployed")
                    
            except Exception as e:
                logger.warning(f"Could not check existing enclave status: {str(e)}")
                return create_response(False, f"Could not verify enclave status: {str(e)}")
        
        return create_response(True, "Destroy request is valid")
        
    except Exception as e:
        return create_response(False, f"Destroy validation failed: {str(e)}")

def create_response(valid, message):
    """Create standardized response"""
    return {
        'valid': valid,
        'message': message,
        'timestamp': boto3.client('sts').get_caller_identity()['Arn']
    }