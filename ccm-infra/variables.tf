variable "aws_region" {
  description = "The target AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Crazy Cloud Monkey Project"
  type        = string
  default     = "ccm"
}

variable "environment" {
  description = "Deployment environment stage"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.100.0.0/16"
}