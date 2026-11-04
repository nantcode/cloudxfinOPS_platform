variable "environment" {
  type = string
}

variable "github_repo" {
  description = "GitHub repository allowed to assume the role, as owner/name"
  type        = string
}

variable "create_oidc_provider" {
  description = "Set to false if the account already has the GitHub OIDC provider"
  type        = bool
  default     = true
}
