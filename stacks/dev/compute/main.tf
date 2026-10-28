data "terraform_remote_state" "networking" {
  backend = "s3"
  config = {
    bucket = "4o4-hackathon-tfstate"
    key    = "dev/networking/terraform.tfstate"
    region = "us-east-1"
  }
}

data "terraform_remote_state" "dns" {
  backend = "s3"
  config = {
    bucket = "4o4-hackathon-tfstate"
    key    = "dev/dns/terraform.tfstate"
    region = "us-east-1"
  }
}

data "terraform_remote_state" "data_layer" {
  backend = "s3"
  config = {
    bucket = "4o4-hackathon-tfstate"
    key    = "dev/data/terraform.tfstate"
    region = "us-east-1"
  }
}

data "terraform_remote_state" "shared_ecr" {
  backend = "s3"
  config = {
    bucket = "4o4-hackathon-tfstate"
    key    = "shared/ecr/terraform.tfstate"
    region = "us-east-1"
  }
}

data "terraform_remote_state" "alerting" {
  backend = "s3"
  config = {
    bucket = "4o4-hackathon-tfstate"
    key    = "dev/alerting/terraform.tfstate"
    region = "us-east-1"
  }
}

module "alb" {
  source = "../../../modules/alb"

  name              = "${var.project}-${var.environment}-alb"
  vpc_id            = data.terraform_remote_state.networking.outputs.vpc_id
  public_subnet_ids = data.terraform_remote_state.networking.outputs.public_subnets
  certificate_arn   = data.terraform_remote_state.dns.outputs.acm_certificate_arn
  container_port    = var.container_port
  health_check_path = var.health_check_path

  sns_topic_arn = data.terraform_remote_state.alerting.outputs.sns_topic_arn

  tags = {
    Environment = var.environment
    Project     = var.project
  }
}

data "aws_iam_policy_document" "task" {
  statement {
    sid       = "SendEmail"
    effect    = "Allow"
    actions   = ["ses:SendEmail", "ses:SendRawEmail"]
    resources = [data.terraform_remote_state.dns.outputs.ses_identity_arn]
  }
}

module "ecs" {
  source = "../../../modules/ecs-service"

  name                  = "${var.project}-${var.environment}-api"
  vpc_id                = data.terraform_remote_state.networking.outputs.vpc_id
  private_subnet_ids    = data.terraform_remote_state.networking.outputs.private_subnets
  alb_security_group_id = module.alb.security_group_id
  target_group_arn      = module.alb.target_group_arn

  container_image = "${data.terraform_remote_state.shared_ecr.outputs.repository_url}:${var.image_tag}"
  container_port  = var.container_port
  cpu             = var.cpu
  memory          = var.memory
  desired_count   = var.desired_count

  enable_autoscaling = var.enable_autoscaling
  min_capacity       = var.min_capacity
  max_capacity       = var.max_capacity
  cpu_target_value   = var.cpu_target_value

  rds_security_group_id   = data.terraform_remote_state.data_layer.outputs.rds_security_group_id
  redis_security_group_id = data.terraform_remote_state.data_layer.outputs.redis_security_group_id

  environment = [
    { name = "DB_HOST", value = data.terraform_remote_state.data_layer.outputs.rds_endpoint },
    { name = "DB_PORT", value = tostring(data.terraform_remote_state.data_layer.outputs.rds_port) },
    { name = "DB_NAME", value = data.terraform_remote_state.data_layer.outputs.rds_db_name },
    { name = "DB_USER", value = data.terraform_remote_state.data_layer.outputs.rds_master_username },
    { name = "DB_SSL_MODE", value = "require" },
    { name = "REDIS_HOST", value = data.terraform_remote_state.data_layer.outputs.redis_endpoint },
    { name = "REDIS_PORT", value = tostring(data.terraform_remote_state.data_layer.outputs.redis_port) },
    { name = "AWS_REGION", value = var.aws_region },
    { name = "SES_FROM_DOMAIN", value = data.terraform_remote_state.dns.outputs.domain_name },
    { name = "APP_PORT", value = tostring(var.container_port) },
    { name = "CORS_ORIGIN", value = "https://app.${data.terraform_remote_state.dns.outputs.domain_name}" },
    { name = "APP_PAYLOAD_MAX_SIZE_IN_MB", value = tostring(var.app_payload_max_size_mb) },
    { name = "DATABASE_SCHEMA", value = var.database_schema },
    { name = "DATABASE_MIN_CONNECTIONS", value = tostring(var.database_min_connections) },
    { name = "DATABASE_MAX_CONNECTIONS", value = tostring(var.database_max_connections) },
  ]

  task_role_policy_json = data.aws_iam_policy_document.task.json

  secrets = [
    {
      name      = "DB_PASSWORD"
      valueFrom = "${data.terraform_remote_state.data_layer.outputs.rds_master_user_secret_arn}:password::"
    }
  ]

  execution_role_extra_secret_arns = [
    data.terraform_remote_state.data_layer.outputs.rds_master_user_secret_arn
  ]

  sns_topic_arn = data.terraform_remote_state.alerting.outputs.sns_topic_arn

  tags = {
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_route53_record" "api" {
  zone_id = data.terraform_remote_state.dns.outputs.zone_id
  name    = "api.${data.terraform_remote_state.dns.outputs.domain_name}"
  type    = "A"

  alias {
    name                   = module.alb.dns_name
    zone_id                = module.alb.zone_id
    evaluate_target_health = true
  }
}

resource "aws_cloudwatch_dashboard" "this" {
  dashboard_name = "${var.project}-${var.environment}-overview"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 8, height = 6
        properties = {
          title  = "ALB — taxa de erro 5xx (%)"
          region = var.aws_region
          view   = "timeSeries"
          metrics = [
            [{ expression = "(errors / requests) * 100", label = "5xx rate (%)", id = "e1" }],
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", module.alb.arn_suffix, { id = "errors", visible = false, stat = "Sum" }],
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", module.alb.arn_suffix, { id = "requests", visible = false, stat = "Sum" }],
          ]
        }
      },
      {
        type = "metric", x = 8, y = 0, width = 8, height = 6
        properties = {
          title  = "ALB — latência p99 (blue vs green)"
          region = var.aws_region
          view   = "timeSeries"
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", module.alb.arn_suffix, "TargetGroup", module.alb.target_group_arn_suffix, { stat = "p99", label = "p99 blue" }],
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", module.alb.arn_suffix, "TargetGroup", module.alb.green_target_group_arn_suffix, { stat = "p99", label = "p99 green" }],
          ]
        }
      },
      {
        type = "metric", x = 16, y = 0, width = 8, height = 6
        properties = {
          title  = "ALB — hosts saudáveis vs total (blue + green)"
          region = var.aws_region
          view   = "timeSeries"
          metrics = [
            ["AWS/ApplicationELB", "HealthyHostCount", "LoadBalancer", module.alb.arn_suffix, "TargetGroup", module.alb.target_group_arn_suffix, { stat = "Minimum", label = "Healthy (blue)" }],
            ["AWS/ApplicationELB", "UnHealthyHostCount", "LoadBalancer", module.alb.arn_suffix, "TargetGroup", module.alb.target_group_arn_suffix, { stat = "Maximum", label = "Unhealthy (blue)" }],
            ["AWS/ApplicationELB", "HealthyHostCount", "LoadBalancer", module.alb.arn_suffix, "TargetGroup", module.alb.green_target_group_arn_suffix, { stat = "Minimum", label = "Healthy (green)" }],
            ["AWS/ApplicationELB", "UnHealthyHostCount", "LoadBalancer", module.alb.arn_suffix, "TargetGroup", module.alb.green_target_group_arn_suffix, { stat = "Maximum", label = "Unhealthy (green)" }],
          ]
        }
      },
      {
        type = "metric", x = 0, y = 6, width = 8, height = 6
        properties = {
          title  = "ECS — CPU (serviço)"
          region = var.aws_region
          view   = "timeSeries"
          metrics = [
            ["AWS/ECS", "CPUUtilization", "ClusterName", module.ecs.cluster_name, "ServiceName", module.ecs.service_name],
          ]
        }
      },
      {
        type = "metric", x = 8, y = 6, width = 8, height = 6
        properties = {
          title  = "ECS — memória (serviço)"
          region = var.aws_region
          view   = "timeSeries"
          metrics = [
            ["AWS/ECS", "MemoryUtilization", "ClusterName", module.ecs.cluster_name, "ServiceName", module.ecs.service_name],
          ]
        }
      },
      {
        type = "metric", x = 16, y = 6, width = 8, height = 6
        properties = {
          title  = "ECS — tasks rodando vs desejado"
          region = var.aws_region
          view   = "timeSeries"
          metrics = [
            ["ECS/ContainerInsights", "RunningTaskCount", "ClusterName", module.ecs.cluster_name, "ServiceName", module.ecs.service_name, { label = "Running" }],
            ["ECS/ContainerInsights", "DesiredTaskCount", "ClusterName", module.ecs.cluster_name, "ServiceName", module.ecs.service_name, { label = "Desired" }],
          ]
        }
      },
      {
        type = "metric", x = 0, y = 12, width = 6, height = 6
        properties = {
          title  = "RDS — CPU"
          region = var.aws_region
          view   = "timeSeries"
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", data.terraform_remote_state.data_layer.outputs.rds_identifier],
          ]
        }
      },
      {
        type = "metric", x = 6, y = 12, width = 6, height = 6
        properties = {
          title  = "RDS — espaço livre"
          region = var.aws_region
          view   = "timeSeries"
          metrics = [
            ["AWS/RDS", "FreeStorageSpace", "DBInstanceIdentifier", data.terraform_remote_state.data_layer.outputs.rds_identifier],
          ]
        }
      },
      {
        type = "metric", x = 12, y = 12, width = 6, height = 6
        properties = {
          title  = "RDS — conexões"
          region = var.aws_region
          view   = "timeSeries"
          metrics = [
            ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", data.terraform_remote_state.data_layer.outputs.rds_identifier],
          ]
        }
      },
      {
        type = "metric", x = 18, y = 12, width = 6, height = 6
        properties = {
          title  = "RDS — memória livre"
          region = var.aws_region
          view   = "timeSeries"
          metrics = [
            ["AWS/RDS", "FreeableMemory", "DBInstanceIdentifier", data.terraform_remote_state.data_layer.outputs.rds_identifier],
          ]
        }
      },
      {
        type = "metric", x = 0, y = 18, width = 12, height = 6
        properties = {
          title  = "ElastiCache — CPU"
          region = var.aws_region
          view   = "timeSeries"
          metrics = [
            ["AWS/ElastiCache", "CPUUtilization", "CacheClusterId", "${data.terraform_remote_state.data_layer.outputs.redis_replication_group_id}-001"],
          ]
        }
      },
      {
        type = "metric", x = 12, y = 18, width = 12, height = 6
        properties = {
          title  = "ElastiCache — evictions"
          region = var.aws_region
          view   = "timeSeries"
          metrics = [
            ["AWS/ElastiCache", "Evictions", "CacheClusterId", "${data.terraform_remote_state.data_layer.outputs.redis_replication_group_id}-001", { stat = "Sum" }],
          ]
        }
      },
    ]
  })
}

module "codedeploy" {
  source = "../../../modules/codedeploy-ecs"

  cluster_name      = module.ecs.cluster_name
  service_name      = module.ecs.service_name
  prod_listener_arn = module.alb.https_listener_arn

  execution_role_arn = module.ecs.execution_role_arn
  task_role_arn      = module.ecs.task_role_arn

  blue_target_group_name  = module.alb.blue_target_group_name
  green_target_group_name = module.alb.green_target_group_name

  deployment_config_name           = "CodeDeployDefault.ECSAllAtOnce"
  termination_wait_time_in_minutes = 10

  alarm_names = module.alb.alarm_names

  tags = {
    Environment = var.environment
    Project     = var.project
  }
}
