resource "aws_security_group" "this" {
  name        = "${var.name}-sg"
  description = "ALB ${var.name}"
  vpc_id      = var.vpc_id

  tags = var.tags
}

resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.this.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "https" {
  security_group_id = aws_security_group.this.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.this.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_lb" "this" {
  name               = var.name
  internal           = false
  load_balancer_type = "application"
  subnets            = var.public_subnet_ids
  security_groups    = [aws_security_group.this.id]

  enable_deletion_protection = var.enable_deletion_protection

  drop_invalid_header_fields = true

  tags = var.tags
}

locals {
  target_group_health_check = {
    path                = var.health_check_path
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
    matcher             = "200"
  }
}

resource "aws_lb_target_group" "blue" {
  name        = "${var.name}-tg-blue"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = local.target_group_health_check.path
    healthy_threshold   = local.target_group_health_check.healthy_threshold
    unhealthy_threshold = local.target_group_health_check.unhealthy_threshold
    interval            = local.target_group_health_check.interval
    timeout             = local.target_group_health_check.timeout
    matcher             = local.target_group_health_check.matcher
  }

  tags = var.tags
}

resource "aws_lb_target_group" "green" {
  name        = "${var.name}-tg-green"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = local.target_group_health_check.path
    healthy_threshold   = local.target_group_health_check.healthy_threshold
    unhealthy_threshold = local.target_group_health_check.unhealthy_threshold
    interval            = local.target_group_health_check.interval
    timeout             = local.target_group_health_check.timeout
    matcher             = local.target_group_health_check.matcher
  }

  tags = var.tags
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blue.arn
  }

  lifecycle {
    ignore_changes = [default_action]
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "error_rate_high" {
  count = var.sns_topic_arn != null ? 1 : 0

  alarm_name          = "${var.name}-5xx-error-rate-high"
  alarm_description   = "Target 5xx rate above 5% of requests over 5 minutes"
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = 5
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "error_rate"
    expression  = "(errors / requests) * 100"
    label       = "5xx error rate (%)"
    return_data = true
  }

  metric_query {
    id = "errors"

    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "HTTPCode_Target_5XX_Count"
      period      = 300
      stat        = "Sum"

      dimensions = {
        LoadBalancer = aws_lb.this.arn_suffix
      }
    }
  }

  metric_query {
    id = "requests"

    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "RequestCount"
      period      = 300
      stat        = "Sum"

      dimensions = {
        LoadBalancer = aws_lb.this.arn_suffix
      }
    }
  }

  alarm_actions = [var.sns_topic_arn]
  ok_actions    = [var.sns_topic_arn]
  tags          = var.tags
}

resource "aws_cloudwatch_metric_alarm" "latency_p99_high" {
  count = var.sns_topic_arn != null ? 1 : 0

  alarm_name          = "${var.name}-latency-p99-high"
  alarm_description   = "Target response time p99 above 1s for 5 minutes (whichever of blue/green is live)"
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = 1
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "latency"
    expression  = "MAX([blue, green])"
    label       = "TargetResponseTime p99"
    return_data = true
  }

  metric_query {
    id = "blue"

    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "TargetResponseTime"
      period      = 300
      stat        = "p99"

      dimensions = {
        LoadBalancer = aws_lb.this.arn_suffix
        TargetGroup  = aws_lb_target_group.blue.arn_suffix
      }
    }
  }

  metric_query {
    id = "green"

    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "TargetResponseTime"
      period      = 300
      stat        = "p99"

      dimensions = {
        LoadBalancer = aws_lb.this.arn_suffix
        TargetGroup  = aws_lb_target_group.green.arn_suffix
      }
    }
  }

  alarm_actions = [var.sns_topic_arn]
  ok_actions    = [var.sns_topic_arn]
  tags          = var.tags
}

resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  count = var.sns_topic_arn != null ? 1 : 0

  alarm_name          = "${var.name}-unhealthy-hosts"
  alarm_description   = "One or more targets failing health checks (whichever of blue/green is live)"
  evaluation_periods  = 2
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "unhealthy"
    expression  = "MAX([blue, green])"
    label       = "UnHealthyHostCount"
    return_data = true
  }

  metric_query {
    id = "blue"

    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "UnHealthyHostCount"
      period      = 60
      stat        = "Maximum"

      dimensions = {
        LoadBalancer = aws_lb.this.arn_suffix
        TargetGroup  = aws_lb_target_group.blue.arn_suffix
      }
    }
  }

  metric_query {
    id = "green"

    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "UnHealthyHostCount"
      period      = 60
      stat        = "Maximum"

      dimensions = {
        LoadBalancer = aws_lb.this.arn_suffix
        TargetGroup  = aws_lb_target_group.green.arn_suffix
      }
    }
  }

  alarm_actions = [var.sns_topic_arn]
  ok_actions    = [var.sns_topic_arn]
  tags          = var.tags
}
