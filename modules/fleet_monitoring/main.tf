data "aws_region" "current" {}

data "aws_lambda_functions" "all" {}

locals {
  functions = sort(tolist(setsubtract(toset(data.aws_lambda_functions.all.function_names), toset(var.exclude_functions))))
}

data "aws_lambda_function" "fleet" {
  for_each      = toset(local.functions)
  function_name = each.value
}

resource "aws_sns_topic" "alerts" {
  name = "fleet-alerts"
}

resource "aws_cloudwatch_metric_alarm" "errors" {
  for_each            = toset(local.functions)
  alarm_name          = "fleet-${each.value}-errors"
  alarm_description   = "${each.value} had at least one error in 5 minutes"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = each.value }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "near_timeout" {
  for_each            = toset(local.functions)
  alarm_name          = "fleet-${each.value}-near-timeout"
  alarm_description   = "${each.value} ran longer than 80% of its timeout"
  namespace           = "AWS/Lambda"
  metric_name         = "Duration"
  dimensions          = { FunctionName = each.value }
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  threshold           = data.aws_lambda_function.fleet[each.value].timeout * 1000 * 0.8
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_dashboard" "fleet" {
  dashboard_name = "fleet-overview"
  dashboard_body = jsonencode({
    widgets = [
      for i, metric in ["Invocations", "Errors", "Duration"] : {
        type   = "metric"
        x      = 0
        y      = i * 6
        width  = 24
        height = 6
        properties = {
          title   = metric
          region  = data.aws_region.current.region
          view    = "timeSeries"
          stacked = false
          stat    = metric == "Duration" ? "Maximum" : "Sum"
          period  = 300
          metrics = [for fn in local.functions : ["AWS/Lambda", metric, "FunctionName", fn]]
        }
      }
    ]
  })
}
