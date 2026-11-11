terraform {
  required_version = ">= 1.10"

  backend "s3" {
    bucket       = "nant-tfstate-319484642507"
    key          = "cloudxfinops/dev/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

provider "aws" {
  alias  = "bots"
  region = "us-east-2"
}
