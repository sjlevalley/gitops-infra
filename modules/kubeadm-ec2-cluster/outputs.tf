output "server_public_ip" {
  description = "Public IP address of the control plane"
  value       = aws_instance.server.public_ip
}

output "server_private_ip" {
  description = "Private IP address of the control plane"
  value       = aws_instance.server.private_ip
}

output "node_0_public_ip" {
  description = "Public IP address of worker node-0"
  value       = aws_instance.node_0.public_ip
}

output "node_0_private_ip" {
  description = "Private IP address of worker node-0"
  value       = aws_instance.node_0.private_ip
}

output "node_1_public_ip" {
  description = "Public IP address of worker node-1"
  value       = aws_instance.node_1.public_ip
}

output "node_1_private_ip" {
  description = "Private IP address of worker node-1"
  value       = aws_instance.node_1.private_ip
}

output "security_group_id" {
  description = "ID of the cluster security group"
  value       = aws_security_group.k8s_cluster.id
}

output "key_pair_name" {
  description = "AWS EC2 key pair name"
  value       = aws_key_pair.k8s.key_name
}

output "private_key_path" {
  description = "Absolute path to the generated PEM file"
  value       = local_file.k8s_private_key.filename
}

output "public_key_path" {
  description = "Absolute path to the generated public key file"
  value       = local_file.k8s_public_key.filename
}

output "machines_txt_path" {
  description = "Absolute path to generated machines.txt"
  value       = local_file.machines_txt.filename
}

output "private_key_filename" {
  description = "Basename of the private key file (for SSH commands)"
  value       = var.private_key_filename
}
