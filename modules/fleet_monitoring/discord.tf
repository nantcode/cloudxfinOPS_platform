data "aws_caller_identity" "current" {}

resource "aws_iam_role" "discord" {
  name = "fleet-discord-alerts"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "discord_logs" {
  role       = aws_iam_role.discord.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "discord_ssm" {
  name = "read-discord-webhook"
  role = aws_iam_role.discord.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "ssm:GetParameter"
      Resource = "arn:aws:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:parameter/fleet/discord_webhook_url"
    }]
  })
}

resource "aws_lambda_function" "discord" {
  function_name    = "fleet-discord-alerts"
  role             = aws_iam_role.discord.arn
  handler          = "lambda_function.handler"
  runtime          = "python3.12"
  timeout          = 10
  filename         = var.discord_zip_path
  source_code_hash = var.discord_zip_hash

  environment {
    variables = {
      DISCORD_WEBHOOK_PARAM = "/fleet/discord_webhook_url"
    }
  }
}

resource "aws_lambda_permission" "discord_sns" {
  statement_id  = "AllowFleetAlertsTopic"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.discord.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.alerts.arn
}

resource "aws_sns_topic_subscription" "discord" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.discord.arn
}
