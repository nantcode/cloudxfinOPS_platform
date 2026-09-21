resource "aws_dynamodb_table" "audit_log" {
  name         = "cloudops-audit-log-${var.environment}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "eventId"

  attribute {
    name = "eventId"
    type = "S"
  }

  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}
