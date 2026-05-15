#!/bin/bash

# Fix Flannel TX Checksum Offloading Issue
# This script creates a persistent solution for the TX checksum offloading problem
# that affects Flannel VXLAN on Ubuntu 22.04 in AWS EC2 environments

set -e

echo "🔧 Creating persistent TX checksum fix for Flannel..."

# Create the systemd service file
sudo tee /etc/systemd/system/flannel-tx-checksum-fix.service > /dev/null <<EOF
[Unit]
Description=Fix Flannel TX Checksum Offloading
After=network.target flanneld.service
Wants=flanneld.service

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'sleep 10 && if ip link show flannel.1 >/dev/null 2>&1; then ethtool -K flannel.1 tx off; echo "TX checksum offloading disabled on flannel.1"; else echo "flannel.1 interface not found, skipping"; fi'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# Create a script that will be executed by the service
sudo tee /usr/local/bin/fix-flannel-checksum.sh > /dev/null <<EOF
#!/bin/bash

# Wait for flannel.1 interface to be created
for i in {1..30}; do
    if ip link show flannel.1 >/dev/null 2>&1; then
        echo "flannel.1 interface found, disabling TX checksum offloading..."
        ethtool -K flannel.1 tx off
        echo "TX checksum offloading disabled on flannel.1"
        exit 0
    fi
    echo "Waiting for flannel.1 interface... (\$i/30)"
    sleep 2
done

echo "Warning: flannel.1 interface not found after 60 seconds"
exit 1
EOF

# Make the script executable
sudo chmod +x /usr/local/bin/fix-flannel-checksum.sh

# Update the systemd service to use the script
sudo tee /etc/systemd/system/flannel-tx-checksum-fix.service > /dev/null <<EOF
[Unit]
Description=Fix Flannel TX Checksum Offloading
After=network.target flanneld.service
Wants=flanneld.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/fix-flannel-checksum.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and enable the service
sudo systemctl daemon-reload
sudo systemctl enable flannel-tx-checksum-fix.service

# Start the service immediately
sudo systemctl start flannel-tx-checksum-fix.service

# Check service status
echo "📋 Service status:"
sudo systemctl status flannel-tx-checksum-fix.service --no-pager

# Verify the fix is applied
echo "🔍 Verifying TX checksum offloading status:"
if ip link show flannel.1 >/dev/null 2>&1; then
    echo "flannel.1 interface found:"
    ethtool -k flannel.1 | grep tx-checksumming || echo "TX checksum info not available"
else
    echo "flannel.1 interface not found yet"
fi

echo "✅ Persistent TX checksum fix installed and enabled!"
echo "🔄 The fix will be applied automatically on every boot"
echo "🧪 Test external access to your NodePort services now"
