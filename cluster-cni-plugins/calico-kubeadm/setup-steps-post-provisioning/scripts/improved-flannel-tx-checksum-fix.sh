#!/bin/bash

# Improved Flannel TX Checksum Fix
# This script creates a robust persistent solution for the TX checksum offloading problem
# that affects Flannel VXLAN on Ubuntu 22.04 in AWS EC2 environments

set -e

echo "🔧 Creating improved persistent TX checksum fix for Flannel..."

# Create the improved script with better error handling and timeout
sudo tee /usr/local/bin/flannel-fix.sh > /dev/null <<'EOF'
#!/usr/bin/env bash
MAX_WAIT=300
WAIT_INTERVAL=10
ELAPSED_TIME=0

echo "Waiting for flannel.1 interface to be created..."

while ! ip link show flannel.1 &> /dev/null; do
  sleep $WAIT_INTERVAL
  ELAPSED_TIME=$((ELAPSED_TIME + WAIT_INTERVAL))
  echo "Waiting for flannel.1 interface... (${ELAPSED_TIME}s/${MAX_WAIT}s)"
  
  if [ $ELAPSED_TIME -ge $MAX_WAIT ]; then
    echo "ERROR: Timed out waiting for flannel.1 interface after ${MAX_WAIT} seconds."
    exit 1
  fi
done

echo "flannel.1 interface found, disabling TX checksum offloading..."

# Disable TX checksum offloading
ethtool -K flannel.1 tx-checksum-ip-generic off

# Verify the change
if ethtool -k flannel.1 | grep -q "tx-checksum-ip-generic: off"; then
    echo "SUCCESS: TX checksum offloading disabled on flannel.1"
    exit 0
else
    echo "WARNING: TX checksum offloading may not have been disabled properly"
    ethtool -k flannel.1 | grep tx-checksum-ip-generic || echo "Could not verify TX checksum status"
    exit 1
fi
EOF

# Make the script executable
sudo chmod +x /usr/local/bin/flannel-fix.sh

# Create the systemd service
sudo tee /etc/systemd/system/flannel-fix.service > /dev/null <<'EOF'
[Unit]
Description=Disable Flannel TX checksum offload
After=network.target kubelet.service
Wants=kubelet.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/flannel-fix.sh
RemainAfterExit=true
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and enable the service
sudo systemctl daemon-reload
sudo systemctl enable flannel-fix.service

# Start the service immediately
sudo systemctl start flannel-fix.service

# Check service status
echo "📋 Service status:"
sudo systemctl status flannel-fix.service --no-pager

# Verify the fix is applied
echo "🔍 Verifying TX checksum offloading status:"
if ip link show flannel.1 >/dev/null 2>&1; then
    echo "flannel.1 interface found:"
    ethtool -k flannel.1 | grep tx-checksum-ip-generic || echo "TX checksum info not available"
else
    echo "flannel.1 interface not found yet"
fi

echo "✅ Improved persistent TX checksum fix installed and enabled!"
echo "🔄 The fix will be applied automatically on every boot"
echo "🧪 Test external access to your NodePort services now"
