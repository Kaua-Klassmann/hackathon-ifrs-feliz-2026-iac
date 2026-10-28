variable "name" {
  type = string
}

variable "force_delete" {
  description = "Allow terraform destroy to delete the repository even with images in it"
  type        = bool
  default     = false
}

variable "tags" {
  type    = map(string)
  default = {}
}
