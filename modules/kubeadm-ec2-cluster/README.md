# kubeadm-ec2-cluster

Terraform module that provisions **three Debian 12 EC2 instances** (one Kubernetes control plane, two workers), a **Kubernetes-oriented security group**, an **SSH key pair**, and generated **`k8s-key.pem`** / **`machines.txt`** under a directory you choose.

CNI (Flannel, Calico, Cilium, etc.) is **not** installed here—only the shared EC2/network/key layout before bootstrapping kubeadm and installing a CNI.

## Usage (root stack)

```hcl
provider "aws" {
  region = var.aws_region
}

module "cluster" {
  source = "../../modules/kubeadm-ec2-cluster"

  stack_identifier    = "kubeadm-mystack"
  pod_subnets         = var.pod_subnets
  artifacts_directory = abspath(path.module)
}
```

## State migration (from inline Terraform)

If you previously had EC2 resources in the root module and switch to this module, Terraform will see new resource addresses. Use [`moved` blocks](https://developer.hashicorp.com/terraform/language/modules/develop/refactoring) or `terraform state mv` to map old addresses to `module.cluster.*`, and set `key_pair_name` if your existing AWS key is still named `k8s-key`.

## Inputs (see `variables.tf`)

Key options: `stack_identifier`, `pod_subnets`, `artifacts_directory`, optional `key_pair_name`, instance types, AZ, root volume size.

## Outputs

Instance IPs, security group id, key pair name, paths to generated PEM and `machines.txt`.
