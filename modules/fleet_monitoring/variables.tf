variable "exclude_functions" {
  description = "Lambda function names in the region that should not be monitored"
  type        = list(string)
  default     = []
}
