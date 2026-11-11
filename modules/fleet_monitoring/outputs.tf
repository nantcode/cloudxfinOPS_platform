output "alerts_topic_arn" {
  value = aws_sns_topic.alerts.arn
}

output "monitored_functions" {
  value = local.functions
}

output "dashboard_url" {
  value = "https://${data.aws_region.current.region}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.region}#dashboards/dashboard/${aws_cloudwatch_dashboard.fleet.dashboard_name}"
}
