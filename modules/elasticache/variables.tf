variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  description = "Isolated subnet IDs for the cache subnet group"
  type        = list(string)
}

variable "node_type" {
  type    = string
  default = "cache.t4g.micro"
}

variable "engine_version" {
  type    = string
  default = "8.0"
}

variable "multi_az" {
  description = "When true, runs 2 nodes with automatic failover instead of a single node"
  type        = bool
  default     = false
}

variable "sns_topic_arn" {
  description = "SNS topic ARN for alarm notifications. Null disables alarms."
  type        = string
  default     = null
}

variable "tags" {
  type    = map(string)
  default = {}
}
