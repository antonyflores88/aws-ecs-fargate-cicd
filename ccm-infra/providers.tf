terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0"
    }
  }
}

# Configura the AWS Provider
provider "aws" {
  region = var.aws_region

  # Default tags automatically apply to every resource Terraform builds
  default_tags {
    tags = {
      "Project"     = var.project_name
      "Environment" = var.environment
      "ManagedBy"   = "Terraform"
    }
  }
}

