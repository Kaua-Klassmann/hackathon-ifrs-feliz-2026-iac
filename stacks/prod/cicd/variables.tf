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

variable "github_org" {
  type    = string
  default = "4oquatro"
}

# Numeric GitHub org/repo IDs, required by the immutable OIDC subject claim format
# (opted into on all 3 repos via PUT /repos/{owner}/{repo}/actions/oidc/customization/sub).
variable "github_org_id" {
  type    = number
  default = 299864787
}

variable "iac_repo" {
  type    = string
  default = "hackathon-iac"
}

variable "iac_repo_id" {
  type    = number
  default = 1289280104
}

variable "api_repo" {
  type    = string
  default = "hackathon-api"
}

variable "api_repo_id" {
  type    = number
  default = 1289279257
}

variable "landing_repo" {
  type    = string
  default = "hackathon-landing"
}

variable "landing_repo_id" {
  type    = number
  default = 1317505276
}
