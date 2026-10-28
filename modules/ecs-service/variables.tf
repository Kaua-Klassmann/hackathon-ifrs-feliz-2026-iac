variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "alb_security_group_id" {
  type = string
}

variable "target_group_arn" {
  type = string
}

variable "container_image" {
  type = string
}

variable "container_port" {
  type    = number
  default = 8080
}

variable "cpu" {
  type    = number
  default = 512
}

variable "memory" {
  type    = number
  default = 1024
}

variable "desired_count" {
  type    = number
  default = 1
}

variable "log_retention_days" {
  type    = number
  default = 30
}

variable "environment" {
  description = "Plain (non-secret) container environment variables"
  type        = list(object({ name = string, value = string }))
  default     = []
}

variable "secrets" {
  description = "Container secrets sourced from Secrets Manager or SSM Parameter Store"
  type        = list(object({ name = string, valueFrom = string }))
  default     = []
}

variable "execution_role_extra_secret_arns" {
  description = "Secrets Manager secret ARNs the task execution role may read to resolve container secrets"
  type        = list(string)
  default     = []
}

variable "execution_role_extra_ssm_arns" {
  description = "SSM Parameter Store ARNs the task execution role may read to resolve container secrets"
  type        = list(string)
  default     = []
}

variable "rds_security_group_id" {
  type    = string
  default = null
}

variable "rds_port" {
  type    = number
  default = 5432
}

variable "redis_security_group_id" {
  type    = string
  default = null
}

variable "redis_port" {
  type    = number
  default = 6379
}

variable "task_role_policy_json" {
  description = "IAM policy document (JSON) granted to the task role, for permissions the app needs at runtime (e.g. ses:SendEmail). Null attaches nothing."
  type        = string
  default     = null
}

variable "enable_autoscaling" {
  type    = bool
  default = false
}

variable "min_capacity" {
  type    = number
  default = 1
}

variable "max_capacity" {
  type    = number
  default = 1
}

variable "cpu_target_value" {
  type    = number
  default = 70
}

variable "scale_in_cooldown" {
  type    = number
  default = 300
}

variable "scale_out_cooldown" {
  type    = number
  default = 60
}

variable "container_insights" {
  description = "Enables ECS Container Insights (needed for the RunningTaskCount alarm; small additional CloudWatch cost)"
  type        = bool
  default     = true
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
