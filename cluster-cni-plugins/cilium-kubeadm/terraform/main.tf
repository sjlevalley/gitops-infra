# Configure the AWS Provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.0"
    }
  }
  required_version = ">= 1.0"
}

provider "aws" {
  region = var.aws_region
}

module "cluster" {
  source = "../../modules/kubeadm-ec2-cluster"

  stack_identifier    = "kubeadm-cilium"
  pod_subnets         = var.pod_subnets
  artifacts_directory = abspath(path.module)
}
