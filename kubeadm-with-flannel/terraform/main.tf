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

  stack_identifier    = "kubeadm-flannel"
  pod_subnets         = var.pod_subnets
  artifacts_directory = abspath(path.module)
}

# Ansible inventory and playbook copy (Flannel stack automation only)
resource "local_file" "ansible_inventory" {
  filename = "${path.module}/ansible/inventory.ini"
  content = templatefile("${path.module}/ansible/inventory.ini.tpl", {
    server_public_ip = module.cluster.server_public_ip
    node0_public_ip  = module.cluster.node_0_public_ip
    node1_public_ip  = module.cluster.node_1_public_ip
    ssh_key_path     = module.cluster.private_key_path
  })
}

resource "local_file" "ansible_site_yml" {
  filename = "${path.module}/ansible/site.yml"
  content  = file("${path.module}/ansible/site.yml")
}

# Optional: Run Ansible automatically after Terraform (disabled by default for safety)
# resource "null_resource" "run_ansible" {
#   triggers = {
#     always_run = timestamp()
#   }
#
#   provisioner "local-exec" {
#     command = "cd ${path.module}/ansible && ansible-playbook -i inventory.ini site.yml --extra-vars 'deploy_sample_app=true'"
#   }
# }
