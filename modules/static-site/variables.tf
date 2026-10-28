variable "name" {
  description = "Name prefix, also used as the S3 bucket name (must be globally unique)"
  type        = string
}

variable "domain_name" {
  description = "Domain the site is served on (e.g. 4o4.com.br or dev.4o4.com.br)"
  type        = string
}

variable "certificate_arn" {
  description = "ACM certificate ARN, must be issued in us-east-1 (CloudFront requirement)"
  type        = string
}

variable "zone_id" {
  description = "Route53 hosted zone ID for the alias record"
  type        = string
}

variable "web_acl_arn" {
  description = "ARN of a CLOUDFRONT-scope WAFv2 Web ACL to attach to the distribution. Null skips it."
  type        = string
  default     = null
}

variable "tags" {
  type    = map(string)
  default = {}
}
