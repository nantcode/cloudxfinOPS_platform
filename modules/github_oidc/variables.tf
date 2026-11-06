variable "environment" {
  type = string
}

variable "github_sub_prefix" {
  description = "GitHub OIDC subject prefix for the repo, e.g. repo:owner@id/name@id"
  type        = string
}

variable "create_oidc_provider" {
  description = "Set to false if the account already has the GitHub OIDC provider"
  type        = bool
  default     = true
}
