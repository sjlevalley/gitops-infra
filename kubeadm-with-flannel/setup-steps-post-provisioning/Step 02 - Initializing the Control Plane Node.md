# Step 02 - Initializing the Control Plane Node

**Prerequisites:** Ensure Step 01 has been completed on ALL nodes before proceeding.

## Step 1: Set Proper Hostnames On All Nodes
Set proper hostnames to avoid DNS resolution warnings.

***RUN ON EACH NODE APPROPRIATELY***
```bash
{
# Set hostname based on node role
# Run the appropriate command for each node:

# On master node:
sudo hostnamectl set-hostname master

# On node-0:
sudo hostnamectl set-hostname node-0

# On node-1:
sudo hostnamectl set-hostname node-1

# Verify hostname
hostnamectl status
}
```

## Step 2: Initialize the Kubernetes Cluster and Configure kubectl

***ONLY RUN ON MASTER NODE***
```bash
{
# Get the correct IP automatically and Initialize the Kubernetes cluster
MASTER_IP=$(hostname -I | awk '{print $1}')
sudo kubeadm init --apiserver-advertise-address $MASTER_IP --pod-network-cidr "10.244.0.0/16" --upload-certs

# Save the join command output - you'll need it for worker nodes
echo "=== SAVE THE KUBEADM JOIN COMMAND FROM THE OUTPUT ABOVE ==="

# Create .kube directory
mkdir -p $HOME/.kube

# Copy admin configuration
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config

# Set proper ownership
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Verify kubectl configuration
kubectl cluster-info
kubectl get nodes
}
```



## Step 3: Join Worker Nodes to Cluster

***RUN ON EACH WORKER NODE***
Use the exact join command from the kubeadm init output:

```bash
# Option 1: Use the exact join command from kubeadm init output (RECOMMENDED)
# The output will already include the correct master IP address
# Example output format:
# sudo kubeadm join <MASTER_IP>:6443 --token <TOKEN> \
#         --discovery-token-ca-cert-hash sha256:<HASH>

# Option 2: If you need to construct the command manually, get master IP from master node
# First, on the master node, get the IP:
# MASTER_IP=$(hostname -I | awk '{print $1}')
# echo $MASTER_IP
# Then on worker nodes, use that IP in the join command:
# sudo kubeadm join <MASTER_IP>:6443 --token <TOKEN> \
#         --discovery-token-ca-cert-hash sha256:<HASH>
```

**Important Notes:**
- The token and hash values will be different for your cluster
- **The join command from `kubeadm init` output already includes the correct master IP** - use that exact command
- If you need to regenerate the join command, run on master node: `sudo kubeadm token create --print-join-command`
- Run this command on each worker node (node-0 and node-1)











## Step 4: Verify Cluster Status

***RUN ON MASTER NODE***
```bash
{
# Check cluster status
kubectl cluster-info

# Check nodes (master will show as NotReady until CNI is installed)
kubectl get nodes

# Check all pods in kube-system namespace
kubectl get pods -n kube-system
}
```

## Troubleshooting Common Issues

### Issue 1: Hostname Resolution Warning
**Warning:** `[WARNING Hostname]: hostname "ip-172-31-17-166" could not be reached`

**Solution:** Follow Step 1 above to set proper hostnames on all nodes.

### Issue 2: API Server Not Starting
**Error:** `container.Runtime.Name must be set: invalid argument`

**Solution:** This indicates containerd configuration is missing. Follow Step 02 (Install Container Runtime) to create a complete containerd configuration.

### Issue 3: Duplicate Join Attempt
**Error:** `[ERROR FileAvailable--etc-kubernetes-kubelet.conf]: /etc/kubernetes/kubelet.conf already exists`

**Solution:** Reset the node and try again:

```bash
# Reset kubeadm on the problematic node
sudo kubeadm reset --force

# Stop and disable kubelet
sudo systemctl stop kubelet
sudo systemctl disable kubelet

# Clean up remaining files
sudo rm -rf /etc/kubernetes/
sudo rm -rf /var/lib/kubelet/
sudo rm -rf /var/lib/etcd/

# Now try the join command again
```

### Issue 4: Expired Join Token
**Error:** `[ERROR TokenInvalid]: token is invalid due to time`

**Solution:** Generate a new join token from the master node:

```bash
# On the master node, generate a new join token
sudo kubeadm token create --print-join-command
```

## Important Notes
- The `--apiserver-advertise-address` uses the **private IP** of your master node (automatically detected via `hostname -I`)
- The `--pod-network-cidr` uses a /16 subnet (10.244.0.0/16) to accommodate both worker nodes
- The `--upload-certs` flag uploads control-plane certificates to a ConfigMap for easier worker node joining
- **Save the kubeadm join command** - you'll need it for joining worker nodes (it already includes the correct master IP)
- The master node will show as "NotReady" until a pod network add-on is deployed (Step 03)