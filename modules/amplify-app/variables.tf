variable "name" {
  type = string
}

variable "repository" {
  description = "GitHub repository URL (e.g. https://github.com/org/hackathon-web)"
  type        = string
}

variable "access_token" {
  description = "Classic GitHub personal access token (scopes: repo, admin:repo_hook). Required by aws_amplify_app; GitHub App tokens are not supported (hashicorp/terraform-provider-aws#36071)."
  type        = string
  sensitive   = true
}

variable "branch_name" {
  type    = string
  default = "main"
}

variable "stage" {
  description = "Amplify branch stage (PRODUCTION, BETA, DEVELOPMENT, ...)"
  type        = string
  default     = "PRODUCTION"
}

variable "zone_domain" {
  description = "Route53 hosted zone domain the subdomain belongs to (e.g. dev.4o4.com.br)"
  type        = string
}

variable "subdomain_prefix" {
  description = "Prefix under zone_domain, e.g. \"app\" for app.<zone_domain>"
  type        = string
  default     = "app"
}

variable "environment_variables" {
  type    = map(string)
  default = {}
}

variable "tags" {
  type    = map(string)
  default = {}
}
