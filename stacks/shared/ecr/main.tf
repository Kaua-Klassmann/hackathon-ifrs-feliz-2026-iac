module "ecr" {
  source = "../../../modules/ecr"

  name         = "${var.project}-api"
  force_delete = true

  tags = {
    Project = var.project
    Scope   = "shared"
  }
}
