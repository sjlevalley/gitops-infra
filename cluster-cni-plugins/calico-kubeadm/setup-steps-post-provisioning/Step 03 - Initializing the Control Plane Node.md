# Step 03 - Initializing the Control Plane Node

**Prerequisites:** Ensure Step 01 and Step 02 have been completed on ALL nodes before proceeding.

Every node must have **`conntrack`** installed before **`kubeadm init`** or **`kubeadm join`** (included in the Step 01-02 combined script). If you skipped that or hit **`[ERROR FileExisting-conntrack]`**, run on the affected node:

```bash
sudo apt-get update
sudo apt-get install -y conntrack
```

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
# Initialize the Kubernetes cluster.
# The advertise address is auto-detected from this node's primary private IP,
# so it survives instance recreation (EC2 assigns a new private IP each time).
sudo kubeadm init --apiserver-advertise-address "$(hostname -I | awk '{print $1}')" --pod-network-cidr "10.244.0.0/16" --upload-certs

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
# Example join command (use the actual command from kubeadm init output):
sudo kubeadm join <MASTER_PRIVATE_IP>:6443 --token <TOKEN> \
        --discovery-token-ca-cert-hash sha256:<HASH>
```

**Important Notes:**
- The token and hash values will be different for your cluster
- Use the exact values provided by your kubeadm init output
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
**Warning:** `[WARNING Hostname]: hostname "ip-172-31-20-247" could not be reached`

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

### Issue 5: API Server Times Out / "no route to host" on Port 6443
**Error:** `[api-check] The API server is not healthy after 4m0s` followed by `error execution phase wait-control-plane: could not initialize a Kubernetes cluster`, then `dial tcp <IP>:6443: connect: no route to host`.

**Cause:** The `--apiserver-advertise-address` was set to an IP that does **not** belong to this node (e.g. a hardcoded IP left over from a previous deployment). The kube-apiserver static pod cannot bind to an address the host does not own, so it crash-loops and never becomes healthy.

**Solution:** Reset and re-init using the node's own private IP (the updated command above auto-detects it):

```bash
sudo kubeadm reset -f
sudo rm -rf /etc/cni/net.d $HOME/.kube

# Confirm this node's primary private IP:
hostname -I | awk '{print $1}'

# Re-run the init command from Step 2 (it auto-detects the IP).
```

## Important Notes
- The `--apiserver-advertise-address` uses the **private IP** of your master node, auto-detected via `hostname -I | awk '{print $1}'`. Do **not** hardcode an IP here — EC2 assigns a new private IP whenever the instance is recreated, and a stale/wrong IP causes the API server to fail to bind (`connect: no route to host` on port 6443).
- To see the master's private IP from your workstation: `terraform output server_private_ip`
- The `--pod-network-cidr` uses a /16 subnet (10.244.0.0/16) to accommodate both worker nodes
- The `--upload-certs` flag uploads control-plane certificates to a ConfigMap for easier worker node joining
- **Save the kubeadm join command** - you'll need it for joining worker nodes
- The master node will show as "NotReady" until a pod network add-on is deployed (Step 04)