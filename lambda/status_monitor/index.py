import json
import boto3
import os
import logging
from datetime import datetime

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
ec2 = boto3.client('ec2')
dynamodb = boto3.resource('dynamodb')

def handler(event, context):
    """
    Lambda function to monitor EC2 instance states and update enclave statuses.
    Triggered by CloudWatch Events (EventBridge) on a schedule.
    """
    try:
        logger.info("Starting enclave status monitoring")
        
        table_name = os.environ['DYNAMODB_TABLE_NAME']
        table = dynamodb.Table(table_name)
        
        # Scan for enclaves in transitional states
        transitional_statuses = ['PAUSING', 'RESUMING', 'DESTROYING']
        
        for status in transitional_statuses:
            response = table.scan(
                FilterExpression='#status = :status',
                ExpressionAttributeNames={'#status': 'status'},
                ExpressionAttributeValues={':status': status}
            )
            
            for item in response['Items']:
                process_enclave_status(item, table)
        
        return {
            'statusCode': 200,
            'body': json.dumps('Successfully monitored enclave statuses')
        }
        
    except Exception as e:
        logger.error(f"Error monitoring statuses: {str(e)}")
        raise e

def process_enclave_status(enclave, table):
    """Process a single enclave's status"""
    try:
        enclave_id = enclave['id']
        current_status = enclave['status']
        
        logger.info(f"Checking enclave {enclave_id} with status {current_status}")
        
        # Find the associated EC2 instance
        ec2_response = ec2.describe_instances(
            Filters=[
                {
                    'Name': 'tag:EnclaveId',
                    'Values': [enclave_id]
                },
                {
                    'Name': 'instance-state-name',
                    'Values': ['running', 'stopped', 'stopping', 'pending', 'terminated']
                }
            ]
        )
        
        instance_id = None
        instance_state = None
        
        # Find the instance
        for reservation in ec2_response['Reservations']:
            for instance in reservation['Instances']:
                instance_id = instance['InstanceId']
                instance_state = instance['State']['Name']
                break
        
        if not instance_id:
            # Check if this is a DESTROYING enclave - if so, instance might already be terminated and cleaned up
            if current_status == 'DESTROYING':
                logger.info(f"No EC2 instance found for DESTROYING enclave {enclave_id} - likely already terminated, marking as DESTROYED")
                new_status = 'DESTROYED'
                # Update status directly since we have the info we need
                table.update_item(
                    Key={'id': enclave_id},
                    UpdateExpression='SET #status = :status, #updated_at = :timestamp',
                    ExpressionAttributeNames={
                        '#status': 'status',
                        '#updated_at': 'updatedAt'
                    },
                    ExpressionAttributeValues={
                        ':status': new_status,
                        ':timestamp': datetime.utcnow().isoformat()
                    }
                )
                return
            else:
                logger.warning(f"No EC2 instance found for enclave {enclave_id}")
                return
        
        logger.info(f"Instance {instance_id} state: {instance_state}")
        
        # Determine the new status and take actions based on current status and instance state
        new_status = None
        action_taken = False
        
        if current_status == 'PAUSING':
            if instance_state == 'running':
                # Need to stop the instance
                try:
                    logger.info(f"Stopping instance {instance_id} for enclave {enclave_id}")
                    ec2.stop_instances(InstanceIds=[instance_id])
                    action_taken = True
                except Exception as e:
                    logger.error(f"Failed to stop instance {instance_id}: {str(e)}")
            elif instance_state == 'stopped':
                new_status = 'PAUSED'
            elif instance_state in ['stopping']:
                # Still transitioning, keep current status
                pass
            else:
                logger.warning(f"Unexpected state {instance_state} for pausing enclave {enclave_id}")
        
        elif current_status == 'RESUMING':
            if instance_state == 'stopped':
                # Need to start the instance
                try:
                    logger.info(f"Starting instance {instance_id} for enclave {enclave_id}")
                    ec2.start_instances(InstanceIds=[instance_id])
                    action_taken = True
                except Exception as e:
                    logger.error(f"Failed to start instance {instance_id}: {str(e)}")
            elif instance_state == 'running':
                new_status = 'DEPLOYED'
            elif instance_state in ['pending']:
                # Still transitioning, keep current status
                pass
            else:
                logger.warning(f"Unexpected state {instance_state} for resuming enclave {enclave_id}")
        
        elif current_status == 'DESTROYING':
            if instance_state == 'terminated':
                # Instance has been terminated, mark as destroyed
                new_status = 'DESTROYED'
                logger.info(f"Instance {instance_id} is terminated, marking enclave {enclave_id} as DESTROYED")
            elif instance_state in ['running', 'stopped']:
                # Instance still exists but should be terminated - this might indicate a stuck destruction
                logger.warning(f"Enclave {enclave_id} is in DESTROYING state but instance {instance_id} is still {instance_state}")
                # Could potentially trigger termination here if needed
            elif instance_state in ['stopping']:
                # Instance is being stopped as part of termination process
                logger.info(f"Instance {instance_id} is stopping as part of destruction process for enclave {enclave_id}")
            else:
                logger.warning(f"Unexpected state {instance_state} for destroying enclave {enclave_id}")
        
        # Update status if changed
        if new_status and new_status != current_status:
            logger.info(f"Updating enclave {enclave_id} status from {current_status} to {new_status}")
            
            table.update_item(
                Key={'id': enclave_id},
                UpdateExpression='SET #status = :status, #updated_at = :timestamp',
                ExpressionAttributeNames={
                    '#status': 'status',
                    '#updated_at': 'updatedAt'
                },
                ExpressionAttributeValues={
                    ':status': new_status,
                    ':timestamp': datetime.utcnow().isoformat()
                }
            )
            
            logger.info(f"Successfully updated enclave {enclave_id} to {new_status}")
        elif action_taken:
            logger.info(f"Action taken for enclave {enclave_id}, will check again next cycle")
            
    except Exception as e:
        logger.error(f"Error processing enclave {enclave.get('id', 'unknown')}: {str(e)}")
        raise e
