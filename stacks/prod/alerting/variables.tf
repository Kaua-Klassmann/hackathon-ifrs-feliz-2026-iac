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

variable "alert_email" {
  description = "Email address that receives alarm notifications. AWS sends a confirmation email after apply — someone needs to click \"Confirm subscription\" before alerts actually deliver. No default on purpose; pass via a local .tfvars (gitignored) or -var."
  type        = string
}
