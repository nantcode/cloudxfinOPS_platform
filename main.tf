module "dynamodb" {
  source      = "./modules/dynamodb"
  environment = var.environment
}

module "iam" {
  source          = "./modules/iam"
  environment     = var.environment
  audit_table_arn = module.dynamodb.table_arn
}

module "api_gateway" {
  source               = "./modules/api_gateway"
  environment          = var.environment
  lambda_exec_role_arn = module.iam.lambda_exec_role_arn
  audit_table_name     = module.dynamodb.table_name
}

module "github_oidc" {
  source               = "./modules/github_oidc"
  environment          = var.environment
  github_repo          = "nantcode/cloudxfinOPS_platform"
  github_sub_prefix    = "repo:nantcode@306319471/cloudxfinOPS_platform@1377934094"
  create_oidc_provider = true
}

module "fleet_monitoring" {
  source           = "./modules/fleet_monitoring"
  discord_zip_path = data.archive_file.discord_forwarder.output_path
  discord_zip_hash = data.archive_file.discord_forwarder.output_base64sha256
  providers = {
    aws = aws.bots
  }
}

data "archive_file" "discord_forwarder" {
  type        = "zip"
  source_dir  = "${path.root}/src/discord_forwarder"
  output_path = "${path.root}/build/discord_forwarder.zip"
}
