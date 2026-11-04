output "table_name" {
  value = aws_dynamodb_table.audit_log.name
}

output "table_arn" {
  value = aws_dynamodb_table.audit_log.arn
}
