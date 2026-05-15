#!/bin/bash

# Comprehensive NodePort Fix
# This script tries multiple approaches to fix cross-node NodePort access

set -e

# Node IPs from your machines.txt
SERVER_IP="54.164.109.60"
NODE_0_IP="98.80.9.220"
NODE_1_IP="54.196.171.115"

# SSH key path
SSH_KEY="k8s-key.pem"

echo "🔧 Comprehensive NodePort Fix"
echo "============================"
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

echo "1️⃣ Checking current service configuration..."
echo "==========================================="
run_on_node "$SERVER_IP" "Server (Control Plane)" "kubectl get services -o wide"

echo "2️⃣ Checking if services are using externalTrafficPolicy: Local..."
echo "=============================================================="
run_on_node "$SERVER_IP" "Server (Control Plane)" "kubectl get services -o yaml | grep -A 2 -B 2 externalTrafficPolicy"

echo "3️⃣ Changing services to externalTrafficPolicy: Cluster..."
echo "========================================================"
run_on_node "$SERVER_IP" "Server (Control Plane)" "kubectl patch service vote -p '{\"spec\":{\"externalTrafficPolicy\":\"Cluster\"}}'"
run_on_node "$SERVER_IP" "Server (Control Plane)" "kubectl patch service result -p '{\"spec\":{\"externalTrafficPolicy\":\"Cluster\"}}'"

echo "4️⃣ Restarting kube-proxy with full configuration..."
echo "=================================================="
run_on_node "$SERVER_IP" "Server (Control Plane)" "kubectl -n kube-system patch configmap kube-proxy --patch '{\"data\":{\"config.conf\":\"apiVersion: kubeproxy.config.k8s.io/v1alpha1\\nkind: KubeProxyConfiguration\\nmode: ipvs\\nnodePortAddresses: []\\nbindAddress: 0.0.0.0\\n\"}}'"

echo "5️⃣ Restarting kube-proxy daemonset..."
echo "====================================="
run_on_node "$SERVER_IP" "Server (Control Plane)" "kubectl -n kube-system rollout restart daemonset kube-proxy"

echo "6️⃣ Waiting for kube-proxy pods to restart..."
echo "==========================================="
run_on_node "$SERVER_IP" "Server (Control Plane)" "kubectl -n kube-system rollout status daemonset kube-proxy --timeout=120s"

echo "7️⃣ Checking IPVS rules after restart..."
echo "======================================"
run_on_node "$SERVER_IP" "Server (Control Plane)" "sudo ipvsadm -L -n | grep -E '(30001|30002)'"

echo "8️⃣ Testing multiple access methods..."
echo "===================================="
echo "Testing localhost access:"
run_on_node "$NODE_0_IP" "Node-0 (Worker)" "curl -s --connect-timeout 5 http://localhost:30001 | head -1 || echo 'localhost failed'"

echo "Testing private IP access:"
run_on_node "$NODE_0_IP" "Node-0 (Worker)" "curl -s --connect-timeout 5 http://172.31.30.214:30001 | head -1 || echo 'private IP failed'"

echo "Testing public IP access:"
run_on_node "$NODE_0_IP" "Node-0 (Worker)" "curl -s --connect-timeout 5 http://54.164.109.60:30001 | head -1 || echo 'public IP failed'"

echo "9️⃣ If all methods fail, try switching back to iptables mode..."
echo "============================================================"
echo "kubectl -n kube-system patch configmap kube-proxy --patch '{\"data\":{\"config.conf\":\"apiVersion: kubeproxy.config.k8s.io/v1alpha1\\nkind: KubeProxyConfiguration\\nmode: iptables\\n\"}}'"
echo "kubectl -n kube-system rollout restart daemonset kube-proxy"


