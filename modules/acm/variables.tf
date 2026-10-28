variable "domain_name" {
  description = "Apex domain name; the certificate covers this and *.domain_name"
  type        = string
}

variable "zone_id" {
  description = "Route53 hosted zone ID used for DNS validation records"
  type        = string
}

variable "tags" {
  description = "Additional tags applied to the certificate"
  type        = map(string)
  default     = {}
}
