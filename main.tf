module "dynamodb" {
  source      = "./modules/dynamodb"
  environment = var.environment
}

module "iam" {
  source      = "./modules/iam"
  environment = var.environment
}

module "api_gateway" {
  source               = "./modules/api_gateway"
  environment          = var.environment
  lambda_exec_role_arn = module.iam.lambda_exec_role_arn
}