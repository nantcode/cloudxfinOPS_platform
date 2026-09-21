output "api_gateway_endpoint" {
  description = "HTTP API Gateway base endpoint URL"
  value       = module.api_gateway.api_endpoint
}

output "github_webhook_url" {
  description = "Full URL to configure in GitHub Repo Settings -> Webhooks"
  value       = "${module.api_gateway.api_endpoint}/webhooks/github"
}
