terraform {
  required_version = ">= 1.10.0, < 2.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
  # Before team use, configure an encrypted S3 backend and use_lockfile = true.
  # Keep local state private; it is excluded from Git.
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "Terraform"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_availability_zones" "available" {
  state = "available"
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  prefix       = var.project_name
  account_id   = data.aws_caller_identity.current.account_id
  partition    = data.aws_partition.current.partition
  azs          = slice(data.aws_availability_zones.available.names, 0, 2)
  pipeline     = "${local.prefix}-pipeline"
  build        = "${local.prefix}-build"
  verify       = "${local.prefix}-verify"
  cluster      = "${local.prefix}-eks"
  connection   = var.github_connection_arn != "" ? var.github_connection_arn : aws_codestarconnections_connection.github[0].arn
  managed_base = "arn:${local.partition}:iam::aws:policy"
}
