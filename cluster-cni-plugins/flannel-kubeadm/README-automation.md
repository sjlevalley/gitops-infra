# Kubernetes Cluster Automation with Kubeadm

This directory contains an automated solution for setting up a Kubernetes cluster using kubeadm, replacing the manual steps 1-4.

## Files

- `test-shell-script.sh` - Main automation script that combines all 4 kubeadm steps
- `cluster-config.env` - Configuration template for IP addresses and settings
- `README-automation.md` - This documentation file

## Prerequisites

1. **Infrastructure**: 3 EC2 instances (1 master, 2 workers) running Debian 12
2. **Jumpbox**: A machine with SSH access to all nodes
3. **SSH Keys**: Key-based authentication configured
4. **Network**: All nodes can communicate with each other

## Quick Start

### 1. Configure the Script

```bash
# Copy and edit the configuration file
cp cluster-config.env my-cluster-config.env
nano my-cluster-config.env

# Update the IP addresses with your actual values from Terraform output
export MASTER_IP="172.31.19.113"  # Your master node private IP
export WORKER_IPS=("172.31.20.247" "172.31.21.123")  # Your worker node private IPs
```

### 2. Run the Script

```bash
# Make the script executable
chmod +x test-shell-script.sh

# Source your configuration
source my-cluster-config.env

# Run the automation script
./test-shell-script.sh
```

## What the Script Does

The script automates all 4 manual kubeadm steps:

### Step 1: Install Kubernetes Components
- Updates package repositories
- Adds Kubernetes GPG key
- Installs kubeadm, kubelet, kubectl
- Holds packages to prevent auto-updates

### Step 2: Install Container Runtime
- Installs containerd
- Configures containerd with systemd cgroup driver
- Restarts and enables containerd service

### Step 3: Initialize Control Plane
- Enables IP forwarding on all nodes
- Sets proper hostnames
- Initializes Kubernetes cluster on master
- Configures kubectl for regular user
- Extracts join command for worker nodes

### Step 4: Install CNI Plugin
- Installs CNI plugins on all nodes
- Deploys Flannel or Calico networking
- Joins worker nodes to cluster
- Verifies cluster health

## Configuration Options

### CNI Plugins
- **Flannel** (default): Simple, works well for basic setups
- **Calico**: More advanced, supports network policies

### Kubernetes Version
- Default: 1.31
- Change by modifying `KUBERNETES_VERSION` in the script

### Network Configuration
- Default Pod CIDR: 10.244.0.0/16
- Change by modifying `POD_NETWORK_CIDR` in the script

## Troubleshooting

### Common Issues

1. **SSH Connection Failed**
   ```bash
   # Test SSH connectivity
   ssh -i ~/.ssh/id_rsa admin@<NODE_IP> "echo 'SSH test'"
   ```

2. **Join Command Not Found**
   - Ensure Step 3 completed successfully
   - Check master node logs: `journalctl -u kubelet`

3. **Nodes Not Ready**
   - Wait a few minutes for CNI plugin to initialize
   - Check pod status: `kubectl get pods -n kube-system`

4. **Containerd Issues**
   - Verify configuration: `sudo systemctl status containerd`
   - Check logs: `journalctl -u containerd`

### Verification Commands

After successful setup, verify your cluster:

```bash
# SSH into master node
ssh -i ~/.ssh/id_rsa admin@<MASTER_IP>

# Check cluster status
kubectl cluster-info
kubectl get nodes
kubectl get pods -n kube-system

# Test with a simple pod
kubectl run nginx --image=nginx --port=80
kubectl get pods
kubectl delete pod nginx
```

## Integration with Terraform

To integrate this script with your existing Terraform setup:

1. **Add to Terraform**: Use `local-exec` provisioner to copy script to jumpbox
2. **Automate IP extraction**: Use Terraform outputs to populate configuration
3. **Trigger execution**: Run script after infrastructure is ready

Example Terraform addition:
```hcl
resource "null_resource" "k8s_setup" {
  depends_on = [aws_instance.server, aws_instance.node_0, aws_instance.node_1]
  
  provisioner "local-exec" {
    command = "scp -i k8s-key.pem test-shell-script.sh admin@${aws_instance.jumpbox.public_ip}:~/"
  }
  
  provisioner "local-exec" {
    command = "ssh -i k8s-key.pem admin@${aws_instance.jumpbox.public_ip} 'chmod +x test-shell-script.sh && ./test-shell-script.sh'"
  }
}
```

## Benefits of This Approach

1. **Single Command**: Complete cluster setup in one script execution
2. **Error Handling**: Comprehensive error checking and logging
3. **Idempotent**: Can be run multiple times safely
4. **Configurable**: Easy to customize for different environments
5. **Maintainable**: Well-documented and modular code
6. **Fast**: Much faster than manual step-by-step process

## Next Steps

After successful cluster setup:
1. Deploy your applications
2. Set up monitoring (Prometheus, Grafana)
3. Configure ingress controller
4. Implement backup strategies
5. Set up RBAC policies
