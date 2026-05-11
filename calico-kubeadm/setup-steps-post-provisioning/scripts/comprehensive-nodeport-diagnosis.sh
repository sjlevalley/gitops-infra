#!/bin/bash

# Comprehensive NodePort Diagnosis Script
# This script runs all the diagnostic commands to identify the external access issue

set -e

# Node IPs from your machines.txt
SERVER_IP="54.164.109.60"
NODE_0_IP="98.80.9.220"
NODE_1_IP="54.196.171.115"

# SSH key path
SSH_KEY="k8s-key.pem"

echo "🔍 Comprehensive NodePort Diagnosis"
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

# 1. Check kube-proxy logs
echo "1️⃣ Checking kube-proxy logs..."
echo "================================"
run_on_node "$SERVER_IP" "Server (Control Plane)" "kubectl -n kube-system logs -l component=kube-proxy --tail=20"

# 2. Check iptables NAT rules for NodePorts
echo "2️⃣ Checking iptables NAT rules for NodePorts..."
echo "==============================================="
run_on_node "$SERVER_IP" "Server (Control Plane)" "sudo iptables -t nat -L KUBE-NODEPORTS"

# 3. Check pod locations
echo "3️⃣ Checking pod locations..."
echo "============================="
run_on_node "$SERVER_IP" "Server (Control Plane)" "kubectl get pods -o wide"

# 4. Check services
echo "4️⃣ Checking services..."
echo "======================="
run_on_node "$SERVER_IP" "Server (Control Plane)" "kubectl get services"

# 5. Check TX checksum status on all nodes
echo "5️⃣ Checking TX checksum status on all nodes..."
echo "=============================================="
run_on_node "$SERVER_IP" "Server (Control Plane)" "if ip link show flannel.1 >/dev/null 2>&1; then ethtool -k flannel.1 | grep tx-checksum-ip-generic; else echo 'flannel.1 not found'; fi"
run_on_node "$NODE_0_IP" "Node-0 (Worker)" "if ip link show flannel.1 >/dev/null 2>&1; then ethtool -k flannel.1 | grep tx-checksum-ip-generic; else echo 'flannel.1 not found'; fi"
run_on_node "$NODE_1_IP" "Node-1 (Worker)" "if ip link show flannel.1 >/dev/null 2>&1; then ethtool -k flannel.1 | grep tx-checksum-ip-generic; else echo 'flannel.1 not found'; fi"

# 6. Check systemd service status
echo "6️⃣ Checking systemd service status..."
echo "====================================="
run_on_node "$SERVER_IP" "Server (Control Plane)" "sudo systemctl status flannel-tx-checksum-fix.service --no-pager 2>/dev/null || echo 'Service not found'"
run_on_node "$NODE_0_IP" "Node-0 (Worker)" "sudo systemctl status flannel-tx-checksum-fix.service --no-pager 2>/dev/null || echo 'Service not found'"
run_on_node "$NODE_1_IP" "Node-1 (Worker)" "sudo systemctl status flannel-tx-checksum-fix.service --no-pager 2>/dev/null || echo 'Service not found'"

# 7. Test local NodePort access
echo "7️⃣ Testing local NodePort access..."
echo "==================================="
run_on_node "$NODE_0_IP" "Node-0 (Worker)" "curl -s --connect-timeout 5 http://localhost:30001 | head -1 || echo 'Local access failed'"
run_on_node "$NODE_1_IP" "Node-1 (Worker)" "curl -s --connect-timeout 5 http://localhost:30001 | head -1 || echo 'Local access failed'"

# 8. Check network interfaces
echo "8️⃣ Checking network interfaces..."
echo "================================="
run_on_node "$SERVER_IP" "Server (Control Plane)" "ip link show | grep -E '(eth0|flannel)'"
run_on_node "$NODE_0_IP" "Node-0 (Worker)" "ip link show | grep -E '(eth0|flannel)'"
run_on_node "$NODE_1_IP" "Node-1 (Worker)" "ip link show | grep -E '(eth0|flannel)'"

# 9. Check kube-proxy configuration
echo "9️⃣ Checking kube-proxy configuration..."
echo "======================================="
run_on_node "$SERVER_IP" "Server (Control Plane)" "kubectl -n kube-system get configmap kube-proxy -o yaml | grep -A 5 -B 5 mode"

echo "🌐 External Access Test URLs:"
echo "============================="
echo "Vote app:"
echo "  http://$SERVER_IP:30001"
echo "  http://$NODE_0_IP:30001"
echo "  http://$NODE_1_IP:30001"
echo ""
echo "Result app:"
echo "  http://$SERVER_IP:30002"
echo "  http://$NODE_0_IP:30002"
echo "  http://$NODE_1_IP:30002"
echo ""
echo "🧪 Manual test commands:"
echo "======================="
echo "curl -v http://$SERVER_IP:30001"
echo "curl -v http://$NODE_0_IP:30001"
echo "curl -v http://$NODE_1_IP:30001"
echo ""
echo "📋 Next steps based on results:"
echo "==============================="
echo "1. If TX checksum is still 'on', apply the persistent fix"
echo "2. If pods are only on one node, external access to other nodes may fail"
echo "3. If iptables rules are missing, kube-proxy may need restart"
echo "4. If local access works but external fails, check security groups"
