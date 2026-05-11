#!/bin/bash

# Verify NodePort Access and TX Checksum Fix
# This script helps verify that the persistent TX checksum fix is working

set -e

# Node IPs from your machines.txt
SERVER_IP="54.164.109.60"
NODE_0_IP="98.80.9.220"
NODE_1_IP="54.196.171.115"

# SSH key path
SSH_KEY="k8s-key.pem"

echo "🔍 Verifying NodePort access and TX checksum fix..."
echo ""

# Function to check node status
check_node_status() {
    local node_ip=$1
    local node_name=$2
    
    echo "📋 Checking $node_name ($node_ip)..."
    
    # Check if the service is running
    echo "  🔧 Service status:"
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no admin@$node_ip "sudo systemctl is-active flannel-tx-checksum-fix.service" 2>/dev/null || echo "    Service not found or not active"
    
    # Check TX checksum status
    echo "  🔍 TX checksum status:"
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no admin@$node_ip "if ip link show flannel.1 >/dev/null 2>&1; then ethtool -k flannel.1 | grep tx-checksumming || echo '    TX checksum info not available'; else echo '    flannel.1 interface not found'; fi"
    
    # Test local NodePort access
    echo "  🧪 Local NodePort test:"
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no admin@$node_ip "curl -s --connect-timeout 5 http://localhost:30001 | head -1" 2>/dev/null || echo "    Local NodePort test failed"
    
    echo ""
}

# Check all nodes
check_node_status "$SERVER_IP" "Server (Control Plane)"
check_node_status "$NODE_0_IP" "Node-0 (Worker)"
check_node_status "$NODE_1_IP" "Node-1 (Worker)"

echo "🌐 External access URLs to test:"
echo "  Vote app on Node-0: http://$NODE_0_IP:30001"
echo "  Result app on Node-0: http://$NODE_0_IP:30002"
echo "  Vote app on Node-1: http://$NODE_1_IP:30001"
echo "  Result app on Node-1: http://$NODE_1_IP:30002"
echo ""
echo "📋 If external access still doesn't work, try these additional steps:"
echo "1. Check if the VXLAN security group rule was applied:"
echo "   aws ec2 describe-security-groups --group-names k8s-cluster-sg* --query 'SecurityGroups[0].IpPermissions[?FromPort==\`4789\`]'"
echo ""
echo "2. Test with curl from your local machine:"
echo "   curl -v http://$NODE_0_IP:30001"
echo ""
echo "3. Check if pods are running on the correct nodes:"
echo "   ssh -i $SSH_KEY admin@$SERVER_IP 'kubectl get pods -o wide'"
echo ""
echo "4. If still having issues, consider switching to Calico CNI:"
echo "   kubectl delete -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml"
echo "   kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/calico.yaml"
