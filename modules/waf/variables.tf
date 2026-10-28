variable "name" {
  type = string
}

variable "scope" {
  description = "REGIONAL (ALB) or CLOUDFRONT (CloudFront/Amplify — must be created in us-east-1)"
  type        = string

  validation {
    condition     = contains(["REGIONAL", "CLOUDFRONT"], var.scope)
    error_message = "scope must be REGIONAL or CLOUDFRONT"
  }
}

variable "rate_limit_per_ip" {
  type    = number
  default = 2000
}

variable "enable_logging" {
  description = "Log blocked/counted requests to a CloudWatch log group (aws-waf-logs-<name>)"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  type    = number
  default = 30
}

variable "tags" {
  type    = map(string)
  default = {}
}
