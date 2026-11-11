terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

resource "aws_iam_role" "canary" {
  name = "fleet-canary-bot"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "canary_logs" {
  role       = aws_iam_role.canary.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "canary" {
  function_name    = "fleet-canary-bot"
  role             = aws_iam_role.canary.arn
  handler          = "lambda_function.handler"
  runtime          = "python3.12"
  timeout          = 10
  filename         = var.zip_path
  source_code_hash = var.zip_hash

  environment {
    variables = {
      MODE = "paper"
    }
  }

  depends_on = [aws_iam_role_policy_attachment.canary_logs]
}
