# Step 03 - Install CNI Plugin (Flannel)

**Prerequisites:** 
- Step 01 and Step 02 must be completed first
- kubeadm init must be successful before running this step

**Note:** CNI prerequisites are now included in Step 01. This step only deploys the Flannel network after kubeadm init.

## Deploy Flannel Network (AFTER KUBEADM INIT)

***RUN ON MASTER NODE ONLY***
```bash
{
# Deploy Flannel network
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

# Wait for Flannel pods to be ready
echo "Waiting for Flannel pods to start..."
sleep 30

# Verify Flannel pods are running
echo "=== Checking Flannel Pods ==="
kubectl get pods -n kube-flannel

echo "=== Checking All Pods ==="
kubectl get pods -A

echo "=== Checking Node Status ==="
kubectl get nodes
}
```

## Step 2: Setup Flannel Plugin on ALL Nodes

***RUN ON ALL NODES (INCLUDING MASTER)***

This step ensures the flannel CNI plugin is properly configured on all nodes to prevent pod creation issues.

```bash
{
# Check if flannel plugin is available
ls -la /usr/lib/cni/ | grep flannel

# If flannel symlink is missing, create it
sudo ln -sf /opt/cni/bin/flannel /usr/lib/cni/flannel

# Restart kubelet to pick up changes
sudo systemctl restart kubelet

# Wait for kubelet to restart
sleep 10

# Verify the plugin is now available
ls -la /usr/lib/cni/ | grep flannel
}
```

<!-- **Run this on:**
- **master**: `ssh -i "kubeadm-with-flannel/terraform/k8s-key.pem" admin@98.80.77.111`
- **node-0**: `ssh -i "kubeadm-with-flannel/terraform/k8s-key.pem" admin@54.83.125.17`
- **node-1**: `ssh -i "kubeadm-with-flannel/terraform/k8s-key.pem" admin@3.85.237.175` -->

## Step 3: Verify Cluster Status

***RUN ON MASTER NODE***
```bash
{
# Check all nodes are ready
kubectl get nodes

# Check all pods in kube-system
kubectl get pods -n kube-system

# Check flannel pods specifically
kubectl get pods -n kube-flannel
}
```

## Troubleshooting: Pods Stuck in ContainerCreating

If any pods are still stuck in "ContainerCreating" state after following the steps above, the flannel CNI plugin setup may have failed. Re-run Step 2 on the affected node(s) to ensure the flannel plugin is properly configured.

You can also check the pod status from the master node:
```bash
kubectl get pods -A
kubectl describe pod <pod-name>
```

**Expected Output:**
- You should see `kube-flannel-*` pods in the `kube-flannel` namespace
- All nodes should show as `Ready` status
- All pods in `kube-system` should be running 