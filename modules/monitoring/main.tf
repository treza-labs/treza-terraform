# CloudWatch Dashboard
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.name_prefix}-infrastructure"
  
  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        
        properties = {
          metrics = [
            ["AWS/States", "ExecutionsSucceeded", "StateMachineArn", var.step_function_arn],
            [".", "ExecutionsFailed", ".", "."],
            [".", "ExecutionsStarted", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Step Functions Executions"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        
        properties = {
          metrics = [
            ["AWS/ECS", "RunningTaskCount", "ServiceName", var.ecs_cluster_name, "ClusterName", var.ecs_cluster_name],
            [".", "PendingTaskCount", ".", ".", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "ECS Tasks"
          period  = 300
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 6
        width  = 24
        height = 6
        
        properties = {
          query   = "SOURCE '/aws/stepfunctions/${var.name_prefix}-deployment'\n| fields @timestamp, @message\n| sort @timestamp desc\n| limit 100"
          region  = data.aws_region.current.name
          title   = "Step Functions Logs"
        }
      }
    ]
  })
}

# CloudWatch Alarm for Step Function Failures
resource "aws_cloudwatch_metric_alarm" "step_function_failures" {
  alarm_name          = "${var.name_prefix}-step-function-failures"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ExecutionsFailed"
  namespace           = "AWS/States"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors step function failures"
  alarm_actions       = var.sns_topic_arn != "" ? [var.sns_topic_arn] : []
  
  dimensions = {
    StateMachineArn = var.step_function_arn
  }
  
  tags = var.tags
}

# CloudWatch Alarm for ECS Task Failures
resource "aws_cloudwatch_metric_alarm" "ecs_task_failures" {
  alarm_name          = "${var.name_prefix}-ecs-task-failures"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ServiceEvents"
  namespace           = "AWS/ECS"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors ECS task failures"
  alarm_actions       = var.sns_topic_arn != "" ? [var.sns_topic_arn] : []
  
  dimensions = {
    ClusterName = var.ecs_cluster_name
  }
  
  tags = var.tags
}

# CloudWatch Log Insights Queries
resource "aws_cloudwatch_query_definition" "terraform_errors" {
  name = "${var.name_prefix}-terraform-errors"
  
  log_group_names = [
    "/aws/stepfunctions/${var.name_prefix}-deployment",
    "/ecs/${var.name_prefix}-terraform-runner"
  ]
  
  query_string = <<EOF
fields @timestamp, @message
| filter @message like /ERROR/
| sort @timestamp desc
| limit 50
EOF
}

resource "aws_cloudwatch_query_definition" "deployment_duration" {
  name = "${var.name_prefix}-deployment-duration"
  
  log_group_names = [
    "/aws/stepfunctions/${var.name_prefix}-deployment"
  ]
  
  query_string = <<EOF
fields @timestamp, @message
| filter @type = "ExecutionSucceeded" or @type = "ExecutionFailed"
| stats count() by bin(5m)
EOF
}

# Optional SNS Topic for Alerts (if notifications are needed)
resource "aws_sns_topic" "alerts" {
  count = var.create_sns_topic ? 1 : 0
  name  = "${var.name_prefix}-infrastructure-alerts"
  
  tags = var.tags
}

resource "aws_sns_topic_subscription" "email_alerts" {
  count     = var.create_sns_topic && var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts[0].arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# Data source for current region
data "aws_region" "current" {}