variable "name" {
  description = "Name prefix applied to all resources created by this module"
  type        = string
}

variable "cidr_block" {
  description = "CIDR block for the VPC. Subnets are carved with cidrsubnet(cidr, 8, ...), so a /16 yields the intended /24s per tier — smaller VPC CIDRs yield proportionally smaller subnets"
  type        = string
}

variable "az_count" {
  description = "Number of Availability Zones to spread subnets across"
  type        = number
  default     = 2
}

variable "single_nat_gateway" {
  description = "Use a single NAT Gateway shared by all private subnets instead of one per AZ"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags applied to all resources created by this module"
  type        = map(string)
  default     = {}
}
