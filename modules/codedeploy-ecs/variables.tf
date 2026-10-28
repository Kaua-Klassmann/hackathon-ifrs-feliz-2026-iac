variable "cluster_name" {
  type = string
}

variable "service_name" {
  type = string
}

variable "execution_role_arn" {
  type = string
}

variable "task_role_arn" {
  type = string
}

variable "prod_listener_arn" {
  description = "ALB listener ARN CodeDeploy flips between the blue and green target groups"
  type        = string
}

variable "blue_target_group_name" {
  type = string
}

variable "green_target_group_name" {
  type = string
}

variable "deployment_config_name" {
  description = "AWS-managed CodeDeploy config controlling traffic shifting speed (e.g. CodeDeployDefault.ECSCanary10Percent5Minutes, CodeDeployDefault.ECSAllAtOnce)"
  type        = string
  default     = "CodeDeployDefault.ECSAllAtOnce"
}

variable "termination_wait_time_in_minutes" {
  description = "How long the old (blue) task set stays running after a successful cutover, as a manual-rollback safety window"
  type        = number
  default     = 10
}

variable "alarm_names" {
  description = "CloudWatch alarm names that trigger automatic rollback if they fire during a deployment"
  type        = list(string)
  default     = []
}

variable "tags" {
  type    = map(string)
  default = {}
}
