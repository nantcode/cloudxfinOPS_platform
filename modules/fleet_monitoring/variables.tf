variable "exclude_functions" {
  description = "Lambda function names in the region that should not be monitored"
  type        = list(string)
  default     = []
}

variable "discord_zip_path" {
  type = string
}

variable "discord_zip_hash" {
  type = string
}
