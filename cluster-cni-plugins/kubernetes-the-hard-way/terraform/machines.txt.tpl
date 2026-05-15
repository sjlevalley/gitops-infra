${server_private_ip} server.kubernetes.local server
${node_0_private_ip} node-0.kubernetes.local node-0 ${pod_subnets["node-0"]}
${node_1_private_ip} node-1.kubernetes.local node-1 ${pod_subnets["node-1"]}

# SSH connection commands for each node:
# Jumpbox (Administration): ssh -i "k8s-key.pem" admin@${jumpbox_public_ip}
# Server (Control Plane): ssh -i "k8s-key.pem" admin@${server_public_ip}
# Node-0 (Worker): ssh -i "k8s-key.pem" admin@${node_0_public_ip}
# Node-1 (Worker): ssh -i "k8s-key.pem" admin@${node_1_public_ip}

# Copy SSH keys to jumpbox commands:
# scp -i "k8s-key.pem" k8s-key.pem admin@${jumpbox_public_ip}:~/
# scp -i "k8s-key.pem" k8s-key.pub admin@${jumpbox_public_ip}:~/