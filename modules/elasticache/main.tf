resource "aws_elasticache_subnet_group" "this" {
  name       = var.name
  subnet_ids = var.subnet_ids
}

resource "aws_security_group" "this" {
  name        = "${var.name}-sg"
  description = "ElastiCache Valkey ${var.name}"
  vpc_id      = var.vpc_id

  tags = var.tags
}

resource "aws_elasticache_replication_group" "this" {
  replication_group_id = var.name
  description          = "${var.name} valkey replication group"

  engine         = "valkey"
  engine_version = var.engine_version
  node_type      = var.node_type
  port           = 6379

  num_cache_clusters         = var.multi_az ? 2 : 1
  automatic_failover_enabled = var.multi_az
  multi_az_enabled           = var.multi_az

  parameter_group_name = "default.valkey${split(".", var.engine_version)[0]}"
  subnet_group_name    = aws_elasticache_subnet_group.this.name
  security_group_ids   = [aws_security_group.this.id]

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true

  tags = var.tags
}

locals {
  monitored_nodes = var.sns_topic_arn != null ? (var.multi_az ? 2 : 1) : 0
}

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  count = local.monitored_nodes

  alarm_name          = "${var.name}-00${count.index + 1}-cpu-high"
  alarm_description   = "ElastiCache node CPU above 75% sustained"
  namespace           = "AWS/ElastiCache"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  comparison_operator = "GreaterThanThreshold"
  threshold           = 75

  dimensions = {
    CacheClusterId = "${var.name}-00${count.index + 1}"
  }

  alarm_actions = [var.sns_topic_arn]
  ok_actions    = [var.sns_topic_arn]
  tags          = var.tags
}

resource "aws_cloudwatch_metric_alarm" "evictions" {
  count = local.monitored_nodes

  alarm_name          = "${var.name}-00${count.index + 1}-evictions"
  alarm_description   = "ElastiCache evicting keys — sign of undersized cache or TTLs too long"
  namespace           = "AWS/ElastiCache"
  metric_name         = "Evictions"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0

  dimensions = {
    CacheClusterId = "${var.name}-00${count.index + 1}"
  }

  alarm_actions = [var.sns_topic_arn]
  ok_actions    = [var.sns_topic_arn]
  tags          = var.tags
}
