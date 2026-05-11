#!/bin/bash

# Apply Improved TX Checksum Fix to All Kubernetes Nodes
# This script applies the improved persistent fix to all nodes in the cluster

set -e

# Node IPs from your machines.txt
SERVER_IP="54.164.109.60"
NODE_0_IP="98.80.9.220"
NODE_1_IP="54.196.171.115"

# SSH key path
SSH_KEY="k8s-key.pem"

echo "🚀 Applying improved persistent TX checksum fix to all Kubernetes nodes..."
echo "📋 Nodes to update:"
echo "  - Server (Control Plane): $SERVER_IP"
echo "  - Node-0 (Worker): $NODE_0_IP"
echo "  - Node-1 (Worker): $NODE_1_IP"
echo ""

# Function to apply fix to a node
apply_fix_to_node() {
    local node_ip=$1
    local node_name=$2
    
    echo "🔧 Applying improved fix to $node_name ($node_ip)..."
    
    # Copy the fix script to the node
    scp -i "$SSH_KEY" -o StrictHostKeyChecking=no improved-flannel-tx-checksum-fix.sh admin@$node_ip:/tmp/
    
    # Execute the fix script on the node
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no admin@$node_ip "chmod +x /tmp/improved-flannel-tx-checksum-fix.sh && sudo /tmp/improved-flannel-tx-checksum-fix.sh"
    
    echo "✅ Improved fix applied to $node_name"
    echo ""
}

# Apply fix to all nodes
apply_fix_to_node "$SERVER_IP" "Server (Control Plane)"
apply_fix_to_node "$NODE_0_IP" "Node-0 (Worker)"
apply_fix_to_node "$NODE_1_IP" "Node-1 (Worker)"

echo "🎉 Improved persistent TX checksum fix applied to all nodes!"
echo ""
echo "🧪 Testing external access..."
echo "Try accessing your NodePort services:"
echo "  - Vote app: http://$NODE_0_IP:30001"
echo "  - Result app: http://$NODE_0_IP:30002"
echo "  - Vote app: http://$NODE_1_IP:30001"
echo "  - Result app: http://$NODE_1_IP:30002"
echo ""
echo "📋 To verify the fix is working:"
echo "1. Check service status on any node:"
echo "   ssh -i $SSH_KEY admin@$NODE_0_IP 'sudo systemctl status flannel-fix.service'"
echo ""
echo "2. Verify TX checksum is disabled:"
echo "   ssh -i $SSH_KEY admin@$NODE_0_IP 'ethtool -k flannel.1 | grep tx-checksum-ip-generic'"
echo ""
echo "3. Test local NodePort access:"
echo "   ssh -i $SSH_KEY admin@$NODE_0_IP 'curl -s http://localhost:30001 | head -5'"
echo ""
echo "4. Run comprehensive diagnosis:"
echo "   chmod +x comprehensive-nodeport-diagnosis.sh"
echo "   ./comprehensive-nodeport-diagnosis.sh"
