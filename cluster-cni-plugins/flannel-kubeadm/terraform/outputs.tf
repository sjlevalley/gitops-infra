# Output values for the Kubernetes cluster instances

output "server_public_ip" {
  description = "Public IP address of the Kubernetes server (control plane)"
  value       = module.cluster.server_public_ip
}

output "server_private_ip" {
  description = "Private IP address of the Kubernetes server"
  value       = module.cluster.server_private_ip
}

output "node_0_public_ip" {
  description = "Public IP address of node-0 (worker node)"
  value       = module.cluster.node_0_public_ip
}

output "node_0_private_ip" {
  description = "Private IP address of node-0"
  value       = module.cluster.node_0_private_ip
}

output "node_1_public_ip" {
  description = "Public IP address of node-1 (worker node)"
  value       = module.cluster.node_1_public_ip
}

output "node_1_private_ip" {
  description = "Private IP address of node-1"
  value       = module.cluster.node_1_private_ip
}

output "fqdns" {
  description = "Fully qualified domain names for all instances"
  value = {
    server = "server.kubernetes.local"
    node-0 = "node-0.kubernetes.local"
    node-1 = "node-1.kubernetes.local"
  }
}

output "cluster_info" {
  description = "Kubernetes cluster information"
  value = {
    server_ip = module.cluster.server_public_ip
    node_0_ip = module.cluster.node_0_public_ip
    node_1_ip = module.cluster.node_1_public_ip
    ssh_key   = module.cluster.key_pair_name
  }
}

output "ssh_connection_info" {
  description = "SSH connection information"
  value = {
    private_key_file   = module.cluster.private_key_path
    ssh_command_server = "ssh -i ${module.cluster.private_key_filename} admin@${module.cluster.server_public_ip}"
    ssh_command_node_0 = "ssh -i ${module.cluster.private_key_filename} admin@${module.cluster.node_0_public_ip}"
    ssh_command_node_1 = "ssh -i ${module.cluster.private_key_filename} admin@${module.cluster.node_1_public_ip}"
  }
}

output "ansible_info" {
  description = "Ansible automation information"
  value = {
    inventory_path = "${path.module}/ansible/inventory.ini"
    playbook_path  = "${path.module}/ansible/site.yml"
    run_command    = "cd ${path.module}/ansible && ansible-playbook -i inventory.ini site.yml"
    note           = "Run after terraform apply. Requires Ansible installed locally."
  }
}
