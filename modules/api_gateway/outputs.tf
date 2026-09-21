output "api_endpoint" {
  description = "HTTP API Gateway base endpoint URL"
  value       = aws_apigatewayv2_api.http_api.api_endpoint
}

output "api_id" {
  description = "ID of the created API Gateway"
  value       = aws_apigatewayv2_api.http_api.id
}
