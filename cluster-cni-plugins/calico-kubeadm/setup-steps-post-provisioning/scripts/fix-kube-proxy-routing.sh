#!/bin/bash

# Fix Kube-Proxy Routing Issue
# This script addresses common kube-proxy routing problems for NodePort services

set -e

# Node IPs from your machines.txt
SERVER_IP="54.164.109.60"
NODE_0_IP="98.80.9.220"
NODE_1_IP="54.196.171.115"

# SSH key path
SSH_KEY="k8s-key.pem"

echo "🔧 Fixing Kube-Proxy Routing Issue"
echo "=================================="
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

echo "1️⃣ Checking current kube-proxy status..."
echo "======================================="
run_on_node "$SERVER_IP" "Server (Control Plane)" "kubectl -n kube-system get pods -l component=kube-proxy -o wide"

echo "2️⃣ Restarting kube-proxy daemonset..."
echo "====================================="
run_on_node "$SERVER_IP" "Server (Control Plane)" "kubectl -n kube-system rollout restart daemonset kube-proxy"

echo "3️⃣ Waiting for kube-proxy pods to restart..."
echo "==========================================="
run_on_node "$SERVER_IP" "Server (Control Plane)" "kubectl -n kube-system rollout status daemonset kube-proxy --timeout=120s"

echo "4️⃣ Checking kube-proxy logs for errors..."
echo "========================================="
run_on_node "$SERVER_IP" "Server (Control Plane)" "kubectl -n kube-system logs -l component=kube-proxy --tail=20"

echo "5️⃣ Verifying iptables rules are updated..."
echo "=========================================="
run_on_node "$SERVER_IP" "Server (Control Plane)" "sudo iptables -t nat -L KUBE-NODEPORTS -n"

echo "6️⃣ Testing cross-node access..."
echo "==============================="
echo "Testing vote app from Node-0 to Node-1:"
run_on_node "$NODE_0_IP" "Node-0 (Worker)" "curl -s --connect-timeout 10 http://$NODE_1_IP:30001 | head -1 || echo 'Cross-node access still failing'"

echo "Testing result app from Node-1 to Node-0:"
run_on_node "$NODE_1_IP" "Node-1 (Worker)" "curl -s --connect-timeout 10 http://$NODE_0_IP:30002 | head -1 || echo 'Cross-node access still failing'"

echo "🎯 If cross-node access still fails, try switching to IPVS mode:"
echo "=============================================================="
echo "1. Edit kube-proxy configmap:"
echo "   kubectl -n kube-system edit configmap kube-proxy"
echo ""
echo "2. Change mode from '' to 'ipvs':"
echo "   mode: 'ipvs'"
echo ""
echo "3. Restart kube-proxy again:"
echo "   kubectl -n kube-system rollout restart daemonset kube-proxy"
echo ""
echo "4. Test cross-node access again"


