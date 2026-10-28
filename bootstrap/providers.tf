provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      ManagedBy = "terraform"
      Project   = "hackathon"
      Layer     = "bootstrap"
    }
  }
}