import json
import boto3
import os
import logging
from datetime import datetime

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
dynamodb = boto3.resource('dynamodb')
sns = boto3.client('sns')

def handler(event, context):
    """
    Lambda function to handle errors in the enclave deployment process.
    Logs errors, updates status, and optionally sends notifications.
    """
    try:
        logger.info(f"Handling error event: {json.dumps(event)}")
        
        enclave_id = event.get('enclave_id')
        error_info = event.get('error', {})
        
        if not enclave_id:
            logger.error("No enclave_id provided in error event")
            return create_response(False, "Missing enclave_id")
        
        # Extract error details
        error_message = extract_error_message(error_info)
        error_type = extract_error_type(error_info)
        
        logger.error(f"Error in enclave {enclave_id}: {error_message}")
        
        # Update enclave status in DynamoDB
        update_result = update_enclave_error_status(enclave_id, error_message, error_type)
        
        # Send notification if configured
        notification_result = send_error_notification(enclave_id, error_message, error_type)
        
        return create_response(True, "Error handled successfully", {
            'enclave_id': enclave_id,
            'error_type': error_type,
            'error_message': error_message,
            'database_updated': update_result,
            'notification_sent': notification_result
        })
        
    except Exception as e:
        logger.error(f"Error in error handler: {str(e)}")
        return create_response(False, f"Error handler failed: {str(e)}")

def extract_error_message(error_info):
    """Extract human-readable error message from error info"""
    if isinstance(error_info, dict):
        # Try different error message fields
        for field in ['Cause', 'Error', 'Message', 'message']:
            if field in error_info:
                try:
                    # If it's JSON, try to parse it
                    if isinstance(error_info[field], str) and error_info[field].startswith('{'):
                        parsed = json.loads(error_info[field])
                        return parsed.get('errorMessage', error_info[field])
                    return str(error_info[field])
                except:
                    return str(error_info[field])
        
        # If no specific field found, return the whole error as string
        return json.dumps(error_info)
    
    return str(error_info)

def extract_error_type(error_info):
    """Extract error type from error info"""
    if isinstance(error_info, dict):
        # Try different error type fields
        for field in ['Error', 'errorType', 'type']:
            if field in error_info:
                return str(error_info[field])
    
    return "UnknownError"

def update_enclave_error_status(enclave_id, error_message, error_type):
    """Update enclave status in DynamoDB with error information"""
    try:
        table_name = os.environ.get('DYNAMODB_TABLE_NAME')
        if not table_name:
            logger.warning("No DynamoDB table name configured")
            return False
        
        table = dynamodb.Table(table_name)
        
        response = table.update_item(
            Key={'id': enclave_id},
            UpdateExpression='SET #status = :status, #updated_at = :timestamp, #error_message = :error_msg, #error_type = :error_type',
            ExpressionAttributeNames={
                '#status': 'status',
                '#updated_at': 'updated_at',
                '#error_message': 'error_message',
                '#error_type': 'error_type'
            },
            ExpressionAttributeValues={
                ':status': 'FAILED',
                ':timestamp': datetime.utcnow().isoformat(),
                ':error_msg': error_message,
                ':error_type': error_type
            },
            ReturnValues='UPDATED_NEW'
        )
        
        logger.info(f"Updated enclave {enclave_id} status to FAILED")
        return True
        
    except Exception as e:
        logger.error(f"Failed to update enclave status: {str(e)}")
        return False

def send_error_notification(enclave_id, error_message, error_type):
    """Send error notification via SNS if configured"""
    try:
        sns_topic_arn = os.environ.get('SNS_TOPIC_ARN')
        if not sns_topic_arn:
            logger.info("No SNS topic configured for notifications")
            return False
        
        message = {
            'enclave_id': enclave_id,
            'error_type': error_type,
            'error_message': error_message,
            'timestamp': datetime.utcnow().isoformat(),
            'source': 'treza-terraform-infrastructure'
        }
        
        subject = f"Treza Enclave Error: {enclave_id}"
        
        response = sns.publish(
            TopicArn=sns_topic_arn,
            Message=json.dumps(message, indent=2),
            Subject=subject
        )
        
        logger.info(f"Sent error notification for enclave {enclave_id}")
        return True
        
    except Exception as e:
        logger.error(f"Failed to send error notification: {str(e)}")
        return False

def create_response(success, message, data=None):
    """Create standardized response"""
    response = {
        'success': success,
        'message': message,
        'timestamp': datetime.utcnow().isoformat()
    }
    
    if data:
        response['data'] = data
    
    return response