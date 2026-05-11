#!/bin/bash

# Diagnose Kube-Proxy Routing Issue
# This script helps identify why NodePort services only work on the node where pods are running

set -e

# Node IPs from your machines.txt
SERVER_IP="54.164.109.60"
NODE_0_IP="98.80.9.220"
NODE_1_IP="54.196.171.115"

# SSH key path
SSH_KEY="k8s-key.pem"

echo "🔍 Diagnosing Kube-Proxy Routing Issue"
echo "======================================"
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

# 1. Check kube-proxy mode and configuration
echo "1️⃣ Checking kube-proxy configuration..."
echo "======================================="
run_on_node "$SERVER_IP" "Server (Control Plane)" "kubectl -n kube-system get configmap kube-proxy -o yaml | grep -A 10 -B 5 mode"

# 2. Check kube-proxy logs for errors
echo "2️⃣ Checking kube-proxy logs for errors..."
echo "========================================="
run_on_node "$SERVER_IP" "Server (Control Plane)" "kubectl -n kube-system logs -l component=kube-proxy --tail=50 | grep -i error || echo 'No errors found in logs'"

# 3. Check iptables rules for NodePorts on each node
echo "3️⃣ Checking iptables NodePort rules on each node..."
echo "=================================================="
run_on_node "$SERVER_IP" "Server (Control Plane)" "sudo iptables -t nat -L KUBE-NODEPORTS -n"
run_on_node "$NODE_0_IP" "Node-0 (Worker)" "sudo iptables -t nat -L KUBE-NODEPORTS -n"
run_on_node "$NODE_1_IP" "Node-1 (Worker)" "sudo iptables -t nat -L KUBE-NODEPORTS -n"

# 4. Check if kube-proxy is running on all nodes
echo "4️⃣ Checking kube-proxy pod status..."
echo "===================================="
run_on_node "$SERVER_IP" "Server (Control Plane)" "kubectl -n kube-system get pods -l component=kube-proxy -o wide"

# 5. Check kube-proxy daemonset status
echo "5️⃣ Checking kube-proxy daemonset status..."
echo "=========================================="
run_on_node "$SERVER_IP" "Server (Control Plane)" "kubectl -n kube-system get daemonset kube-proxy -o wide"

# 6. Test cross-node connectivity
echo "6️⃣ Testing cross-node connectivity..."
echo "====================================="
echo "Testing from Node-0 to Node-1 (where vote pod is running):"
run_on_node "$NODE_0_IP" "Node-0 (Worker)" "curl -v --connect-timeout 10 http://$NODE_1_IP:30001 2>&1 | head -10 || echo 'Cross-node access failed'"

echo "Testing from Node-1 to Node-0 (where result pod is running):"
run_on_node "$NODE_1_IP" "Node-1 (Worker)" "curl -v --connect-timeout 10 http://$NODE_0_IP:30002 2>&1 | head -10 || echo 'Cross-node access failed'"

# 7. Check if kube-proxy is binding to the correct interface
echo "7️⃣ Checking kube-proxy binding..."
echo "================================="
run_on_node "$SERVER_IP" "Server (Control Plane)" "kubectl -n kube-system logs -l component=kube-proxy | grep -i bind || echo 'No binding info found'"

# 8. Check network connectivity between nodes
echo "8️⃣ Checking network connectivity between nodes..."
echo "================================================="
run_on_node "$SERVER_IP" "Server (Control Plane)" "ping -c 3 $NODE_0_IP && ping -c 3 $NODE_1_IP"

# 9. Check if NodePort services are properly configured
echo "9️⃣ Checking NodePort service configuration..."
echo "============================================="
run_on_node "$SERVER_IP" "Server (Control Plane)" "kubectl get services -o wide"
run_on_node "$SERVER_IP" "Server (Control Plane)" "kubectl describe service vote"
run_on_node "$SERVER_IP" "Server (Control Plane)" "kubectl describe service result"

echo "🔧 Potential Solutions:"
echo "======================"
echo "1. Restart kube-proxy: kubectl -n kube-system rollout restart daemonset kube-proxy"
echo "2. Switch to IPVS mode: Edit kube-proxy configmap and set mode: 'ipvs'"
echo "3. Check if kube-proxy is running on all nodes"
echo "4. Verify iptables rules are consistent across all nodes"
echo "5. Check if there are any network policies blocking traffic"


