${server_private_ip} server.kubernetes.local server
${node_0_private_ip} node-0.kubernetes.local node-0 ${pod_subnets["node-0"]}
${node_1_private_ip} node-1.kubernetes.local node-1 ${pod_subnets["node-1"]}

# SSH connection commands for each node:
# Server (Control Plane): ssh -i "${key_filename}" -o "StrictHostKeyChecking=no" -o "UserKnownHostsFile=/dev/null" admin@${server_public_ip} "sudo hostnamectl set-hostname server"
# Node-0 (Worker): ssh -i "${key_filename}" -o "StrictHostKeyChecking=no" -o "UserKnownHostsFile=/dev/null" admin@${node_0_public_ip} "sudo hostnamectl set-hostname node-0"
# Node-1 (Worker): ssh -i "${key_filename}" -o "StrictHostKeyChecking=no" -o "UserKnownHostsFile=/dev/null" admin@${node_1_public_ip} "sudo hostnamectl set-hostname node-1"
