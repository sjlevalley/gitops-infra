# Step 03 - Install Flannel CNI

**Prerequisites:** 
- Step 01 (Common Setup) completed on all nodes
- Step 02 (Cluster Initialization) completed successfully
- kubectl is configured on the master node

**Note:** The CNI plugins (including flannel) should already be installed from Step 01. This step deploys the Flannel network.

## Deploy Flannel Network

**Run on Master Node:**

```bash
# Deploy Flannel
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

# Wait for pods to start
echo "Waiting for Flannel pods to become ready..."
sleep 30

# Verify
kubectl get pods -n kube-flannel
kubectl get pods -A
kubectl get nodes
```

## Verify CNI Plugin Installation (All Nodes)

**Run on ALL nodes to verify the fix we added:**

```bash
# Check that flannel plugin is available
ls -la /usr/lib/cni/ | grep -E "(flannel|bridge|host-local)"

echo "=== CNI plugins check complete on $(hostname) ==="
```

**Expected:** You should see `flannel`, `bridge`, `host-local`, etc. listed.
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