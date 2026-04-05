# Ansible Automation for Kubeadm + Flannel Cluster

This directory contains Ansible playbooks and roles generated/populated by Terraform.

## Usage

1. After `terraform apply`, the inventory and playbooks are created in this folder.
2. Run the full bootstrap:

```bash
cd ansible
ansible-playbook -i inventory.ini site.yml
```

3. For just common setup on all nodes:

```bash
ansible-playbook -i inventory.ini site.yml --tags common
```

## Structure

- `inventory.ini` — Dynamic inventory from Terraform outputs
- `site.yml` — Main playbook
- `roles/` — Modular roles for each phase

## Customization

Edit `site.yml` to enable/disable the `deploy-app` role or add new roles for Trino, monitoring, etc.

See `../../setup-steps-post-provisioning/` for the original manual steps this automates.
