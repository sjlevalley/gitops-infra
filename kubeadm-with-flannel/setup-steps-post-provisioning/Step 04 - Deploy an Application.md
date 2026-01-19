# Step 04 - Deploy an Application (Voting App)

**Prerequisites:** 
- Step 01, Step 02, and Step 03 must be completed first
- Kubernetes cluster is running and healthy
- kubectl is configured on the master node
- **Important**: Ensure Step 03's "Setup Flannel Plugin on ALL Nodes" section was completed on all nodes (master, node-0, and node-1)

## Step 0: Get Master Node IP Address

***RUN FROM YOUR LOCAL MACHINE OR FROM TERRAFORM OUTPUT***
```bash
# Option 1: Get master IP from Terraform output (if available)
# cd terraform
# terraform output master_public_ip

# Option 2: Get master IP from AWS console or your infrastructure
# The master node's public IP address is needed for SSH and accessing the application

# Option 3: SSH into master node and get its public IP
# ssh -i "k8s-key.pem" admin@<MASTER_IP> "curl -s http://169.254.169.254/latest/meta-data/public-ipv4"

# Set the master IP as a variable for convenience
MASTER_PUBLIC_IP="3.85.111.119"
echo "Master Public IP: $MASTER_PUBLIC_IP"
```

## Step 1: Copy Voting App to Master Node

***RUN FROM YOUR LOCAL MACHINE***
```bash
# Set the master node's public IP (replace with your actual IP)
MASTER_PUBLIC_IP="3.85.111.119"

# Option 1: Run from project root directory (EC2-Kubernetes)
# cd /path/to/EC2-Kubernetes
# scp -i "gitops-infra/kubeadm-with-flannel/terraform/k8s-key.pem" -r "gitops-application/applications/voting-app" admin@${MASTER_PUBLIC_IP}:~/

# Option 2: Run from terraform directory
# cd gitops-infra/kubeadm-with-flannel/terraform
scp -i "k8s-key.pem" -r "../../../gitops-application/applications/voting-app" admin@${MASTER_PUBLIC_IP}:~/

# Verify the files were copied
ssh -i "k8s-key.pem" admin@${MASTER_PUBLIC_IP} "ls -la ~/voting-app/"
```

<!-- **Important:**  -->
<!-- - The voting-app is located at `gitops-application/applications/voting-app` in the project root
- Adjust the path to `k8s-key.pem` based on where you're running the command from
- If running from terraform directory, use `../../../gitops-application/applications/voting-app`
- If running from project root, use `gitops-application/applications/voting-app` -->

## Step 2: Deploy the Voting Application

***RUN ON MASTER NODE***
```bash
# # SSH into the master node (replace with your actual master public IP)
# MASTER_PUBLIC_IP="<YOUR_MASTER_PUBLIC_IP>"
# ssh -i "kubeadm-with-flannel/terraform/k8s-key.pem" admin@${MASTER_PUBLIC_IP}

# Navigate to the voting-app k8s directory and apply the project files
cd ~/voting-app/k8s && kubectl apply -f .


# Check deployment status
kubectl get pods
kubectl get services
```

## Step 3: Verify Deployment

***RUN ON MASTER NODE***
```bash
# Wait for all pods to be ready (this may take a few minutes)
kubectl get pods -w

# Check all services
kubectl get services

# Check if NodePort services are accessible
kubectl get nodes -o wide
```

## Step 4: Test the Application

### Access the Voting App:
Replace `<YOUR_MASTER_PUBLIC_IP>` with your actual master node's public IP address:
- **Vote App**: `http://3.85.111.119:30001`
- **Result App**: `http://3.85.111.119:30002`

**To get your master node's public IP:**
```bash
# From master node
curl -s http://169.254.169.254/latest/meta-data/public-ipv4

# Or from local machine (if you have the master's private IP)
# Check your Terraform output or AWS console
```

### Test Steps:
1. **Vote**: Go to the vote app and click on "Cats" or "Dogs"
2. **View Results**: Go to the result app to see the voting results
3. **Check Logs**: Monitor the worker processing votes

## Step 5: Monitor and Troubleshoot

***RUN ON MASTER NODE***
```bash
# Check pod logs
kubectl logs -f deployment/vote
kubectl logs -f deployment/result
kubectl logs -f deployment/worker

# Check pod status
kubectl describe pod <pod-name>

# Check service endpoints
kubectl get endpoints

# Check events
kubectl get events --sort-by=.metadata.creationTimestamp
```

## Troubleshooting Common Issues

### Issue 1: Pods Stuck in Pending State
```bash
# Check node resources
kubectl describe nodes

# Check if images are being pulled
kubectl describe pod <pod-name>
```

### Issue 2: Cannot Access Application from Browser
```bash
# Check if NodePort services are running
kubectl get services

# Check if ports are open in security groups
# Ensure ports 30001 and 30002 are open in AWS security group

# Test connectivity from master node
curl http://localhost:30001
curl http://localhost:30002
```

### Issue 3: Database Connection Issues
```bash
# Check database pods
kubectl get pods | grep -E "(redis|db)"

# Check database logs
kubectl logs deployment/redis
kubectl logs deployment/db

# Test database connectivity
kubectl exec -it deployment/redis -- redis-cli ping
```

## Useful Commands

```bash
# Scale the vote app
kubectl scale deployment vote --replicas=3

# Check resource usage
kubectl top pods
kubectl top nodes

# Delete the application (run from ~/voting-app/k8s directory)
cd ~/voting-app/k8s && kubectl delete -f .

# Restart a deployment
kubectl rollout restart deployment/vote
```

## Expected Results

After successful deployment, you should see:

- **5 pods running**: vote, result, worker, redis, db
- **4 services**: vote (NodePort 30001), result (NodePort 30002), redis, db
- **Vote app accessible** at `http://<YOUR_MASTER_PUBLIC_IP>:30001`
- **Result app accessible** at `http://<YOUR_MASTER_PUBLIC_IP>:30002`
- **Voting functionality working** - votes are processed and results are displayed

## Clean Up

To remove the application:

```bash
# Delete all resources (run from ~/voting-app/k8s directory)
cd ~/voting-app/k8s && kubectl delete -f .

# Verify cleanup
kubectl get pods
kubectl get services
```

## Security Group Configuration

Ensure your AWS security group allows inbound traffic on:
- **Port 30001** (Vote App)
- **Port 30002** (Result App)
- **Port 4789 UDP** (VXLAN for Flannel CNI) - **Not needed for Calico CNI**

**Security Group Rules:**
```
Type: Custom TCP
Port: 30001-30002
Source: 0.0.0.0/0
Description: Voting App NodePort Services

Type: Custom UDP
Port: 4789
Source: 172.31.0.0/16
Description: VXLAN for Flannel CNI (not needed for Calico)
```

**Important:** Since you're using Calico CNI (not Flannel), the VXLAN UDP 4789 rule is not required. Calico uses BGP routing instead of VXLAN overlay networking.

## Troubleshooting NodePort Access Issues

### TX Checksum Offloading Issue (Ubuntu 22.04 + Flannel)

If external browser access to NodePort services hangs despite local access working, this is likely due to TX checksum offloading on the flannel.1 interface. This is a known issue with Flannel VXLAN on Ubuntu 22.04 in AWS EC2 environments.

**Symptoms:**
- Local NodePort access works: `curl http://localhost:30001`
- External browser access hangs or times out
- All pods are running and healthy
- Security group rules are correct

**Solution - Apply Persistent TX Checksum Fix:**

1. **Apply the fix to all nodes:**
   ```bash
   # Make scripts executable
   chmod +x fix-flannel-tx-checksum.sh apply-persistent-tx-checksum-fix.sh
   
   # Apply persistent fix to all nodes
   ./apply-persistent-tx-checksum-fix.sh
   ```

2. **Verify the fix is working:**
   ```bash
   # Set the node IP (replace with your actual node IP)
   NODE_IP="<YOUR_NODE_PUBLIC_IP>"
   
   # Check service status on any node
   ssh -i k8s-key.pem admin@${NODE_IP} 'sudo systemctl status flannel-tx-checksum-fix.service'
   
   # Verify TX checksum is disabled
   ssh -i k8s-key.pem admin@${NODE_IP} 'ethtool -k flannel.1 | grep tx-checksumming'
   
   # Test external access
   curl http://${NODE_IP}:30001
   ```

3. **Run verification script:**
   ```bash
   chmod +x verify-nodeport-access.sh
   ./verify-nodeport-access.sh
   ```

**What the fix does:**
- Creates a systemd service that automatically disables TX checksum offloading on flannel.1
- Runs after flanneld service starts
- Persists across reboots
- Applies to all nodes in the cluster

**Alternative solutions if the fix doesn't work:**
1. Switch to Calico CNI plugin
2. Try kube-proxy in IPVS mode
3. Check if VXLAN security group rule was actually applied