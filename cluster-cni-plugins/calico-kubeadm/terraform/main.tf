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
  source = "../../../modules/kubeadm-ec2-cluster"

  stack_identifier            = "kubeadm-calico"
  pod_subnets                 = var.pod_subnets
  artifacts_directory         = abspath(path.module)
  control_plane_instance_type = "t3.large"
  worker_instance_type        = "t3.large"

  # Calico can use non-encapsulated pod routing depending on IPPool settings.
  # Disabling source/destination check avoids EC2 dropping forwarded pod traffic.
  disable_source_dest_check = true

  # Attach an instance profile granting AmazonEBSCSIDriverPolicy to all nodes so
  # the AWS EBS CSI driver (Step 10) can provision volumes via the node role
  # instead of static IAM user credentials.
  enable_ebs_csi_iam = true
}
