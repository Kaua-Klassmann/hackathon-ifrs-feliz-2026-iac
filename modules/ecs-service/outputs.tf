output "cluster_id" {
  value = aws_ecs_cluster.this.id
}

output "cluster_name" {
  value = aws_ecs_cluster.this.name
}

output "service_name" {
  value = aws_ecs_service.this.name
}

output "security_group_id" {
  value = aws_security_group.this.id
}

output "execution_role_arn" {
  value = aws_iam_role.execution.arn
}

output "task_role_arn" {
  value = aws_iam_role.task.arn
}

output "alarm_names" {
  description = "Names of the alarms created here (empty unless sns_topic_arn was set) — for wiring into CodeDeploy's alarm_configuration"
  value = concat(
    aws_cloudwatch_metric_alarm.running_tasks_low[*].alarm_name,
    aws_cloudwatch_metric_alarm.cpu_high[*].alarm_name,
  )
}
