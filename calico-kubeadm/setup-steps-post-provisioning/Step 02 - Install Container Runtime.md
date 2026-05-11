# Step 02 - Install Container Runtime

> **⚠️ RECOMMENDED**: This step has been combined with Step 01 for efficiency. See **[Step 01-02 - Combined Setup](Step%2001-02%20-%20Combined%20Setup.md)** for the recommended approach.

*****Verifying the cgroup driver*****
- If the cgroup driver is NOT set to systemd, go tot the section in the Kubernetes documentaion that talks about 'Configuring the kubelet cgroup driver'. 
- Note that after v1.22, if no cgroup driver is set, it will default to systemd
- If needed, the documentation shows how to manually set it to be systemd usinig a configuration yaml file.

*****Setting the container runtime (containerd) cgroup driver to systemd*****
- Note that this step is not automatic and must be done. 
- Instructions can be found on the 'Container Runtimes > containerd page under the 'Configuring the systemd cgroup driver' section

 

***RUN ON ALL NODES***
```bash
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


