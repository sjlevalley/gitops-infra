# Installing Calico CNI Plugin

## Why Calico is Better for Your Situation

Calico is recommended over Flannel for your AWS EC2 setup because:

- **Resolves Flannel's Issues**: Flannel uses VXLAN, which causes problems with checksum offloading, MTU mismatches, and packet routing on AWS EC2. Calico defaults to BGP routing (no VXLAN), avoiding these issues entirely.
- **Higher Performance**: Better scalability and performance for larger clusters
- **Built-in Network Policies**: Native support for Kubernetes Network Policies
- **AWS Compatibility**: Integrates well with VPC routing, avoiding overlay network complexities
- **No Interface Tweaks**: Doesn't require ethtool fixes or systemd services for checksum issues

## Prerequisites

- Cluster initialized with kubeadm
- Pod CIDR: `10.244.0.0/16` (must match kubeadm init --pod-network-cidr=10.244.0.0/16)
- No existing CNI plugin installed
- kubectl configured on master node
- SSH access to all nodes
- CNI plugins installed on all nodes (from Step 02)

## Installation Steps

### Step 1: Verify Cluster Status (Master Node Only)
```bash
kubectl cluster-info
kubectl get nodes
```
**Run on**: Master node only

### Step 2: Verify CNI Plugins Installation (All Nodes)
```bash
# Check if CNI plugins are installed
{
ls -la /opt/cni/bin | grep -E "(bridge|host-local|loopback|portmap|tuning|vlan|bandwidth|firewall|sbr|static|dhcp|host-device|macvlan|ipvlan|ptp|vrf)"
}
```
**Run on**: All nodes (master, node-0, node-1)
**Expected**: Should show multiple CNI plugin symlinks

**If CNI plugins are missing, install them:**
```bash
{
# Install CNI plugins (required for Calico to work)
sudo mkdir -p /opt/cni/bin
cd /tmp
wget -q https://github.com/containernetworking/plugins/releases/download/v1.3.0/cni-plugins-linux-amd64-v1.3.0.tgz
sudo tar -xzf cni-plugins-linux-amd64-v1.3.0.tgz -C /opt/cni/bin/

# Create symlink so Kubernetes can find CNI plugins
sudo mkdir -p /usr/lib/cni
sudo ln -sf /opt/cni/bin/* /usr/lib/cni/

# Verify CNI plugins are available
ls -la /usr/lib/cni/ | grep -E "(bridge|host-local|loopback|portmap|tuning|vlan|bandwidth|firewall|sbr|static|dhcp|host-device|macvlan|ipvlan|ptp|vrf|calico)"

# Clean up
rm -f cni-plugins-linux-amd64-v1.3.0.tgz
cd ~

# Restart kubelet to pick up changes
sudo systemctl restart kubelet
}
```

### Step 3: Check for Existing CNI (All Nodes)
```bash
ls /etc/cni/net.d/
```
**Run on**: All nodes (master, node-0, node-1)
**Expected**: Should be empty or only contain loopback.conf

### Step 4: Install Tigera Operator (Master Node Only)
```bash
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.32.0/manifests/tigera-operator.yaml
```
**Run on**: Master node only

### Step 5: Download Custom Resources (Master Node Only)
```bash
curl https://raw.githubusercontent.com/projectcalico/calico/v3.32.0/manifests/custom-resources.yaml -O
```
**Run on**: Master node only

### Step 6: Edit Custom Resources (Master Node Only)
```bash
nano custom-resources.yaml
```
**Run on**: Master node only

**Edit the file to match your pod CIDR:**
```yaml
spec:
  calicoNetwork:
    ipPools:
    - blockSize: 26
      cidr: 10.244.0.0/16
      encapsulation: None  # Use None for BGP (no VXLAN)
      natOutgoing: Enabled
      nodeSelector: all()
```

### Step 7: Apply Custom Resources (Master Node Only)
```bash
kubectl apply -f custom-resources.yaml
```
**Run on**: Master node only

### Step 7.5: Verify IP Pool Creation (Master Node Only)
```bash
# Calico CRD: short name is "ippool" (singular), not "ippools"
kubectl get ippool
# equivalent:
kubectl get ippools.crd.projectcalico.org
```
**Run on**: Master node only
**Expected**: A pool such as `default-ipv4-ippool` (CIDR `10.244.0.0/16` from your `Installation` / spec).

`kubectl get ippools` often returns nothing because Kubernetes does not register that alias for this resource.

**If you get "no resources found" (or Installation is not Ready yet), run these diagnostic commands:**
```bash
# Check if the custom resources were applied
kubectl get installation
kubectl get apiserver

# Check for any errors in the custom resources
kubectl describe installation default
kubectl describe apiserver default

# Check if Calico operator is running
kubectl get pods -n tigera-operator

# Check the custom-resources.yaml file content
cat custom-resources.yaml
```

### Step 8: Verify Calico Installation (Master Node Only)
```bash
watch kubectl get pods -n calico-system
```
**Run on**: Master node only
**Wait for**: All pods (calico-node, calico-typha) to reach Running state (2-5 minutes)

### Step 9: Check Node Status (Master Node Only)
```bash
kubectl get nodes -o wide
```
**Run on**: Master node only
**Expected**: All nodes should show as Ready

### Step 10: Verify CNI Configuration (All Nodes)
```bash
# On master node
ls /etc/cni/net.d/
cat /etc/cni/net.d/10-calico.conflist

# On node-0
sudo ls /etc/cni/net.d/ && sudo cat /etc/cni/net.d/10-calico.conflist

# On node-1
sudo ls /etc/cni/net.d/ && sudo cat /etc/cni/net.d/10-calico.conflist
```
**Run on**: All nodes (master, node-0, node-1)
**Expected**: Should contain 10-calico.conflist

### Step 11: Test Pod-to-Pod Communication (Master Node Only)
```bash
# Option A (recommended): DNS utils image with nslookup/dig
kubectl run test-dns --image=registry.k8s.io/e2e-test-images/jessie-dnsutils:1.3 \
  --rm -it --restart=Never -- /bin/sh

# Option B (often faster pull): BusyBox (usually includes nslookup)
# kubectl run test-dns --image=busybox:1.36 --rm -it --restart=Never -- /bin/sh
```
**Run on**: Master node only
**Inside the pod, test connectivity:**
```bash
# Test DNS resolution
nslookup kubernetes.default.svc.cluster.local 10.96.0.10

# (Optional) Verify API service IP is reachable (should be 10.96.0.1)
nslookup kubernetes.default.svc.cluster.local
```

### Step 12: Deploy Test Application (Master Node Only)
```bash
kubectl create deployment nginx --image=nginx
kubectl expose deployment nginx --port=80 --type=NodePort
```
**Run on**: Master node only

### Step 13: Get Service Details (Master Node Only)
```bash
kubectl get svc nginx
kubectl get pods -o wide
```
**Run on**: Master node only
**Note**: Record the NodePort number (the `PORT(S)` column shows `80:<nodePort>/TCP`)

### Step 14: Test Cross-Node NodePort Access (All Nodes)
```bash
# Get the NodePort (run on master)
NODEPORT="$(kubectl get svc nginx -o jsonpath='{.spec.ports[0].nodePort}')"
echo "NodePort is: $NODEPORT"

# Test from master node
curl -I "http://127.0.0.1:${NODEPORT}"

# Test from node-0
# SSH into node-0, then run:
# curl -I "http://127.0.0.1:${NODEPORT}"

# Test from node-1  
# SSH into node-1, then run:
# curl -I "http://127.0.0.1:${NODEPORT}"
```
**Run on**: All nodes (master, node-0, node-1)
**Expected**: All should return HTTP 200 OK

### Step 15: Test External Access (Local Machine)
```bash
# Read live cluster values from Terraform state (run from your local machine in Git Bash)
TF_DIR="/c/Users/sleva/OneDrive/Desktop/Desktop/ActiveApps/EC2-Kubernetes/gitops-infra/cluster-cni-plugins/calico-kubeadm/terraform"
MASTER_IP=$(terraform -chdir="$TF_DIR" output -raw server_public_ip)
NODE0_IP=$(terraform -chdir="$TF_DIR" output -raw node_0_public_ip)
NODE1_IP=$(terraform -chdir="$TF_DIR" output -raw node_1_public_ip)
KEY="$TF_DIR/k8s-key.pem"

# Get the NodePort by asking the control-plane
NODEPORT="$(ssh -i "$KEY" -o StrictHostKeyChecking=no "admin@${MASTER_IP}" \
  "kubectl get svc nginx -o jsonpath='{.spec.ports[0].nodePort}'")"
echo "NodePort is: $NODEPORT"

# Test external access to all nodes
for ip in "$MASTER_IP" "$NODE0_IP" "$NODE1_IP"; do
  echo "--- $ip ---"
  curl -I "http://${ip}:${NODEPORT}"
done
```
**Run on**: Your local machine
**Expected**: All should return HTTP 200 OK

## Troubleshooting

### `failed to find plugin "calico" in path [/usr/lib/cni]`

Containerd was pointing CNI `bin_dir` at **`/usr/lib/cni`**, but Calico installs the **`calico`** binary under **`/opt/cni/bin`**. Fix on **every node**:

```bash
sudo sed -i 's|bin_dir = "/usr/lib/cni"|bin_dir = "/opt/cni/bin"|' /etc/containerd/config.toml
grep bin_dir /etc/containerd/config.toml   # should show /opt/cni/bin
sudo systemctl restart containerd
sudo systemctl restart kubelet
```

Confirm **`ls /opt/cni/bin/calico`** exists on workers after **`calico-node`** has run. Delete stuck pods so they reschedule: **`kubectl delete pod -n calico-system --field-selector=status.phase!=Running`** (or delete specific pods). New clusters should use Step 01-02 as updated (`bin_dir = "/opt/cni/bin"`).

### If Calico Pods Don't Start
```bash
kubectl logs -n calico-system -l k8s-app=calico-node
kubectl describe pods -n calico-system
```

### If Nodes Show NotReady
```bash
kubectl get nodes -o wide
kubectl describe node <node-name>
```

### Master Node NotReady: `cni plugin not initialized`

**Symptom:** Worker nodes show `Ready` but master stays `NotReady` with this message in `kubectl describe node master`:
```
KubeletNotReady: container runtime network not ready: NetworkReady=false reason:NetworkPluginNotReady message:Network plugin returns error: cni plugin not initialized
```

**Cause:** Calico's `calico-node` pod wrote the CNI config and binary *after* containerd had already started and cached a "no CNI" state. Restarting only the kubelet is not enough — containerd itself must be restarted to re-scan `/opt/cni/bin/` and `/etc/cni/net.d/`.

Note: Workers don't hit this because they join the cluster after Calico is already installed, so containerd initializes with the CNI already in place.

**Verify everything is in place first:**
```bash
grep bin_dir /etc/containerd/config.toml   # should show /opt/cni/bin
ls /opt/cni/bin/calico                     # binary must exist
ls /etc/cni/net.d/                         # should show 10-calico.conflist
```

**Fix (run on master):**
```bash
sudo systemctl restart containerd
sleep 5
sudo systemctl restart kubelet
```

Wait ~30 seconds, then confirm:
```bash
kubectl get nodes
```

### If Cross-Node Access Fails
```bash
# Check Calico configuration
kubectl get ippool
kubectl get nodes -o wide

# Verify CNI configuration on all nodes
# (from your local machine in Git Bash; reads worker IPs + key from Terraform state)
TF_DIR="/c/Users/sleva/OneDrive/Desktop/Desktop/ActiveApps/EC2-Kubernetes/gitops-infra/cluster-cni-plugins/calico-kubeadm/terraform"
KEY="$TF_DIR/k8s-key.pem"
cat /etc/cni/net.d/10-calico.conflist   # on the master
for o in node_0_public_ip node_1_public_ip; do
  ip=$(terraform -chdir="$TF_DIR" output -raw $o)
  ssh -i "$KEY" -o StrictHostKeyChecking=no "admin@${ip}" "cat /etc/cni/net.d/10-calico.conflist"
done
```

### If External Access Fails
```bash
# Check security group rules
aws ec2 describe-security-groups --filters Name=group-name,Values=k8s-cluster-sg

# Verify NodePort range is open (30000-32767)
```

## Rollback to Flannel (If Needed)

If Calico doesn't work as expected:

```bash
# Remove Calico
kubectl delete -f https://raw.githubusercontent.com/projectcalico/calico/v3.32.0/manifests/tigera-operator.yaml
kubectl delete -f custom-resources.yaml

# Clean up CNI configuration on all nodes
sudo rm /etc/cni/net.d/10-calico.conflist
sudo systemctl restart kubelet

# Install Flannel
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
```

## Expected Results

After successful installation:
- ✅ All nodes show as Ready
- ✅ Calico pods are running in calico-system namespace
- ✅ Cross-node NodePort access works via localhost
- ✅ External browser access works to all node IPs
- ✅ No need for TX checksum offloading fixes
- ✅ No VXLAN-related issues

## Security Group Requirements

Ensure your AWS security group has:
- **TCP 30000-32767** from 0.0.0.0/0 (NodePort services)
- **TCP 22** from 0.0.0.0/0 (SSH access)
- **TCP 6443** from 0.0.0.0/0 (Kubernetes API)
- **All traffic** between nodes (self-referential rules)

## Next Steps

1. Deploy your voting application
2. Test cross-node communication
3. Verify external access works
4. Configure network policies if needed

Calico should resolve all the cross-node communication issues you experienced with Flannel!
