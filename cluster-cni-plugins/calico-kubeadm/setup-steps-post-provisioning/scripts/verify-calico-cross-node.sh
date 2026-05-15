#!/bin/bash

# Verify Calico Cross-Node Communication Setup
# This script checks if Calico is properly configured for cross-node communication

set -e

# Node IPs from your machines.txt
SERVER_IP="54.164.109.60"
NODE_0_IP="98.80.9.220"
NODE_1_IP="54.196.171.115"

# SSH key path
SSH_KEY="k8s-key.pem"

echo "🔍 Verifying Calico Cross-Node Communication Setup"
echo "=================================================="
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

echo "1️⃣ Checking Calico Installation Status..."
echo "========================================"
run_on_node "$SERVER_IP" "Server (Control Plane)" "kubectl get pods -n calico-system"

echo "2️⃣ Checking Node Status..."
echo "========================="
run_on_node "$SERVER_IP" "Server (Control Plane)" "kubectl get nodes -o wide"

echo "3️⃣ Checking Calico IP Pools..."
echo "============================="
run_on_node "$SERVER_IP" "Server (Control Plane)" "kubectl get ippools -o wide"

echo "4️⃣ Checking Calico Node Status..."
echo "================================"
run_on_node "$SERVER_IP" "Server (Control Plane)" "kubectl get nodes -o custom-columns=NAME:.metadata.name,STATUS:.status.conditions[-1].type,INTERNAL-IP:.status.addresses[0].address,EXTERNAL-IP:.status.addresses[1].address"

echo "5️⃣ Checking BGP Configuration..."
echo "==============================="
run_on_node "$SERVER_IP" "Server (Control Plane)" "kubectl get bgpconfigurations -o yaml"

echo "6️⃣ Checking Calico Node Configuration..."
echo "======================================="
run_on_node "$SERVER_IP" "Server (Control Plane)" "kubectl get caliconodes -o wide"

echo "7️⃣ Testing Pod-to-Pod Communication..."
echo "====================================="
run_on_node "$SERVER_IP" "Server (Control Plane)" "kubectl run test-pod-1 --image=nginx --rm -it --restart=Never -- curl -s http://kubernetes.default.svc.cluster.local | head -1"

echo "8️⃣ Checking CNI Configuration on All Nodes..."
echo "============================================="
run_on_node "$SERVER_IP" "Server (Control Plane)" "cat /etc/cni/net.d/10-calico.conflist"
run_on_node "$NODE_0_IP" "Node-0 (Worker)" "cat /etc/cni/net.d/10-calico.conflist"
run_on_node "$NODE_1_IP" "Node-1 (Worker)" "cat /etc/cni/net.d/10-calico.conflist"

echo "9️⃣ Checking Calico Logs for Errors..."
echo "===================================="
run_on_node "$SERVER_IP" "Server (Control Plane)" "kubectl logs -n calico-system -l k8s-app=calico-node --tail=10"

echo "🔟 Testing Cross-Node NodePort Access..."
echo "======================================="
echo "Testing vote app from different nodes:"
run_on_node "$SERVER_IP" "Server (Control Plane)" "curl -s --connect-timeout 5 http://localhost:30001 | head -1 || echo 'Master node access failed'"
run_on_node "$NODE_0_IP" "Node-0 (Worker)" "curl -s --connect-timeout 5 http://localhost:30001 | head -1 || echo 'Node-0 access failed'"
run_on_node "$NODE_1_IP" "Node-1 (Worker)" "curl -s --connect-timeout 5 http://localhost:30001 | head -1 || echo 'Node-1 access failed'"

echo "🧪 Testing External Access..."
echo "============================"
echo "Test these URLs in your browser:"
echo "  Vote app: http://$SERVER_IP:30001"
echo "  Vote app: http://$NODE_0_IP:30001"
echo "  Vote app: http://$NODE_1_IP:30001"
echo ""

echo "📋 Troubleshooting Checklist:"
echo "============================="
echo "✅ All Calico pods should be Running"
echo "✅ All nodes should show as Ready"
echo "✅ IP pools should be configured with 10.244.0.0/16"
echo "✅ CNI configuration should exist on all nodes"
echo "✅ Cross-node NodePort access should work"
echo "✅ External browser access should work"
echo ""

echo "🔧 If cross-node access fails, check:"
echo "===================================="
echo "1. Security group rules (ports 30000-32767)"
echo "2. Calico BGP configuration"
echo "3. Node network connectivity"
echo "4. Application deployment status"
