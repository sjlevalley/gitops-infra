locals {
  wsl_key_path = replace(replace(module.cluster.private_key_path, "C:", "/mnt/c"), "\\", "/")
}

resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/../ansible/inventory.ini.tpl", {
    server_public_ip = module.cluster.server_public_ip
    node0_public_ip  = module.cluster.node_0_public_ip
    node1_public_ip  = module.cluster.node_1_public_ip
    ssh_key_path     = local.wsl_key_path
  })
  filename        = "${path.module}/../ansible/inventory.ini"
  file_permission = "0600"
}
