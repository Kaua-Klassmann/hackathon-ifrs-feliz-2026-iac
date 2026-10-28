data "aws_caller_identity" "current" {}

data "terraform_remote_state" "compute" {
  backend = "s3"
  config = {
    bucket = "4o4-hackathon-tfstate"
    key    = "dev/compute/terraform.tfstate"
    region = "us-east-1"
  }
}

data "terraform_remote_state" "frontend" {
  backend = "s3"
  config = {
    bucket = "4o4-hackathon-tfstate"
    key    = "dev/frontend/terraform.tfstate"
    region = "us-east-1"
  }
}

# The OIDC provider is account-wide (one per issuer URL) — it lives in its own stack so
# destroying dev or prod never touches it.
data "terraform_remote_state" "shared_oidc" {
  backend = "s3"
  config = {
    bucket = "4o4-hackathon-tfstate"
    key    = "shared/oidc/terraform.tfstate"
    region = "us-east-1"
  }
}

# Broad by necessity: this role runs `terraform apply` for every resource this
# project provisions. Scoped down via the OIDC trust condition (only this repo's
# main branch can assume it), not via resource-level IAM here.
data "aws_iam_policy_document" "iac" {
  statement {
    sid    = "IacDeploy"
    effect = "Allow"
    actions = [
      "ec2:*",
      "elasticloadbalancing:*",
      "ecs:*",
      "ecr:*",
      "rds:*",
      "elasticache:*",
      "route53:*",
      "acm:*",
      "ses:*",
      "sesv2:*",
      "s3:*",
      "cloudfront:*",
      "amplify:*",
      "secretsmanager:*",
      "ssm:*",
      "logs:*",
      "iam:*",
      "wafv2:*",
      "codedeploy:*",
      "cloudwatch:*",
      "sns:*",
      "application-autoscaling:*",
      "kms:DescribeKey",
      "sts:GetCallerIdentity",
    ]
    resources = ["*"]
  }
}

locals {
  iac_boundary_name = "${var.project}-${var.environment}-iac-boundary"
  iac_boundary_arn  = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/${local.iac_boundary_name}"
  iac_role_arn      = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.project}-${var.environment}-iac"
}

data "aws_iam_policy_document" "iac_boundary" {
  statement {
    sid       = "AllowEverythingByDefault"
    effect    = "Allow"
    actions   = ["*"]
    resources = ["*"]
  }

  statement {
    sid    = "DenyRemovingOwnBoundary"
    effect = "Deny"
    actions = [
      "iam:DeleteRolePermissionsBoundary",
      "iam:PutRolePermissionsBoundary",
    ]
    resources = [local.iac_role_arn]
  }

  statement {
    sid    = "DenyBoundaryPolicyTampering"
    effect = "Deny"
    actions = [
      "iam:DeletePolicy",
      "iam:DeletePolicyVersion",
      "iam:CreatePolicyVersion",
      "iam:SetDefaultPolicyVersion",
    ]
    resources = [local.iac_boundary_arn]
  }

  statement {
    sid    = "DenyIamUserCreation"
    effect = "Deny"
    actions = [
      "iam:CreateUser",
      "iam:CreateAccessKey",
      "iam:CreateLoginProfile",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "DenyAttachAdminPolicy"
    effect = "Deny"
    actions = [
      "iam:AttachUserPolicy",
      "iam:AttachRolePolicy",
      "iam:AttachGroupPolicy",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "iam:PolicyARN"
      values   = ["arn:aws:iam::aws:policy/AdministratorAccess"]
    }
  }

  statement {
    sid    = "DenyLoggingAndBillingTampering"
    effect = "Deny"
    actions = [
      "cloudtrail:StopLogging",
      "cloudtrail:DeleteTrail",
      "cloudtrail:UpdateTrail",
      "organizations:*",
      "account:*",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "iac_boundary" {
  name   = local.iac_boundary_name
  policy = data.aws_iam_policy_document.iac_boundary.json
}

module "iac_role" {
  source = "../../../modules/github-oidc-role"

  name               = "${var.project}-${var.environment}-iac"
  oidc_provider_arn  = data.terraform_remote_state.shared_oidc.outputs.oidc_provider_arn
  github_org         = var.github_org
  github_org_id      = var.github_org_id
  github_repo        = var.iac_repo
  github_repo_id     = var.iac_repo_id
  github_environment = var.environment
  policy_json        = data.aws_iam_policy_document.iac.json

  permissions_boundary_arn = aws_iam_policy.iac_boundary.arn

  tags = {
    Environment = var.environment
    Project     = var.project
  }
}

data "aws_iam_policy_document" "api" {
  statement {
    sid       = "EcrAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "EcrPushPull"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
    ]
    resources = [data.terraform_remote_state.compute.outputs.ecr_repository_arn]
  }

  statement {
    sid    = "EcsTaskDefinition"
    effect = "Allow"
    actions = [
      "ecs:DescribeTaskDefinition",
      "ecs:RegisterTaskDefinition",
      "ecs:TagResource",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "EcsService"
    effect = "Allow"
    actions = [
      "ecs:DescribeServices",
      "ecs:UpdateService",
    ]
    resources = [
      "arn:aws:ecs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:service/${data.terraform_remote_state.compute.outputs.ecs_cluster_name}/${data.terraform_remote_state.compute.outputs.ecs_service_name}",
    ]
  }

  statement {
    sid       = "EcsRunMigrationTask"
    effect    = "Allow"
    actions   = ["ecs:RunTask"]
    resources = ["arn:aws:ecs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:task-definition/${var.project}-${var.environment}-api*"]

    condition {
      test     = "ArnEquals"
      variable = "ecs:cluster"
      values   = ["arn:aws:ecs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:cluster/${data.terraform_remote_state.compute.outputs.ecs_cluster_name}"]
    }
  }

  statement {
    sid       = "EcsDescribeTasks"
    effect    = "Allow"
    actions   = ["ecs:DescribeTasks"]
    resources = ["arn:aws:ecs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:task/${data.terraform_remote_state.compute.outputs.ecs_cluster_name}/*"]
  }

  statement {
    sid       = "PassEcsRoles"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.project}-${var.environment}-api-*"]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }

  statement {
    sid    = "CodeDeployEcsBlueGreen"
    effect = "Allow"
    actions = [
      "codedeploy:CreateDeployment",
      "codedeploy:GetDeployment",
      "codedeploy:GetDeploymentGroup",
    ]
    resources = [
      "arn:aws:codedeploy:${var.aws_region}:${data.aws_caller_identity.current.account_id}:deploymentgroup:${data.terraform_remote_state.compute.outputs.codedeploy_application_name}/${data.terraform_remote_state.compute.outputs.codedeploy_deployment_group_name}",
    ]
  }

  statement {
    sid       = "CodeDeployRegisterRevision"
    effect    = "Allow"
    actions   = ["codedeploy:RegisterApplicationRevision"]
    resources = ["arn:aws:codedeploy:${var.aws_region}:${data.aws_caller_identity.current.account_id}:application:${data.terraform_remote_state.compute.outputs.codedeploy_application_name}"]
  }

  statement {
    sid       = "CodeDeployConfig"
    effect    = "Allow"
    actions   = ["codedeploy:GetDeploymentConfig"]
    resources = ["arn:aws:codedeploy:${var.aws_region}:${data.aws_caller_identity.current.account_id}:deploymentconfig:CodeDeployDefault.*"]
  }
}

module "api_role" {
  source = "../../../modules/github-oidc-role"

  name               = "${var.project}-${var.environment}-api"
  oidc_provider_arn  = data.terraform_remote_state.shared_oidc.outputs.oidc_provider_arn
  github_org         = var.github_org
  github_org_id      = var.github_org_id
  github_repo        = var.api_repo
  github_repo_id     = var.api_repo_id
  github_environment = var.environment
  policy_json        = data.aws_iam_policy_document.api.json

  tags = {
    Environment = var.environment
    Project     = var.project
  }
}

data "aws_iam_policy_document" "landing" {
  statement {
    sid    = "SyncBucket"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]
    resources = ["arn:aws:s3:::${data.terraform_remote_state.frontend.outputs.landing_bucket_name}"]
  }

  statement {
    sid    = "SyncObjects"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["arn:aws:s3:::${data.terraform_remote_state.frontend.outputs.landing_bucket_name}/*"]
  }

  statement {
    sid       = "InvalidateCache"
    effect    = "Allow"
    actions   = ["cloudfront:CreateInvalidation"]
    resources = ["arn:aws:cloudfront::${data.aws_caller_identity.current.account_id}:distribution/${data.terraform_remote_state.frontend.outputs.landing_distribution_id}"]
  }
}

module "landing_role" {
  source = "../../../modules/github-oidc-role"

  name               = "${var.project}-${var.environment}-landing"
  oidc_provider_arn  = data.terraform_remote_state.shared_oidc.outputs.oidc_provider_arn
  github_org         = var.github_org
  github_org_id      = var.github_org_id
  github_repo        = var.landing_repo
  github_repo_id     = var.landing_repo_id
  github_environment = var.environment
  policy_json        = data.aws_iam_policy_document.landing.json

  tags = {
    Environment = var.environment
    Project     = var.project
  }
}
