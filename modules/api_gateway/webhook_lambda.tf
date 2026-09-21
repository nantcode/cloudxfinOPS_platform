# Zip up Python code dynamically
data "archive_file" "webhook_lambda_zip" {
  type        = "zip"
  source_dir  = "${path.root}/../src/github_webhook"
  output_path = "${path.module}/../../build/github_webhook.zip"
}

# Lambda function definition
resource "aws_lambda_function" "github_webhook" {
  filename         = data.archive_file.webhook_lambda_zip.output_path
  function_name    = "cloudops-github-webhook-${var.environment}"
  role             = var.lambda_exec_role_arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.11"
  source_code_hash = data.archive_file.webhook_lambda_zip.output_base64sha256

  environment {
    variables = {
      ENVIRONMENT                   = var.environment
      GITHUB_WEBHOOK_SECRET_PARAM   = "/cloudops/github/webhook_secret"
    }
  }
}

# API Gateway Integration with Lambda
resource "aws_apigatewayv2_integration" "webhook" {
  api_id                 = aws_apigatewayv2_api.http_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.github_webhook.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "webhook" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "POST /webhooks/github"
  target    = "integrations/${aws_apigatewayv2_integration.webhook.id}"
}

# Permission allowing API Gateway to trigger Lambda
resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.github_webhook.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}