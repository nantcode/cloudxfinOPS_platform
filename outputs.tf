output "api_gateway_endpoint" {
  description = "HTTP API Gateway base endpoint URL"
  value       = module.api_gateway.api_endpoint
}

output "github_webhook_url" {
  description = "Full URL to configure in GitHub Repo Settings -> Webhooks"
  value       = "${module.api_gateway.api_endpoint}/webhooks/github"
}

output "github_plan_role_arn" {
  description = "Role GitHub Actions assumes to run terraform plan"
  value       = module.github_oidc.plan_role_arn
}

output "fleet_dashboard_url" {
  value = module.fleet_monitoring.dashboard_url
}

output "fleet_alerts_topic_arn" {
  value = module.fleet_monitoring.alerts_topic_arn
}

output "fleet_monitored_functions" {
  value = module.fleet_monitoring.monitored_functions
}
