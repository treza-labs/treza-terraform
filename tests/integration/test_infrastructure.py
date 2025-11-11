"""
Integration tests for Treza Terraform Infrastructure
Tests actual AWS resources after deployment
"""

import boto3
import pytest
import os
import json
from typing import Dict, List

# AWS Region from environment or default
AWS_REGION = os.environ.get('AWS_REGION', 'us-west-2')
ENVIRONMENT = os.environ.get('ENVIRONMENT', 'dev')
PROJECT_NAME = os.environ.get('PROJECT_NAME', 'treza')


class TestVPCInfrastructure:
    """Test VPC and networking components"""
    
    @pytest.fixture(scope='class')
    def ec2_client(self):
        return boto3.client('ec2', region_name=AWS_REGION)
    
    def test_vpc_exists(self, ec2_client):
        """Test that VPC exists with correct tags"""
        vpcs = ec2_client.describe_vpcs(
            Filters=[
                {'Name': 'tag:Environment', 'Values': [ENVIRONMENT]},
                {'Name': 'tag:Project', 'Values': [PROJECT_NAME]}
            ]
        )
        
        assert len(vpcs['Vpcs']) >= 1, "VPC not found"
        vpc = vpcs['Vpcs'][0]
        assert vpc['State'] == 'available', "VPC is not available"
        
    def test_subnets_exist(self, ec2_client):
        """Test that public and private subnets exist"""
        vpcs = ec2_client.describe_vpcs(
            Filters=[
                {'Name': 'tag:Environment', 'Values': [ENVIRONMENT]},
                {'Name': 'tag:Project', 'Values': [PROJECT_NAME]}
            ]
        )
        
        if not vpcs['Vpcs']:
            pytest.skip("VPC not found")
            
        vpc_id = vpcs['Vpcs'][0]['VpcId']
        
        subnets = ec2_client.describe_subnets(
            Filters=[{'Name': 'vpc-id', 'Values': [vpc_id]}]
        )
        
        assert len(subnets['Subnets']) >= 4, "Not enough subnets (expected at least 4)"
        
        public_subnets = [s for s in subnets['Subnets'] 
                         if any(tag['Key'] == 'Type' and 'public' in tag['Value'].lower() 
                               for tag in s.get('Tags', []))]
        private_subnets = [s for s in subnets['Subnets'] 
                          if any(tag['Key'] == 'Type' and 'private' in tag['Value'].lower() 
                                for tag in s.get('Tags', []))]
        
        assert len(public_subnets) >= 2, "Not enough public subnets"
        assert len(private_subnets) >= 2, "Not enough private subnets"
        
    def test_nat_gateways_exist(self, ec2_client):
        """Test that NAT gateways exist and are available"""
        vpcs = ec2_client.describe_vpcs(
            Filters=[
                {'Name': 'tag:Environment', 'Values': [ENVIRONMENT]},
                {'Name': 'tag:Project', 'Values': [PROJECT_NAME]}
            ]
        )
        
        if not vpcs['Vpcs']:
            pytest.skip("VPC not found")
            
        vpc_id = vpcs['Vpcs'][0]['VpcId']
        
        nat_gateways = ec2_client.describe_nat_gateways(
            Filters=[{'Name': 'vpc-id', 'Values': [vpc_id]}]
        )
        
        assert len(nat_gateways['NatGateways']) >= 1, "No NAT gateways found"
        
        for nat in nat_gateways['NatGateways']:
            assert nat['State'] in ['available', 'pending'], f"NAT gateway {nat['NatGatewayId']} not available"
            
    def test_vpc_endpoints_exist(self, ec2_client):
        """Test that required VPC endpoints exist"""
        vpcs = ec2_client.describe_vpcs(
            Filters=[
                {'Name': 'tag:Environment', 'Values': [ENVIRONMENT]},
                {'Name': 'tag:Project', 'Values': [PROJECT_NAME]}
            ]
        )
        
        if not vpcs['Vpcs']:
            pytest.skip("VPC not found")
            
        vpc_id = vpcs['Vpcs'][0]['VpcId']
        
        endpoints = ec2_client.describe_vpc_endpoints(
            Filters=[{'Name': 'vpc-id', 'Values': [vpc_id]}]
        )
        
        assert len(endpoints['VpcEndpoints']) >= 3, "Not enough VPC endpoints"
        
        service_names = [e['ServiceName'] for e in endpoints['VpcEndpoints']]
        required_services = ['s3', 'dynamodb', 'ecr']
        
        for service in required_services:
            assert any(service in sn for sn in service_names), f"Missing VPC endpoint for {service}"


class TestECSInfrastructure:
    """Test ECS cluster and task definitions"""
    
    @pytest.fixture(scope='class')
    def ecs_client(self):
        return boto3.client('ecs', region_name=AWS_REGION)
    
    def test_ecs_cluster_exists(self, ecs_client):
        """Test that ECS cluster exists"""
        cluster_name = f"{PROJECT_NAME}-{ENVIRONMENT}"
        
        clusters = ecs_client.describe_clusters(clusters=[cluster_name])
        
        assert len(clusters['clusters']) == 1, "ECS cluster not found"
        cluster = clusters['clusters'][0]
        assert cluster['status'] == 'ACTIVE', "ECS cluster not active"
        
    def test_task_definition_exists(self, ecs_client):
        """Test that Terraform runner task definition exists"""
        task_family = f"{PROJECT_NAME}-{ENVIRONMENT}-terraform-runner"
        
        try:
            task_def = ecs_client.describe_task_definition(taskDefinition=task_family)
            assert task_def['taskDefinition']['status'] == 'ACTIVE', "Task definition not active"
        except ecs_client.exceptions.ClientException:
            pytest.fail("Task definition not found")


class TestLambdaFunctions:
    """Test Lambda functions"""
    
    @pytest.fixture(scope='class')
    def lambda_client(self):
        return boto3.client('lambda', region_name=AWS_REGION)
    
    def test_trigger_lambda_exists(self, lambda_client):
        """Test that trigger Lambda function exists"""
        function_name = f"{PROJECT_NAME}-{ENVIRONMENT}-enclave-trigger"
        
        try:
            response = lambda_client.get_function(FunctionName=function_name)
            config = response['Configuration']
            assert config['State'] == 'Active', "Lambda function not active"
            assert config['Runtime'].startswith('python'), "Lambda not using Python runtime"
        except lambda_client.exceptions.ResourceNotFoundException:
            pytest.fail(f"Lambda function {function_name} not found")
            
    def test_validation_lambda_exists(self, lambda_client):
        """Test that validation Lambda function exists"""
        function_name = f"{PROJECT_NAME}-{ENVIRONMENT}-validation"
        
        try:
            response = lambda_client.get_function(FunctionName=function_name)
            config = response['Configuration']
            assert config['State'] == 'Active', "Lambda function not active"
        except lambda_client.exceptions.ResourceNotFoundException:
            pytest.fail(f"Lambda function {function_name} not found")


class TestStepFunctions:
    """Test Step Functions state machines"""
    
    @pytest.fixture(scope='class')
    def sfn_client(self):
        return boto3.client('stepfunctions', region_name=AWS_REGION)
    
    def test_deployment_state_machine_exists(self, sfn_client):
        """Test that deployment state machine exists"""
        state_machine_name = f"{PROJECT_NAME}-{ENVIRONMENT}-deployment"
        
        state_machines = sfn_client.list_state_machines()
        
        matching = [sm for sm in state_machines['stateMachines'] 
                   if state_machine_name in sm['name']]
        
        assert len(matching) >= 1, "Deployment state machine not found"
        assert matching[0]['status'] == 'ACTIVE', "State machine not active"
        
    def test_cleanup_state_machine_exists(self, sfn_client):
        """Test that cleanup state machine exists"""
        state_machine_name = f"{PROJECT_NAME}-{ENVIRONMENT}-cleanup"
        
        state_machines = sfn_client.list_state_machines()
        
        matching = [sm for sm in state_machines['stateMachines'] 
                   if state_machine_name in sm['name']]
        
        assert len(matching) >= 1, "Cleanup state machine not found"
        assert matching[0]['status'] == 'ACTIVE', "State machine not active"


class TestMonitoring:
    """Test monitoring and logging"""
    
    @pytest.fixture(scope='class')
    def cw_client(self):
        return boto3.client('cloudwatch', region_name=AWS_REGION)
    
    @pytest.fixture(scope='class')
    def logs_client(self):
        return boto3.client('logs', region_name=AWS_REGION)
    
    def test_cloudwatch_log_groups_exist(self, logs_client):
        """Test that CloudWatch log groups exist"""
        log_group_prefix = f"/aws/lambda/{PROJECT_NAME}-{ENVIRONMENT}"
        
        log_groups = logs_client.describe_log_groups(
            logGroupNamePrefix=log_group_prefix
        )
        
        assert len(log_groups['logGroups']) >= 1, "No log groups found"
        
    def test_cloudwatch_dashboard_exists(self, cw_client):
        """Test that CloudWatch dashboard exists"""
        dashboard_name = f"{PROJECT_NAME}-{ENVIRONMENT}"
        
        try:
            dashboard = cw_client.get_dashboard(DashboardName=dashboard_name)
            assert dashboard['DashboardBody'], "Dashboard body is empty"
        except cw_client.exceptions.DashboardNotFoundError:
            pytest.skip("Dashboard not found (optional)")


class TestIAMRoles:
    """Test IAM roles and policies"""
    
    @pytest.fixture(scope='class')
    def iam_client(self):
        return boto3.client('iam', region_name=AWS_REGION)
    
    def test_lambda_execution_role_exists(self, iam_client):
        """Test that Lambda execution role exists"""
        role_name = f"{PROJECT_NAME}-{ENVIRONMENT}-lambda-execution"
        
        try:
            role = iam_client.get_role(RoleName=role_name)
            assert 'Role' in role, "Role not found"
        except iam_client.exceptions.NoSuchEntityException:
            pytest.skip("Role naming might be different")
            
    def test_ecs_task_role_exists(self, iam_client):
        """Test that ECS task role exists"""
        role_name = f"{PROJECT_NAME}-{ENVIRONMENT}-ecs-task"
        
        try:
            role = iam_client.get_role(RoleName=role_name)
            assert 'Role' in role, "Role not found"
        except iam_client.exceptions.NoSuchEntityException:
            pytest.skip("Role naming might be different")


class TestDynamoDB:
    """Test DynamoDB configuration"""
    
    @pytest.fixture(scope='class')
    def dynamodb_client(self):
        return boto3.client('dynamodb', region_name=AWS_REGION)
    
    def test_state_lock_table_exists(self, dynamodb_client):
        """Test that Terraform state lock table exists"""
        table_name = f"{PROJECT_NAME}-terraform-locks-{ENVIRONMENT}"
        
        try:
            table = dynamodb_client.describe_table(TableName=table_name)
            assert table['Table']['TableStatus'] == 'ACTIVE', "Table not active"
        except dynamodb_client.exceptions.ResourceNotFoundException:
            pytest.skip("State lock table might have different naming")


class TestSecurityGroups:
    """Test security group configuration"""
    
    @pytest.fixture(scope='class')
    def ec2_client(self):
        return boto3.client('ec2', region_name=AWS_REGION)
    
    def test_shared_security_group_exists(self, ec2_client):
        """Test that shared enclave security group exists"""
        vpcs = ec2_client.describe_vpcs(
            Filters=[
                {'Name': 'tag:Environment', 'Values': [ENVIRONMENT]},
                {'Name': 'tag:Project', 'Values': [PROJECT_NAME]}
            ]
        )
        
        if not vpcs['Vpcs']:
            pytest.skip("VPC not found")
            
        vpc_id = vpcs['Vpcs'][0]['VpcId']
        
        security_groups = ec2_client.describe_security_groups(
            Filters=[
                {'Name': 'vpc-id', 'Values': [vpc_id]},
                {'Name': 'tag:Name', 'Values': [f"*shared*"]}
            ]
        )
        
        assert len(security_groups['SecurityGroups']) >= 1, "Shared security group not found"


if __name__ == '__main__':
    pytest.main([__file__, '-v', '--tb=short'])

