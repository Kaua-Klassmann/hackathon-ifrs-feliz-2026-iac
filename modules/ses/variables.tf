variable "domain_name" {
  description = "Domain to verify as a SES identity (e.g. example.com.br)"
  type        = string
}

variable "zone_id" {
  description = "Route53 hosted zone ID used for DKIM/SPF/DMARC records"
  type        = string
}

variable "dmarc_policy" {
  description = "DMARC policy applied to the domain (none, quarantine, reject)"
  type        = string
  default     = "quarantine"
}

variable "tags" {
  description = "Additional tags applied to the SES identity"
  type        = map(string)
  default     = {}
}
