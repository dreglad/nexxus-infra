terraform {
  cloud {
    organization = "Sonatafy"

    workspaces {
      tags = [
        "nexxus",
        "aws",
      ]
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      Application = "Nexxus"
    }
  }
}

provider "aws" {
  alias  = "us-east-1"
  region = "us-east-1"
}

locals {
  frontend_domain = "app.${var.domain}"
  backend_domain  = "api.${var.domain}"
  email_domain    = "app.${var.domain}"
}

data "aws_route53_zone" "nexxus" {
  name = var.domain
}

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "3.16.0"

  name                 = "nexxus"
  cidr                 = "10.0.0.0/16"
  azs                  = data.aws_availability_zones.available.names
  public_subnets       = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
  enable_dns_hostnames = true
  enable_dns_support   = true
}
