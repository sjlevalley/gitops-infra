# Step 01 - Common Setup (All Nodes)

**Run this on ALL nodes (master, node-0, node-1)**

This step sets up the base requirements including Kubernetes repository, containerd, CNI plugins, and system configuration.

**Prerequisites:**
- Instances have been provisioned via Terraform
- You can SSH into all nodes using `k8s-key.pem`

<!-- **Verify which distribution of Linux you're using**
`sudo cat /etc/*release*` -->

## 1. Update System and Install Dependencies

```bash
sudo apt-get update
sudo apt-get install -y curl wget vim conntrack apt-transport-https ca-certificates gpg
```

## 2. Add Kubernetes Repository

```bash
# Create keyrings directory
sudo mkdir -p -m 755 /etc/apt/keyrings

# Add Kubernetes GPG key
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# Add Kubernetes repository
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list

# Update package index
sudo apt-get update
```

## 3. Install Kubernetes Components

```bash
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
```

## 4. System Configuration

```bash
# Enable IP forwarding
sudo sysctl net.ipv4.ip_forward=1
echo 'net.ipv4.ip_forward=1' | sudo tee -a /etc/sysctl.conf

# Load kernel modules
sudo modprobe br_netfilter
echo 'br_netfilter' | sudo tee -a /etc/modules

# Configure bridge settings
cat <<EOF | sudo tee /etc/sysctl.d/kubernetes.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

sudo sysctl -p /etc/sysctl.d/kubernetes.conf
```

## 5. Install containerd and CNI Plugins

```bash
# Install containerd
sudo apt install -y containerd

# Configure containerd
sudo mkdir -p /etc/containerd
cat <<EOF | sudo tee /etc/containerd/config.toml
version = 2

[plugins]
  [plugins."io.containerd.grpc.v1.cri"]
    [plugins."io.containerd.grpc.v1.cri".cni]
      bin_dir = "/usr/lib/cni"
      conf_dir = "/etc/cni/net.d"
    [plugins."io.containerd.grpc.v1.cri".containerd]
      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes]
        [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
          runtime_type = "io.containerd.runc.v2"
          [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
            SystemdCgroup = true
EOF

sudo systemctl restart containerd
sudo systemctl enable containerd

# Install CNI plugins (includes flannel plugin)
cd /tmp
wget -q https://github.com/containernetworking/plugins/releases/download/v1.3.0/cni-plugins-linux-amd64-v1.3.0.tgz
sudo mkdir -p /opt/cni/bin /usr/lib/cni
sudo tar -xzf cni-plugins-linux-amd64-v1.3.0.tgz -C /opt/cni/bin/
sudo ln -sf /opt/cni/bin/* /usr/lib/cni/
ls /usr/lib/cni/ | grep -E "(flannel|bridge|host-local)"
rm -f cni-plugins-linux-amd64-v1.3.0.tgz
cd ~

echo "=== Setup Complete on $(hostname) ==="
kubeadm version --short
kubectl version --client --short
echo "CNI plugins installed: $(ls /usr/lib/cni/ | grep -E '(flannel|bridge)' | tr '\n' ' ')"
```

**Next:** Proceed to [Step 02 - Initialize Cluster](Step%2002%20-%20Initializing%20the%20Control%20Plane%20Node.md)
EOL

{
# Enable IP forwarding (required for Kubernetes networking)
sudo sysctl net.ipv4.ip_forward=1 # Enable IP forwarding temporarily
echo 'net.ipv4.ip_forward=1' | sudo tee -a /etc/sysctl.conf # Make it permanent
cat /proc/sys/net/ipv4/ip_forward # Verify IP forwarding is enabled (should return 1)

# Update package index
sudo apt update

# Install containerd
sudo apt install -y containerd

# Verify cgroup driver (should be systemd)
echo "=== Checking cgroup driver ==="
ps -p 1

# Create containerd configuration with systemd cgroup driver
sudo tee /etc/containerd/config.toml > /dev/null << 'EOF'
version = 2

[plugins]
  [plugins."io.containerd.grpc.v1.cri"]
    [plugins."io.containerd.grpc.v1.cri".cni]
      bin_dir = "/usr/lib/cni"
      conf_dir = "/etc/cni/net.d"
    [plugins."io.containerd.grpc.v1.cri".containerd]
      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes]
        [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
          runtime_type = "io.containerd.runc.v2"
          [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
            SystemdCgroup = true
  [plugins."io.containerd.internal.v1.opt"]
    path = "/var/lib/containerd/opt"
EOF

# Restart containerd to apply configuration
sudo systemctl restart containerd

# Enable containerd to start on boot
sudo systemctl enable containerd

# Verify containerd is running
echo "=== Containerd Status ==="
sudo systemctl is-active containerd
echo "=== Containerd Service Status ==="
sudo systemctl status containerd --no-pager

# CNI Prerequisites (required before kubeadm init)
echo "=== Setting up CNI Prerequisites ==="

# Load the br_netfilter module
sudo modprobe br_netfilter

# Make br_netfilter permanent
echo 'br_netfilter' | sudo tee -a /etc/modules

# Configure bridge settings
echo 'net.bridge.bridge-nf-call-iptables = 1' | sudo tee -a /etc/sysctl.d/kubernetes.conf
echo 'net.bridge.bridge-nf-call-ip6tables = 1' | sudo tee -a /etc/sysctl.d/kubernetes.conf

# Apply the settings
sudo sysctl -p /etc/sysctl.d/kubernetes.conf

# Install CNI plugins (required for CNI plugins to work)
sudo mkdir -p /opt/cni/bin
cd /tmp
wget -q https://github.com/containernetworking/plugins/releases/download/v1.3.0/cni-plugins-linux-amd64-v1.3.0.tgz
sudo tar -xzf cni-plugins-linux-amd64-v1.3.0.tgz -C /opt/cni/bin/

# Create symlink so Kubernetes can find CNI plugins
sudo mkdir -p /usr/lib/cni
sudo ln -sf /opt/cni/bin/* /usr/lib/cni/

# Verify CNI plugins are available (Calico will use these)
echo "=== Verifying CNI Plugins ==="
ls -la /usr/lib/cni/ | grep -E "(bridge|host-local|loopback|portmap|tuning|vlan|bandwidth|firewall|sbr|static|dhcp|host-device|macvlan|ipvlan|ptp|vrf)"

# Clean up
rm -f cni-plugins-linux-amd64-v1.3.0.tgz
cd ~

echo "=== CNI Prerequisites Complete ==="
}
```

<!-- ```bash
{
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gpg
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
}
```

***DO ON ALL NODES***
- Note: If the above curl command fails, run this command, then run the curl command again. 
`sudo mkdir -p -m 755 /etc/apt/keyrings`

***DO ON ALL NODES***
`echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list`


***DO ON ALL NODES***
```bash
{
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
}
```

***DO ON ALL NODES***
**Verify Installation**
```bash
{
kubeadm version
kubectl version --client
kubelet --version
}
``` -->

<!-- Now you can proceed to the 'Creating A Cluster' page on the Kubeernetes documentation website -->
