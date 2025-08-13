import json
import boto3
import os
import logging
from datetime import datetime

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
stepfunctions = boto3.client('stepfunctions')
dynamodb = boto3.resource('dynamodb')

def handler(event, context):
    """
    Lambda function triggered by DynamoDB Streams when enclave records are modified.
    Starts Step Functions execution for enclave deployment or destruction.
    """
    try:
        logger.info(f"Received event: {json.dumps(event)}")
        
        deployment_step_function_arn = os.environ['DEPLOYMENT_STEP_FUNCTION_ARN']
        cleanup_step_function_arn = os.environ['CLEANUP_STEP_FUNCTION_ARN']
        table_name = os.environ['DYNAMODB_TABLE_NAME']
        
        for record in event['Records']:
            if record['eventName'] in ['INSERT', 'MODIFY']:
                process_record(record, deployment_step_function_arn, cleanup_step_function_arn)
        
        return {
            'statusCode': 200,
            'body': json.dumps('Successfully processed DynamoDB stream events')
        }
        
    except Exception as e:
        logger.error(f"Error processing event: {str(e)}")
        raise e

def process_record(record, deployment_step_function_arn, cleanup_step_function_arn):
    """Process a single DynamoDB stream record"""
    try:
        # Extract enclave data from the record
        if 'NewImage' in record['dynamodb']:
            new_image = record['dynamodb']['NewImage']
            
            enclave_id = new_image.get('id', {}).get('S')
            status = new_image.get('status', {}).get('S')
            
            if not enclave_id:
                logger.warning("No enclave ID found in record")
                return
            
            logger.info(f"Processing enclave {enclave_id} with status {status}")
            
            # Only trigger for specific status changes
            if status in ['PENDING_DEPLOY', 'PENDING_DESTROY']:
                action = 'deploy' if status == 'PENDING_DEPLOY' else 'destroy'
                
                # Select the appropriate Step Functions state machine based on action
                step_function_arn = deployment_step_function_arn if action == 'deploy' else cleanup_step_function_arn
                
                # Prepare Step Functions input
                step_input = {
                    'enclave_id': enclave_id,
                    'action': action,
                    'configuration': new_image.get('configuration', {}).get('S', '{}'),
                    'timestamp': datetime.utcnow().isoformat()
                }
                
                # Start Step Functions execution
                execution_name = f"{enclave_id}-{action}-{int(datetime.utcnow().timestamp())}"
                
                logger.info(f"Starting {action} workflow using state machine: {step_function_arn}")
                
                response = stepfunctions.start_execution(
                    stateMachineArn=step_function_arn,
                    name=execution_name,
                    input=json.dumps(step_input)
                )
                
                logger.info(f"Started Step Functions execution: {response['executionArn']}")
                
    except Exception as e:
        logger.error(f"Error processing record: {str(e)}")
        raise e