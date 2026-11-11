resource "aws_iam_role" "heartbeat" {
  name = "fleet-heartbeat-checker"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "heartbeat_logs" {
  role       = aws_iam_role.heartbeat.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "heartbeat_metrics" {
  name = "read-invocations-write-heartbeat"
  role = aws_iam_role.heartbeat.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "cloudwatch:GetMetricStatistics"
        Resource = "*"
      },
      {
        Effect    = "Allow"
        Action    = "cloudwatch:PutMetricData"
        Resource  = "*"
        Condition = { StringEquals = { "cloudwatch:namespace" = "Fleet/Heartbeat" } }
      }
    ]
  })
}

resource "aws_lambda_function" "heartbeat" {
  function_name    = "fleet-heartbeat-checker"
  role             = aws_iam_role.heartbeat.arn
  handler          = "lambda_function.handler"
  runtime          = "python3.12"
  timeout          = 30
  filename         = var.heartbeat_zip_path
  source_code_hash = var.heartbeat_zip_hash

  environment {
    variables = {
      HEARTBEATS = jsonencode(var.heartbeats)
    }
  }
}

resource "aws_iam_role" "scheduler" {
  name = "fleet-heartbeat-scheduler"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "scheduler.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "scheduler_invoke" {
  name = "invoke-heartbeat-checker"
  role = aws_iam_role.scheduler.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "lambda:InvokeFunction"
      Resource = aws_lambda_function.heartbeat.arn
    }]
  })
}

resource "aws_scheduler_schedule" "heartbeat" {
  name                         = "fleet-heartbeat"
  schedule_expression          = "cron(0/15 10-15 ? * MON-FRI *)"
  schedule_expression_timezone = "America/New_York"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_function.heartbeat.arn
    role_arn = aws_iam_role.scheduler.arn
  }
}

resource "aws_cloudwatch_metric_alarm" "heartbeat" {
  for_each            = var.heartbeats
  alarm_name          = "fleet-${each.key}-heartbeat"
  alarm_description   = "${each.key} has not run in the last ${each.value} minutes of market hours"
  namespace           = "Fleet/Heartbeat"
  metric_name         = "Quiet"
  dimensions          = { FunctionName = each.key }
  statistic           = "Maximum"
  period              = 900
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "heartbeat_checker_errors" {
  alarm_name          = "fleet-heartbeat-checker-errors"
  alarm_description   = "The heartbeat checker itself is failing, so heartbeats are not being checked"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = aws_lambda_function.heartbeat.function_name }
  statistic           = "Sum"
  period              = 900
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}
