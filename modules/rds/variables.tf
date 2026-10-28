variable "name" {
  description = "Name/identifier prefix for the RDS instance and related resources"
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  description = "Isolated subnet IDs for the DB subnet group"
  type        = list(string)
}

variable "instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "engine_version" {
  description = "PostgreSQL major version"
  type        = string
  default     = "17"
}

variable "allocated_storage" {
  type    = number
  default = 20
}

variable "max_allocated_storage" {
  description = "Ceiling for RDS storage autoscaling (0 disables it)"
  type        = number
  default     = 50
}

variable "db_name" {
  type = string
}

variable "master_username" {
  type    = string
  default = "appuser"
}

variable "backup_retention_period" {
  type    = number
  default = 7
}

variable "multi_az" {
  type    = bool
  default = false
}

variable "deletion_protection" {
  type    = bool
  default = false
}

variable "auto_minor_version_upgrade" {
  description = "Whether minor engine version upgrades are applied automatically during the maintenance window. Kept off by default so upgrades are a deliberate, tested change instead of a surprise restart."
  type        = bool
  default     = false
}

variable "maintenance_window" {
  description = "Preferred weekly window (UTC, format ddd:hh24:mi-ddd:hh24:mi) for RDS-initiated maintenance"
  type        = string
  default     = "sun:05:00-sun:06:00"
}

variable "performance_insights_enabled" {
  description = "Enables Performance Insights (7-day retention, no extra cost at that retention)"
  type        = bool
  default     = true
}

variable "sns_topic_arn" {
  description = "SNS topic ARN for alarm notifications and RDS event subscription. Null disables both."
  type        = string
  default     = null
}

variable "connections_alarm_threshold" {
  description = "DatabaseConnections count that triggers the connections-high alarm. Default is ~80% of db.t4g.micro's connection ceiling — adjust if instance_class changes."
  type        = number
  default     = 90
}

variable "tags" {
  type    = map(string)
  default = {}
}
