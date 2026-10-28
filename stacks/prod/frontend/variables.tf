variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project" {
  type    = string
  default = "hackathon"
}

variable "environment" {
  type    = string
  default = "prod"
}

variable "github_repository" {
  description = "GitHub repository URL for the Next.js frontend"
  type        = string
  default     = "https://github.com/4oquatro/hackathon-web"
}

variable "github_access_token" {
  description = "Classic GitHub PAT (scopes: repo, admin:repo_hook) used by Amplify to connect to the repo. Supply via -var or an untracked terraform.tfvars, never commit it."
  type        = string
  sensitive   = true
}
