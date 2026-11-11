output "plan_role_arn" {
  value = aws_iam_role.plan.arn
}

output "deploy_canary_role_arn" {
  value = aws_iam_role.deploy_canary.arn
}

output "deploy_production_role_arn" {
  value = aws_iam_role.deploy_production.arn
}
