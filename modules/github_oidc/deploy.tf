data "aws_caller_identity" "current" {}

locals {
  account_id      = data.aws_caller_identity.current.account_id
  basic_logs_arn  = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role_management = ["iam:CreateRole", "iam:DeleteRole", "iam:UpdateRole", "iam:UpdateAssumeRolePolicy", "iam:TagRole", "iam:UntagRole", "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:PassRole"]
}

# Canary stage: runs automatically on merge, can only touch fleet-canary-* resources.
resource "aws_iam_role" "deploy_canary" {
  name = "github-actions-deploy-canary-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = local.oidc_provider_arn }
      Condition = {
        StringEquals = { "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com" }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = [
            "${var.github_sub_prefix}:environment:canary",
            "repo:${var.github_repo}:environment:canary"
          ]
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "deploy_canary_read" {
  role       = aws_iam_role.deploy_canary.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_role_policy" "deploy_canary_write" {
  name = "canary-write"
  role = aws_iam_role.deploy_canary.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "StateFile"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "arn:aws:s3:::${var.state_bucket}/*"
      },
      {
        Sid      = "StateBucket"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = "arn:aws:s3:::${var.state_bucket}"
      },
      {
        Sid      = "CanaryFunctions"
        Effect   = "Allow"
        Action   = "lambda:*"
        Resource = "arn:aws:lambda:*:${local.account_id}:function:fleet-canary-*"
      },
      {
        Sid      = "CanaryRoles"
        Effect   = "Allow"
        Action   = local.role_management
        Resource = "arn:aws:iam::${local.account_id}:role/fleet-canary-*"
      },
      {
        Sid       = "CanaryRolesBasicLogsOnly"
        Effect    = "Allow"
        Action    = ["iam:AttachRolePolicy", "iam:DetachRolePolicy"]
        Resource  = "arn:aws:iam::${local.account_id}:role/fleet-canary-*"
        Condition = { ArnEquals = { "iam:PolicyARN" = local.basic_logs_arn } }
      }
    ]
  })
}

# Production stage: only runs after manual approval in the "production" environment.
# It cannot modify github-actions-* roles, so it can never raise its own permissions.
resource "aws_iam_role" "deploy_production" {
  name = "github-actions-deploy-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = local.oidc_provider_arn }
      Condition = {
        StringEquals = { "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com" }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = [
            "${var.github_sub_prefix}:environment:production",
            "repo:${var.github_repo}:environment:production"
          ]
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "deploy_production_power" {
  role       = aws_iam_role.deploy_production.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

resource "aws_iam_role_policy" "deploy_production_iam" {
  name = "app-roles-only"
  role = aws_iam_role.deploy_production.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadIam"
        Effect   = "Allow"
        Action   = ["iam:Get*", "iam:List*"]
        Resource = "*"
      },
      {
        Sid    = "ManageAppRoles"
        Effect = "Allow"
        Action = local.role_management
        Resource = [
          "arn:aws:iam::${local.account_id}:role/cloudops-*",
          "arn:aws:iam::${local.account_id}:role/fleet-*"
        ]
      },
      {
        Sid    = "AppRolesBasicLogsOnly"
        Effect = "Allow"
        Action = ["iam:AttachRolePolicy", "iam:DetachRolePolicy"]
        Resource = [
          "arn:aws:iam::${local.account_id}:role/cloudops-*",
          "arn:aws:iam::${local.account_id}:role/fleet-*"
        ]
        Condition = { ArnEquals = { "iam:PolicyARN" = local.basic_logs_arn } }
      }
    ]
  })
}
