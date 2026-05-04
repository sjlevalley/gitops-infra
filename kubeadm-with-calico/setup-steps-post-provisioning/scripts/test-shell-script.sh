#!/bin/bash

# =============================================================================
# Kubernetes Cluster Setup with Kubeadm - Automated Script
# =============================================================================
# This script automates the complete setup of a Kubernetes cluster using kubeadm
# It combines all 4 manual steps into a single automated process
#
# Prerequisites:
# - 3 EC2 instances (1 master, 2 workers) running Debian 12
# - SSH access with key-based authentication
# - Run from a machine that can reach all nodes over SSH (e.g. your workstation)
# =============================================================================

set -euo pipefail

# =============================================================================
# CONFIGURATION VARIABLES
# =============================================================================

# Node IPs (update these with your actual IPs from Terraform output)
MASTER_IP=""
WORKER_IPS=("" "")

# Kubernetes version
KUBERNETES_VERSION="1.31"

# CNI Plugin choice: "flannel" or "calico"
CNI_PLUGIN="flannel"

# Network configuration
POD_NETWORK_CIDR="10.244.0.0/16"

# SSH configuration
SSH_USER="admin"
SSH_KEY="~/.ssh/id_rsa"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to execute commands on remote nodes
run_remote() {
    local node_ip="$1"
    local command="$2"
    local description="$3"
    
    log_info "Running on $node_ip: $description"
    ssh $SSH_OPTS -i "$SSH_KEY" "$SSH_USER@$node_ip" "$command"
}

# Function to execute commands on all nodes
run_all_nodes() {
    local command="$1"
    local description="$2"
    
    log_info "Running on all nodes: $description"
    
    # Run on master
    run_remote "$MASTER_IP" "$command" "$description (master)"
    
    # Run on workers
    for worker_ip in "${WORKER_IPS[@]}"; do
        run_remote "$worker_ip" "$command" "$description (worker)"
    done
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check if required commands exist
    local required_commands=("ssh" "scp" "curl" "wget")
    for cmd in "${required_commands[@]}"; do
        if ! command_exists "$cmd"; then
            log_error "Required command '$cmd' not found. Please install it first."
            exit 1
        fi
    done
    
    # Check if SSH key exists
    if [[ ! -f "$SSH_KEY" ]]; then
        log_error "SSH key not found at $SSH_KEY"
        exit 1
    fi
    
    # Check if IPs are configured
    if [[ -z "$MASTER_IP" ]] || [[ -z "${WORKER_IPS[0]}" ]] || [[ -z "${WORKER_IPS[1]}" ]]; then
        log_error "Please configure MASTER_IP and WORKER_IPS in the script"
        exit 1
    fi
    
    # Test SSH connectivity
    log_info "Testing SSH connectivity..."
    for ip in "$MASTER_IP" "${WORKER_IPS[@]}"; do
        if ! ssh $SSH_OPTS -i "$SSH_KEY" "$SSH_USER@$ip" "echo 'SSH test successful'" >/dev/null 2>&1; then
            log_error "Cannot connect to $ip via SSH"
            exit 1
        fi
    done
    
    log_success "Prerequisites validation completed"
}

# =============================================================================
# STEP 1: INSTALL KUBEADM, KUBELET, KUBECTL
# =============================================================================

install_kubeadm() {
    log_info "Step 1: Installing kubeadm, kubelet, and kubectl on all nodes"
    
    local install_script='
    # Update package index
    sudo apt-get update
    
    # Install required packages
    sudo apt-get install -y apt-transport-https ca-certificates curl gpg
    
    # Create keyrings directory if it doesn'\''t exist
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
    
    # Verify installation
    echo "=== Kubeadm Version ==="
    kubeadm version
    echo "=== Kubectl Version ==="
    kubectl version --client
    echo "=== Kubelet Version ==="
    kubelet --version
    '
    
    run_all_nodes "$install_script" "Installing Kubernetes components"
    log_success "Step 1 completed: Kubernetes components installed"
}

# =============================================================================
# STEP 2: INSTALL CONTAINER RUNTIME (CONTAINERD)
# =============================================================================

install_containerd() {
    log_info "Step 2: Installing and configuring containerd on all nodes"
    
    local containerd_script='
    # Update package index
    sudo apt update
    
    # Install containerd
    sudo apt install -y containerd
    
    # Verify cgroup driver (should be systemd)
    echo "=== Checking cgroup driver ==="
    ps -p 1
    
    # Create containerd configuration
    sudo tee /etc/containerd/config.toml > /dev/null << '\''EOF'\''
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
    
    # Restart containerd
    sudo systemctl restart containerd
    
    # Enable containerd to start on boot
    sudo systemctl enable containerd
    
    # Verify containerd is running
    echo "=== Containerd Status ==="
    sudo systemctl status containerd --no-pager
    echo "=== Containerd Active Status ==="
    sudo systemctl is-active containerd
    '
    
    run_all_nodes "$containerd_script" "Installing and configuring containerd"
    log_success "Step 2 completed: Containerd installed and configured"
}

# =============================================================================
# STEP 3: INITIALIZE CONTROL PLANE NODE
# =============================================================================

init_control_plane() {
    log_info "Step 3: Initializing control plane node"
    
    # Enable IP forwarding on all nodes
    local ip_forward_script='
    # Enable IP forwarding temporarily
    sudo sysctl net.ipv4.ip_forward=1
    
    # Make IP forwarding permanent
    echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
    
    # Verify IP forwarding is enabled
    echo "IP forwarding status: $(cat /proc/sys/net/ipv4/ip_forward)"
    '
    
    run_all_nodes "$ip_forward_script" "Enabling IP forwarding"
    
    # Set hostnames
    log_info "Setting hostnames on all nodes"
    run_remote "$MASTER_IP" "sudo hostnamectl set-hostname master" "Setting master hostname"
    run_remote "${WORKER_IPS[0]}" "sudo hostnamectl set-hostname node-0" "Setting node-0 hostname"
    run_remote "${WORKER_IPS[1]}" "sudo hostnamectl set-hostname node-1" "Setting node-1 hostname"
    
    # Initialize the cluster on master node
    log_info "Initializing Kubernetes cluster on master node"
    local init_command="sudo kubeadm init --apiserver-advertise-address $MASTER_IP --pod-network-cidr $POD_NETWORK_CIDR --upload-certs"
    
    log_info "Running: $init_command"
    local init_output
    init_output=$(ssh $SSH_OPTS -i "$SSH_KEY" "$SSH_USER@$MASTER_IP" "$init_command")
    
    # Extract join command from output
    local join_command
    join_command=$(echo "$init_output" | grep "kubeadm join" | head -1)
    
    if [[ -z "$join_command" ]]; then
        log_error "Failed to extract join command from kubeadm init output"
        exit 1
    fi
    
    log_success "Join command extracted: $join_command"
    
    # Configure kubectl for regular user on master
    log_info "Configuring kubectl for regular user on master"
    local kubectl_config_script='
    # Create .kube directory
    mkdir -p $HOME/.kube
    
    # Copy admin configuration
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    
    # Set proper ownership
    sudo chown $(id -u):$(id -g) $HOME/.kube/config
    
    # Verify kubectl configuration
    kubectl cluster-info
    '
    
    run_remote "$MASTER_IP" "$kubectl_config_script" "Configuring kubectl"
    
    # Store join command for later use
    echo "$join_command" > /tmp/kubeadm-join-command.txt
    log_success "Step 3 completed: Control plane initialized"
}

# =============================================================================
# STEP 4: INSTALL CNI PLUGIN
# =============================================================================

install_cni_plugin() {
    log_info "Step 4: Installing CNI plugin ($CNI_PLUGIN)"
    
    if [[ "$CNI_PLUGIN" == "flannel" ]]; then
        install_flannel
    elif [[ "$CNI_PLUGIN" == "calico" ]]; then
        install_calico
    else
        log_error "Unsupported CNI plugin: $CNI_PLUGIN"
        exit 1
    fi
}

install_flannel() {
    log_info "Installing Flannel CNI plugin"
    
    # Prepare nodes for Flannel
    local flannel_prep_script='
    # Load the br_netfilter module
    sudo modprobe br_netfilter
    
    # Make br_netfilter permanent
    echo "br_netfilter" | sudo tee -a /etc/modules
    
    # Configure bridge settings
    echo "net.bridge.bridge-nf-call-iptables = 1" | sudo tee -a /etc/sysctl.d/kubernetes.conf
    echo "net.bridge.bridge-nf-call-ip6tables = 1" | sudo tee -a /etc/sysctl.d/kubernetes.conf
    
    # Apply the settings
    sudo sysctl -p /etc/sysctl.d/kubernetes.conf
    
    # Install CNI plugins
    sudo mkdir -p /opt/cni/bin
    cd /tmp
    wget -q https://github.com/containernetworking/plugins/releases/download/v1.3.0/cni-plugins-linux-amd64-v1.3.0.tgz
    sudo tar -xzf cni-plugins-linux-amd64-v1.3.0.tgz -C /opt/cni/bin/
    
    # Create symlink so Kubernetes can find CNI plugins
    sudo mkdir -p /usr/lib/cni
    sudo ln -sf /opt/cni/bin/* /usr/lib/cni/
    
    # Clean up
    rm -f cni-plugins-linux-amd64-v1.3.0.tgz
    '
    
    run_all_nodes "$flannel_prep_script" "Preparing nodes for Flannel"
    
    # Deploy Flannel on master node
    log_info "Deploying Flannel on master node"
    run_remote "$MASTER_IP" "kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml" "Deploying Flannel"
    
    log_success "Flannel CNI plugin installed"
}

install_calico() {
    log_info "Installing Calico CNI plugin"
    
    # Deploy Calico on master node
    run_remote "$MASTER_IP" "kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/calico.yaml" "Deploying Calico"
    
    log_success "Calico CNI plugin installed"
}

# =============================================================================
# JOIN WORKER NODES
# =============================================================================

join_worker_nodes() {
    log_info "Joining worker nodes to the cluster"
    
    # Read join command from file
    if [[ ! -f "/tmp/kubeadm-join-command.txt" ]]; then
        log_error "Join command file not found. Please run Step 3 first."
        exit 1
    fi
    
    local join_command
    join_command=$(cat /tmp/kubeadm-join-command.txt)
    
    # Join each worker node
    for worker_ip in "${WORKER_IPS[@]}"; do
        log_info "Joining worker node: $worker_ip"
        run_remote "$worker_ip" "$join_command" "Joining worker node to cluster"
    done
    
    log_success "All worker nodes joined successfully"
}

# =============================================================================
# VERIFICATION AND CLEANUP
# =============================================================================

verify_cluster() {
    log_info "Verifying cluster health"
    
    # Wait for nodes to be ready
    log_info "Waiting for nodes to be ready..."
    sleep 30
    
    # Check cluster status
    local verification_script='
    echo "=== Cluster Info ==="
    kubectl cluster-info
    
    echo "=== Node Status ==="
    kubectl get nodes
    
    echo "=== Pod Status in kube-system ==="
    kubectl get pods -n kube-system
    
    echo "=== CNI Pods ==="
    if [[ "'$CNI_PLUGIN'" == "flannel" ]]; then
        kubectl get pods -n kube-flannel
    elif [[ "'$CNI_PLUGIN'" == "calico" ]]; then
        kubectl get pods -n kube-system | grep calico
    fi
    '
    
    run_remote "$MASTER_IP" "$verification_script" "Verifying cluster health"
    
    # Clean up temporary files
    rm -f /tmp/kubeadm-join-command.txt
    
    log_success "Cluster verification completed"
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    echo "=========================================="
    echo "Kubernetes Cluster Setup with Kubeadm"
    echo "=========================================="
    echo "Master IP: $MASTER_IP"
    echo "Worker IPs: ${WORKER_IPS[*]}"
    echo "Kubernetes Version: $KUBERNETES_VERSION"
    echo "CNI Plugin: $CNI_PLUGIN"
    echo "Pod Network CIDR: $POD_NETWORK_CIDR"
    echo "=========================================="
    
    # Validate prerequisites
    validate_prerequisites
    
    # Execute all steps
    install_kubeadm
    install_containerd
    init_control_plane
    install_cni_plugin
    join_worker_nodes
    verify_cluster
    
    echo "=========================================="
    log_success "Kubernetes cluster setup completed successfully!"
    echo "=========================================="
    echo ""
    echo "Next steps:"
    echo "1. SSH into master node: ssh -i $SSH_KEY $SSH_USER@$MASTER_IP"
    echo "2. Verify cluster: kubectl get nodes"
    echo "3. Deploy your applications!"
    echo ""
}

# =============================================================================
# SCRIPT EXECUTION
# =============================================================================

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Script is being executed directly
    main "$@"
fi
