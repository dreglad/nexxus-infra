terraform {
  cloud {
    organization = "Sonatafy"

    workspaces {
      name = "nexxus"
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

locals {
  frontend_domain = "app.${var.domain}"
  backend_domain  = "api.${var.domain}"
  email_domain    = "app.${var.domain}"
}

resource "aws_route53_zone" "nexxus" {
  name = var.domain
}

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "3.15.0"

  name                 = "nexxus"
  cidr                 = "10.0.0.0/16"
  azs                  = data.aws_availability_zones.available.names
  public_subnets       = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
  enable_dns_hostnames = true
  enable_dns_support   = true
}

# Base domain name

