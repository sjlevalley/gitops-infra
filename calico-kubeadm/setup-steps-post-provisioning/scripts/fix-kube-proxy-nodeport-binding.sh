#!/bin/bash

# Fix Kube-Proxy NodePort Binding
# This script configures kube-proxy to bind NodePort services to all interfaces

set -e

# Node IPs from your machines.txt
SERVER_IP="54.164.109.60"
NODE_0_IP="98.80.9.220"
NODE_1_IP="54.196.171.115"

# SSH key path
SSH_KEY="k8s-key.pem"

echo "🔧 Fixing Kube-Proxy NodePort Binding"
echo "===================================="
echo ""

# Function to run command on a node
run_on_node() {
    local node_ip=$1
    local node_name=$2
    local command=$3
    
    echo "📋 Running on $node_name ($node_ip): $command"
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no admin@$node_ip "$command" 2>/dev/null || echo "  Command failed or no output"
    echo ""
}

echo "1️⃣ Updating kube-proxy configuration..."
echo "======================================"
run_on_node "$SERVER_IP" "Server (Control Plane)" "kubectl -n kube-system patch configmap kube-proxy --patch '{\"data\":{\"config.conf\":\"apiVersion: kubeproxy.config.k8s.io/v1alpha1\\nkind: KubeProxyConfiguration\\nmode: ipvs\\nnodePortAddresses: []\\n\"}}'"

echo "2️⃣ Restarting kube-proxy daemonset..."
echo "====================================="
run_on_node "$SERVER_IP" "Server (Control Plane)" "kubectl -n kube-system rollout restart daemonset kube-proxy"

echo "3️⃣ Waiting for kube-proxy pods to restart..."
echo "==========================================="
run_on_node "$SERVER_IP" "Server (Control Plane)" "kubectl -n kube-system rollout status daemonset kube-proxy --timeout=120s"

echo "4️⃣ Checking IPVS rules after restart..."
echo "======================================"
run_on_node "$SERVER_IP" "Server (Control Plane)" "sudo ipvsadm -L -n | grep -E '(30001|30002)'"

echo "5️⃣ Testing cross-node NodePort access..."
echo "======================================="
echo "Testing vote app (Node-1) from Node-0:"
run_on_node "$NODE_0_IP" "Node-0 (Worker)" "curl -s --connect-timeout 10 http://localhost:30001 | head -1 || echo 'Cross-node access failed'"

echo "Testing result app (Node-0) from Node-1:"
run_on_node "$NODE_1_IP" "Node-1 (Worker)" "curl -s --connect-timeout 10 http://localhost:30002 | head -1 || echo 'Cross-node access failed'"

echo "Testing vote app (Node-1) from Master:"
run_on_node "$SERVER_IP" "Server (Control Plane)" "curl -s --connect-timeout 10 http://localhost:30001 | head -1 || echo 'Cross-node access failed'"

echo "🎯 If still failing, try alternative approach:"
echo "============================================="
echo "1. Check if NodePort services are using externalTrafficPolicy: Local"
echo "2. Change to externalTrafficPolicy: Cluster"
echo "3. Or try using the private IP addresses directly"


