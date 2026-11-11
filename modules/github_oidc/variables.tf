variable "environment" {
  type = string
}

variable "github_repo" {
  description = "GitHub repository as owner/name"
  type        = string
}

variable "github_sub_prefix" {
  description = "Immutable GitHub OIDC subject prefix, repo:owner@id/name@id"
  type        = string
}

variable "create_oidc_provider" {
  description = "Set to false if the account already has the GitHub OIDC provider"
  type        = bool
  default     = true
}

variable "state_bucket" {
  description = "S3 bucket holding Terraform state"
  type        = string
}
