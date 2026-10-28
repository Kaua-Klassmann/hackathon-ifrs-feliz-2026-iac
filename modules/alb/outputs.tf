output "arn" {
  value = aws_lb.this.arn
}

output "dns_name" {
  value = aws_lb.this.dns_name
}

output "zone_id" {
  value = aws_lb.this.zone_id
}

output "target_group_arn" {
  description = "Blue target group ARN — used as the ECS service's initial load_balancer target on first apply. CodeDeploy manages which one is live after that."
  value       = aws_lb_target_group.blue.arn
}

output "blue_target_group_name" {
  value = aws_lb_target_group.blue.name
}

output "green_target_group_name" {
  value = aws_lb_target_group.green.name
}

output "security_group_id" {
  value = aws_security_group.this.id
}

output "https_listener_arn" {
  value = aws_lb_listener.https.arn
}

output "arn_suffix" {
  value = aws_lb.this.arn_suffix
}

output "target_group_arn_suffix" {
  description = "Blue target group's ARN suffix — dashboard widgets use blue+green together, see modules/alb alarms for the pattern."
  value       = aws_lb_target_group.blue.arn_suffix
}

output "green_target_group_arn_suffix" {
  value = aws_lb_target_group.green.arn_suffix
}

output "alarm_names" {
  description = "Names of the alarms created here (empty unless sns_topic_arn was set) — for wiring into CodeDeploy's alarm_configuration"
  value = concat(
    aws_cloudwatch_metric_alarm.error_rate_high[*].alarm_name,
    aws_cloudwatch_metric_alarm.latency_p99_high[*].alarm_name,
    aws_cloudwatch_metric_alarm.unhealthy_hosts[*].alarm_name,
  )
}
