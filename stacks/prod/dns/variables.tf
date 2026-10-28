variable "aws_region" {
  description = "AWS region for this stack"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name, used as a prefix for resource names and tags"
  type        = string
  default     = "hackathon"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "prod"
}

variable "domain_name" {
  description = "Apex domain name (registered outside AWS, delegated to this hosted zone)"
  type        = string
  default     = "4o4.com.br"
}

variable "dmarc_policy" {
  description = "DMARC policy applied to the domain (none, quarantine, reject)"
  type        = string
  default     = "quarantine"
}
