#!/bin/bash

# Switch Kube-Proxy to IPVS Mode
# This script switches kube-proxy from iptables to IPVS mode to fix cross-node NodePort routing

set -e

# Node IPs from your machines.txt
SERVER_IP="54.164.109.60"
NODE_0_IP="98.80.9.220"
NODE_1_IP="54.196.171.115"

# SSH key path
SSH_KEY="k8s-key.pem"

echo "🔧 Switching Kube-Proxy to IPVS Mode"
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

echo "1️⃣ Checking current kube-proxy mode..."
echo "====================================="
run_on_node "$SERVER_IP" "Server (Control Plane)" "kubectl -n kube-system get configmap kube-proxy -o yaml | grep -A 5 -B 5 mode"

echo "2️⃣ Switching kube-proxy to IPVS mode..."
echo "======================================"
run_on_node "$SERVER_IP" "Server (Control Plane)" "kubectl -n kube-system patch configmap kube-proxy --patch '{\"data\":{\"config.conf\":\"apiVersion: kubeproxy.config.k8s.io/v1alpha1\\nkind: KubeProxyConfiguration\\nmode: ipvs\\n\"}}'"

echo "3️⃣ Restarting kube-proxy daemonset..."
echo "====================================="
run_on_node "$SERVER_IP" "Server (Control Plane)" "kubectl -n kube-system rollout restart daemonset kube-proxy"

echo "4️⃣ Waiting for kube-proxy pods to restart..."
echo "==========================================="
run_on_node "$SERVER_IP" "Server (Control Plane)" "kubectl -n kube-system rollout status daemonset kube-proxy --timeout=120s"

echo "5️⃣ Verifying kube-proxy is in IPVS mode..."
echo "========================================="
run_on_node "$SERVER_IP" "Server (Control Plane)" "kubectl -n kube-system get configmap kube-proxy -o yaml | grep -A 5 -B 5 mode"

echo "6️⃣ Checking kube-proxy logs..."
echo "============================="
run_on_node "$SERVER_IP" "Server (Control Plane)" "kubectl -n kube-system logs -l component=kube-proxy --tail=20"

echo "7️⃣ Testing cross-node NodePort access..."
echo "======================================="
echo "Testing vote app (Node-1) from Node-0:"
run_on_node "$NODE_0_IP" "Node-0 (Worker)" "curl -s --connect-timeout 10 http://localhost:30001 | head -1 || echo 'Cross-node access failed'"

echo "Testing result app (Node-0) from Node-1:"
run_on_node "$NODE_1_IP" "Node-1 (Worker)" "curl -s --connect-timeout 10 http://localhost:30002 | head -1 || echo 'Cross-node access failed'"

echo "Testing vote app (Node-1) from Master:"
run_on_node "$SERVER_IP" "Server (Control Plane)" "curl -s --connect-timeout 10 http://localhost:30001 | head -1 || echo 'Cross-node access failed'"

echo "🎯 If cross-node access still fails, check IPVS rules:"
echo "===================================================="
echo "On any node, run:"
echo "  sudo ipvsadm -L -n"
echo ""
echo "You should see rules for ports 30001 and 30002"


