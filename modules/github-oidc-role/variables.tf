variable "name" {
  type = string
}

variable "oidc_provider_arn" {
  type = string
}

variable "github_org" {
  type = string
}

variable "github_org_id" {
  description = "Numeric GitHub organization ID (immutable subject claim format, opted in via the OIDC customization API)"
  type        = number
}

variable "github_repo" {
  type = string
}

variable "github_repo_id" {
  description = "Numeric GitHub repository ID (immutable subject claim format, opted in via the OIDC customization API)"
  type        = number
}

variable "github_environment" {
  description = <<-EOT
    GitHub Environment name this role trusts. Workflow jobs assuming this role must declare
    a matching `environment:` key — doing so changes the OIDC sub claim from
    `...:ref:refs/heads/<branch>` to `...:environment:<name>`, which is what this condition
    matches against (see GitHub's OIDC reference docs on environment-scoped subject claims:
    https://docs.github.com/en/actions/reference/security/oidc).
  EOT
  type        = string
}

variable "policy_json" {
  description = "IAM policy document (JSON) granted to this role"
  type        = string
}

variable "permissions_boundary_arn" {
  description = "Optional IAM permissions boundary ARN — caps what this role can ever do regardless of its own policy"
  type        = string
  default     = null
}

variable "tags" {
  type    = map(string)
  default = {}
}
