variable "environment" {
  description = "Target environment (dev, staging, prod)"
  type        = string
}

variable "lambda_exec_role_arn" {
  description = "ARN of the IAM execution role for Lambda functions"
  type        = string
}
