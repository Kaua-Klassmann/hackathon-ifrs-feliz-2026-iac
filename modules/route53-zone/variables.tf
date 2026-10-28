variable "domain_name" {
  description = "Apex domain name for the hosted zone (e.g. example.com.br)"
  type        = string
}

variable "tags" {
  description = "Additional tags applied to the hosted zone"
  type        = map(string)
  default     = {}
}
