# Step 01-02 - Combined Setup: Kubeadm Installation & Container Runtime

**Run the following command on all 3 Nodes (master, node-0, node-1)**
***Note that the 'machines.txt' file in the root directory has the commands to SSH into the master node, as well as the two worker nodes.

**Set up terminals in each of the 3 Nodes (master, node-0, node-1)**

This combined step includes:
- Installing `conntrack` (required by `kubeadm` preflight for `kubeadm init` and `kubeadm join`)
- Installing Kubeadm, Kubelet, and Kubectl
- Installing and configuring Containerd as the container runtime
- Setting up CNI prerequisites
- Configuring systemd cgroup driver

***DO ON ALL NODES***
```bash
{
    echo "=== Starting Combined Kubernetes Setup on $(hostname) ==="
    
    # ===========================================
    # PART 1: KUBEADM INSTALLATION
    # ===========================================
    echo "=== Part 1: Installing Kubeadm, Kubelet, and Kubectl ==="
    
    # Update package index
    sudo apt-get update
    
    # Install required packages
    sudo apt-get install -y apt-transport-https ca-certificates curl gpg
    
    # conntrack: required by kubeadm preflight on every node (control plane + workers)
    sudo apt-get update
    sudo apt-get install -y conntrack
    
    # Create keyrings directory
    sudo mkdir -p -m 755 /etc/apt/keyrings
    
    # Download and add Kubernetes GPG key
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    
    # Add Kubernetes repository
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list
    
    # Update package index again
    sudo apt-get update
    
    # Install Kubernetes components
    sudo apt-get install -y kubelet kubeadm kubectl
    
    # Hold packages to prevent automatic updates
    sudo apt-mark hold kubelet kubeadm kubectl
    
    # Verify Kubernetes installation
    echo "=== Kubernetes Components Installed ==="
    echo "Kubeadm Version:"
    kubeadm version
    echo "Kubectl Version:"
    kubectl version --client
    echo "Kubelet Version:"
    kubelet --version
    
    # ===========================================
    # PART 2: CONTAINER RUNTIME (CONTAINERD)
    # ===========================================
    echo "=== Part 2: Installing and Configuring Containerd ==="
    
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
      bin_dir = "/opt/cni/bin"
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
    
    # ===========================================
    # PART 3: CNI PREREQUISITES
    # ===========================================
    echo "=== Part 3: Setting up CNI Prerequisites ==="
    
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
    
    # containerd bin_dir must be /opt/cni/bin (above): Calico installs calico + calico-ipam here;
    # using /usr/lib/cni breaks pods with: failed to find plugin "calico" in path [/usr/lib/cni]
    
    # Verify base CNI plugins (Calico adds calico binaries here when calico-node runs)
    echo "=== Verifying CNI Plugins ==="
    ls -la /opt/cni/bin/ | grep -E "(bridge|host-local|loopback|portmap|tuning|vlan|bandwidth|firewall|sbr|static|dhcp|host-device|macvlan|ipvlan|ptp|vrf)"
    
    # Clean up
    rm -f cni-plugins-linux-amd64-v1.3.0.tgz
    cd ~
    
    echo "=== Combined Setup Complete on $(hostname) ==="
    echo "=== All components ready for cluster initialization ==="
}
```

## What this combined script does:

1. **Installs `conntrack`** so kubeadm preflight passes (`FileExisting-conntrack`)
2. **Installs Kubernetes components** (kubeadm, kubelet, kubectl)
3. **Configures package repositories** and holds packages to prevent auto-updates
4. **Installs and configures containerd** as the container runtime
5. **Sets up systemd cgroup driver** for both kubelet and containerd
6. **Configures networking prerequisites** (IP forwarding, bridge settings)
7. **Installs CNI plugins** required for pod networking
8. **Verifies all installations** and configurations

## Benefits of combining:

- **Single execution**: Run once on each node instead of two separate steps
- **Logical flow**: Dependencies are handled in the correct order
- **Better error handling**: If something fails, you know exactly where
- **Time saving**: Reduces the number of manual steps
- **Consistency**: Ensures all nodes are configured identically

## Next Steps:

After running this combined script on all nodes, you can proceed to:
- **Step 03**: Initializing the Control Plane Node (master only)
- **Step 04**: Installing CNI Plugin (Calico or Flannel)
- **Step 05**: Deploying Applications
