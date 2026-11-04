variable "environment" {
  type = string
}

variable "audit_table_arn" {
  description = "ARN of the DynamoDB audit table the Lambda writes to"
  type        = string
}
