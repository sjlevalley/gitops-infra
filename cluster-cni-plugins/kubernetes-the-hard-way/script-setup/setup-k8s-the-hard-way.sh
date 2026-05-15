# TODO: COPY MACHINES.TXT TO THE JUMPBOX
# TODO: COPY MACHINES.TXT to this '001 - steps - kubernetes-the-hard-way/manual' directory in Terraform script
# TODO: COPY MACHINES.TXT to this '001 - steps - kubernetes-the-hard-way/script' directory in Terraform script

# STEP 02: Initial Setup of Jumpbox

# **Copy Existing SSH Keypair** 
# Since you already have the `k8s-key.pem` and `k8s-key.pub` files from your Terraform script, copy them to the jumpbox for use in the next steps:
# Copy the key files to your jumpbox:

```bash
# From your local machine, copy the key files to the jumpbox so the jumpbox can SSH into the other machines
`scp -i "k8s-key.pem" k8s-key.pem admin@{IP}:~/` # TODO: TERRAFORM SCRIPT UPDATE THIS IP?
`scp -i "k8s-key.pem" k8s-key.pub admin@{IP}:~/` # TODO: TERRAFORM SCRIPT UPDATE THIS IP?
`scp -i "machines.txt" machines.txt admin@{IP}:~/` # TODO: TERRAFORM SCRIPT UPDATE THIS IP?
```

# SSH into Jumpbox
`ssh -i "k8s-key.pem" admin@<JUMPBOX_IP>` # TODO: TERRAFORM SCRIPT UPDATE THIS IP?

# Update and install necessary packages
`sudo apt-get update && sudo apt-get -y install wget curl vim openssl git`

# Create .ssh directory if it doesn't exist
`mkdir -p ~/.ssh`

# Copy the keys to the correct location
`cp k8s-key.pem ~/.ssh/id_rsa && cp k8s-key.pub ~/.ssh/id_rsa.pub`

# Set proper permissions
`chmod 700 ~/.ssh && chmod 400 ~/.ssh/id_rsa && chmod 644 ~/.ssh/id_rsa.pub`

# Also fix permissions on the original key files (AWS recommends chmod 400)
`chmod 400 k8s-key.pem && chmod 644 k8s-key.pub`
```

# Test the key setup:
```bash
# Test that the key works
`ssh-keygen -y -f ~/.ssh/id_rsa`
```

# Clone the Kubernetes The Hard Way git repository
`git clone --depth 1 https://github.com/kelseyhightower/kubernetes-the-hard-way.git`

# Change directory to the Kubernetes The Hard Way git repository
#  THIS WILL BE THE WORKING DIRECTORY ON THE JUMPBOX
`cd kubernetes-the-hard-way`

# Print the current working directory
`pwd`
# Output should be '/home/admin/kubernetes-the-hard-way'

# Download the binaries for the various Kubernetes components
`cat downloads-$(dpkg --print-architecture).txt`

# Download the binaries into a directory called downloads using the wget command:
`wget -q --show-progress --https-only --timestamping -P downloads -i downloads-$(dpkg --print-architecture).txt`

# Print the list of binaries in the downloads directory
`ls -oh downloads`

# Extract the component binaries from the release archives and organize them under the downloads directory
{
ARCH=$(dpkg --print-architecture)
  mkdir -p downloads/{client,cni-plugins,controller,worker}
  tar -xvf downloads/crictl-v1.32.0-linux-${ARCH}.tar.gz \
 -C downloads/worker/
tar -xvf downloads/containerd-2.1.0-beta.0-linux-${ARCH}.tar.gz \
    --strip-components 1 \
    -C downloads/worker/
  tar -xvf downloads/cni-plugins-linux-${ARCH}-v1.6.2.tgz \
 -C downloads/cni-plugins/
tar -xvf downloads/etcd-v3.6.0-rc.3-linux-${ARCH}.tar.gz \
    -C downloads/ \
    --strip-components 1 \
    etcd-v3.6.0-rc.3-linux-${ARCH}/etcdctl \
 etcd-v3.6.0-rc.3-linux-${ARCH}/etcd
  mv downloads/{etcdctl,kubectl} downloads/client/
  mv downloads/{etcd,kube-apiserver,kube-controller-manager,kube-scheduler} \
    downloads/controller/
  mv downloads/{kubelet,kube-proxy} downloads/worker/
  mv downloads/runc.${ARCH} downloads/worker/runc
}

# Remove the release archives
`rm -rf downloads/*gz`

# Make the binaries executable
`chmod +x downloads/{client,cni-plugins,controller,worker}/*`

# Install kubectl
`sudo cp downloads/client/kubectl /usr/local/bin/`

# Print the version of kubectl
`kubectl version --client`

# The output should look like this
# Client Version: v1.32.3
# Kustomize Version: v5.5.0

# At this point the `jumpbox` has been set up with all the command line tools and utilities necessary to complete the labs in this tutorial.




# STEP 03: Distribute SSH Keys

# Set the hostname on each machine listed in the machines.txt file:
{
while read IP FQDN HOST SUBNET; do
CMD="sudo sed -i 's/^127.0.1.1.\*/127.0.1.1\t${FQDN} ${HOST}/' /etc/hosts"
ssh -n admin@${IP} "$CMD"
ssh -n admin@${IP} "sudo hostnamectl set-hostname ${FQDN}"
ssh -n admin@${IP} "sudo systemctl restart systemd-hostnamed"
done < machines.txt
}

# Verify the hostname is set on each machine:
{
while read IP FQDN HOST SUBNET; do
ssh -n admin@${IP} "hostname --fqdn"
done < machines.txt
}
# The output should look like this
# ```
# server.kubernetes.local
# node-0.kubernetes.local
# node-1.kubernetes.local
# ```


# Create a new hosts file and add a header to identify the machines being added:
`echo "" > hosts && echo "# Kubernetes The Hard Way" >> hosts`

# Generate a host entry for each machine in the machines.txt file and append it to the hosts file:
{
while read IP FQDN HOST SUBNET; do
ENTRY="${IP} ${FQDN} ${HOST}"
echo $ENTRY >> hosts
done < machines.txt
}

# Review the host entries in the hosts file:
`cat hosts`

# The output should look like this
# ```
# Kubernetes The Hard Way
# XXX.XXX.XXX.XXX server.kubernetes.local server
# XXX.XXX.XXX.XXX node-0.kubernetes.local node-0
# XXX.XXX.XXX.XXX node-1.kubernetes.local node-1
# ```

# Append the DNS entries from hosts to /etc/hosts:
`sudo sh -c "cat hosts >> /etc/hosts"`

# Verify that the /etc/hosts file has been updated:
`cat /etc/hosts`

# The output should look like this
# ```
# 127.0.0.1       localhost
# 127.0.1.1       jumpbox

# # The following lines are desirable for IPv6 capable hosts
# ::1     localhost ip6-localhost ip6-loopback
# ff02::1 ip6-allnodes
# ff02::2 ip6-allrouters

# # Kubernetes The Hard Way
# XXX.XXX.XXX.XXX server.kubernetes.local server
# XXX.XXX.XXX.XXX node-0.kubernetes.local node-0
# XXX.XXX.XXX.XXX node-1.kubernetes.local node-1
# ```

# At this point you should be able to SSH to each machine listed in the machines.txt file using a hostname.
{
for host in server node-0 node-1
do ssh admin@${host} hostname
done
}

# The output should look like this
# ```
# server.kubernetes.local
# node-0.kubernetes.local
# node-1.kubernetes.local
# ```

# **Adding /etc/hosts Entries To The Remote Machines**
# In this section you will append the host entries from hosts to /etc/hosts on each machine listed in the machines.txt text file.
# Copy the hosts file to each machine and append the contents to /etc/hosts:
{
while read IP FQDN HOST SUBNET; do
scp hosts admin@${HOST}:~/
ssh -n admin@${HOST} "sudo sh -c \"cat hosts >> /etc/hosts\""
done < machines.txt
}

# ********END OF STEP 03********

# STEP 04: Provisioning a CA and Generating TLS Certificates
# Make sure we're back on the jumpbox and in the kubernetes-the-hard-way directory
`cd ~/kubernetes-the-hard-way`

# Print the current working directory
`pwd`
# Output should be '/home/admin/kubernetes-the-hard-way'

# Provision a CA and generate TLS certificates:
{
  openssl genrsa -out ca.key 4096
  openssl req -x509 -new -sha512 -noenc \
    -key ca.key -days 3653 \
    -config ca.conf \
    -out ca.crt
}

# A ca.crt and ca.key file should have been created in the current working directory

## Create Client and Server Certificates

# Next you will generate client and server certificates for each Kubernetes component and a client certificate for the Kubernetes `admin` user.

# Generate the certificates and private keys:
```bash
certs=(
  "admin" "node-0" "node-1"
  "kube-proxy" "kube-scheduler"
  "kube-controller-manager"
  "kube-api-server"
  "service-accounts"
)
```
```bash
for i in ${certs[*]}; do
  openssl genrsa -out "${i}.key" 4096

  openssl req -new -key "${i}.key" -sha256 \
    -config "ca.conf" -section ${i} \
    -out "${i}.csr"

  openssl x509 -req -days 3653 -in "${i}.csr" \
    -copy_extensions copyall \
    -sha256 -CA "ca.crt" \
    -CAkey "ca.key" \
    -CAcreateserial \
    -out "${i}.crt"
done
```

# The results of running the above command will generate a private key, certificate request, and signed SSL certificate for each of the Kubernetes components. You can list the generated files with the following command:
`ls -1 *.crt *.key *.csr`


## Distribute the Client and Server Certificates

# In this section you will copy the various certificates to every machine at a path where each Kubernetes component will search for its certificate pair. In a real-world environment these certificates should be treated like a set of sensitive secrets as they are used as credentials by the Kubernetes components to authenticate to each other.

# Copy the appropriate certificates and private keys to the `node-0` and `node-1` machines:
```bash
for host in node-0 node-1; do
  ssh admin@${host} "sudo mkdir -p /var/lib/kubelet/"

  scp ca.crt admin@${host}:~/
  ssh admin@${host} "sudo mv ~/ca.crt /var/lib/kubelet/"

  scp ${host}.crt admin@${host}:~/
  ssh admin@${host} "sudo mv ~/${host}.crt /var/lib/kubelet/kubelet.crt"

  scp ${host}.key admin@${host}:~/
  ssh admin@${host} "sudo mv ~/${host}.key /var/lib/kubelet/kubelet.key"
done
```

# Copy the appropriate certificates and private keys to the `server` machine:
```bash
scp \
  ca.key ca.crt \
  kube-api-server.key kube-api-server.crt \
  service-accounts.key service-accounts.crt \
  admin@server:~/
```

# ********END OF STEP 04********


# STEP 05: Generating Kubernetes Configuration Files for Authentication

# Generate a kubeconfig file for the `node-0` and `node-1` worker nodes:
```bash
for host in node-0 node-1; do
  kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=ca.crt \
    --embed-certs=true \
    --server=https://server.kubernetes.local:6443 \
    --kubeconfig=${host}.kubeconfig

  kubectl config set-credentials system:node:${host} \
    --client-certificate=${host}.crt \
    --client-key=${host}.key \
    --embed-certs=true \
    --kubeconfig=${host}.kubeconfig

  kubectl config set-context default \
    --cluster=kubernetes-the-hard-way \
    --user=system:node:${host} \
    --kubeconfig=${host}.kubeconfig

  kubectl config use-context default \
    --kubeconfig=${host}.kubeconfig
done
```
# Results:
# ```text
# node-0.kubeconfig
# node-1.kubeconfig
# ```


### The kube-proxy Kubernetes Configuration File

# Generate a kubeconfig file for the `kube-proxy` service:
```bash
{
  kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=ca.crt \
    --embed-certs=true \
    --server=https://server.kubernetes.local:6443 \
    --kubeconfig=kube-proxy.kubeconfig

  kubectl config set-credentials system:kube-proxy \
    --client-certificate=kube-proxy.crt \
    --client-key=kube-proxy.key \
    --embed-certs=true \
    --kubeconfig=kube-proxy.kubeconfig

  kubectl config set-context default \
    --cluster=kubernetes-the-hard-way \
    --user=system:kube-proxy \
    --kubeconfig=kube-proxy.kubeconfig

  kubectl config use-context default \
    --kubeconfig=kube-proxy.kubeconfig
}
```
# Results:

# ```text
# kube-proxy.kubeconfig
# ```

### The kube-controller-manager Kubernetes Configuration File

# Generate a kubeconfig file for the `kube-controller-manager` service:
```bash
{
  kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=ca.crt \
    --embed-certs=true \
    --server=https://server.kubernetes.local:6443 \
    --kubeconfig=kube-controller-manager.kubeconfig

  kubectl config set-credentials system:kube-controller-manager \
    --client-certificate=kube-controller-manager.crt \
    --client-key=kube-controller-manager.key \
    --embed-certs=true \
    --kubeconfig=kube-controller-manager.kubeconfig

  kubectl config set-context default \
    --cluster=kubernetes-the-hard-way \
    --user=system:kube-controller-manager \
    --kubeconfig=kube-controller-manager.kubeconfig

  kubectl config use-context default \
    --kubeconfig=kube-controller-manager.kubeconfig
}
```

# Results:

# ```text
# kube-controller-manager.kubeconfig
# ```

### The kube-scheduler Kubernetes Configuration File

# Generate a kubeconfig file for the `kube-scheduler` service:
```bash
{
  kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=ca.crt \
    --embed-certs=true \
    --server=https://server.kubernetes.local:6443 \
    --kubeconfig=kube-scheduler.kubeconfig

  kubectl config set-credentials system:kube-scheduler \
    --client-certificate=kube-scheduler.crt \
    --client-key=kube-scheduler.key \
    --embed-certs=true \
    --kubeconfig=kube-scheduler.kubeconfig

  kubectl config set-context default \
    --cluster=kubernetes-the-hard-way \
    --user=system:kube-scheduler \
    --kubeconfig=kube-scheduler.kubeconfig

  kubectl config use-context default \
    --kubeconfig=kube-scheduler.kubeconfig
}
```

# Results:
# ```text
# kube-scheduler.kubeconfig
# ```

### The admin Kubernetes Configuration File

# Generate a kubeconfig file for the `admin` user:
```bash
{
  kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=ca.crt \
    --embed-certs=true \
    --server=https://127.0.0.1:6443 \
    --kubeconfig=admin.kubeconfig

  kubectl config set-credentials admin \
    --client-certificate=admin.crt \
    --client-key=admin.key \
    --embed-certs=true \
    --kubeconfig=admin.kubeconfig

  kubectl config set-context default \
    --cluster=kubernetes-the-hard-way \
    --user=admin \
    --kubeconfig=admin.kubeconfig

  kubectl config use-context default \
    --kubeconfig=admin.kubeconfig
}
```

# Results:
# ```text
# admin.kubeconfig
# ```

## Distribute the Kubernetes Configuration Files

# Copy the `kubelet` and `kube-proxy` kubeconfig files to the `node-0` and `node-1` machines:
```bash
for host in node-0 node-1; do
  ssh admin@${host} "sudo mkdir -p /var/lib/{kube-proxy,kubelet}"

  scp kube-proxy.kubeconfig admin@${host}:~/
  ssh admin@${host} "sudo mv ~/kube-proxy.kubeconfig /var/lib/kube-proxy/kubeconfig"

  scp ${host}.kubeconfig admin@${host}:~/
  ssh admin@${host} "sudo mv ~/${host}.kubeconfig /var/lib/kubelet/kubeconfig"
done
```

# Copy the `kube-controller-manager` and `kube-scheduler` kubeconfig files to the `server` machine:
```bash
scp admin.kubeconfig \
  kube-controller-manager.kubeconfig \
  kube-scheduler.kubeconfig \
  admin@server:~/
```

# ********END OF STEP 05********

# STEP 06: Generating the Data Encryption Config and Key

# RUN FROM THE JUMPBOX

# Generate a data encryption config and key:
```bash
export ENCRYPTION_KEY=$(head -c 32 /dev/urandom | base64)
```

## The Encryption Config File
# Create the `encryption-config.yaml` encryption config file:
```bash
envsubst < configs/encryption-config.yaml \
  > encryption-config.yaml
```

# Copy the `encryption-config.yaml` encryption config file to each controller instance:
```bash
scp encryption-config.yaml admin@server:~/
```

# ********END OF STEP 06********

# STEP 07: Bootstrapping the etcd Cluster

# RUN FROM THE JUMPBOX

# Copy `etcd` binaries and systemd unit files to the `server` machine:
```bash
scp \
  downloads/controller/etcd \
  downloads/client/etcdctl \
  units/etcd.service \
  admin@server:~/
```

# SSH INTO SERVER
# The commands in this lab must be run on the `server` machine. Login to the `server` machine using the `ssh` command. Example:
```bash
ssh admin@server
```

# RUN FROM THE SERVER

## Bootstrapping an etcd Cluster

### Install the etcd Binaries

# Extract and install the `etcd` server and the `etcdctl` command line utility:
```bash
{
  sudo mv etcd etcdctl /usr/local/bin/
}
```

### Configure the etcd Server
```bash
{
  sudo mkdir -p /etc/etcd /var/lib/etcd
  sudo chmod 700 /var/lib/etcd
  sudo cp ca.crt kube-api-server.key kube-api-server.crt \
    /etc/etcd/
}
```

# Each etcd member must have a unique name within an etcd cluster. Set the etcd name to match the hostname of the current compute instance:
# Create the `etcd.service` systemd unit file:
```bash
sudo mv etcd.service /etc/systemd/system/
```

### Start the etcd Server
```bash
{
  sudo systemctl daemon-reload
  sudo systemctl enable etcd
  sudo systemctl start etcd
}
```

## Verification
# List the etcd cluster members:
```bash
sudo etcdctl member list
```
# OUTPUT SHOULD LOOK LIKE THIS
# ```text
# 6702b0a34e2cfd39, started, controller, http://127.0.0.1:2380, http://127.0.0.1:2379, false
# ```

# ********END OF STEP 07********

# STEP 08: Bootstrapping the Kubernetes Control Plane

# RUN FROM THE JUMPBOX WORKING DIRECTORY

# Copy Kubernetes binaries and systemd unit files to the `server` machine:
```bash
scp \
  downloads/controller/kube-apiserver \
  downloads/controller/kube-controller-manager \
  downloads/controller/kube-scheduler \
  downloads/client/kubectl \
  units/kube-apiserver.service \
  units/kube-controller-manager.service \
  units/kube-scheduler.service \
  configs/kube-scheduler.yaml \
  configs/kube-apiserver-to-kubelet.yaml \
  admin@server:~/
```

# The commands in this lab must be run on the `server` machine. Login to the `server` machine using the `ssh` command. Example:

# SSH INTO SERVER
```bash
ssh admin@server
```

## Provision the Kubernetes Control Plane

# Create the Kubernetes configuration directory:
```bash
sudo mkdir -p /etc/kubernetes/config
```

### Install the Kubernetes Controller Binaries

# Install the Kubernetes binaries:
```bash
{
  sudo mv kube-apiserver \
    kube-controller-manager \
    kube-scheduler kubectl \
    /usr/local/bin/
}
```

### Configure the Kubernetes API Server
```bash
{
  sudo mkdir -p /var/lib/kubernetes/

  sudo mv ca.crt ca.key \
    kube-api-server.key kube-api-server.crt \
    service-accounts.key service-accounts.crt \
    encryption-config.yaml \
    /var/lib/kubernetes/
}
```

# Create the `kube-apiserver.service` systemd unit file:
```bash
sudo mv kube-apiserver.service \
  /etc/systemd/system/kube-apiserver.service
```
### Configure the Kubernetes Controller Manager

# Move the `kube-controller-manager` kubeconfig into place:
```bash
sudo mv kube-controller-manager.kubeconfig /var/lib/kubernetes/
```

# Create the `kube-controller-manager.service` systemd unit file:
```bash
sudo mv kube-controller-manager.service /etc/systemd/system/
```

### Configure the Kubernetes Scheduler

# Move the `kube-scheduler` kubeconfig into place:
```bash
sudo mv kube-scheduler.kubeconfig /var/lib/kubernetes/
```

# Create the `kube-scheduler.yaml` configuration file:
```bash
sudo mv kube-scheduler.yaml /etc/kubernetes/config/
```

# Create the `kube-scheduler.service` systemd unit file:
```bash
sudo mv kube-scheduler.service /etc/systemd/system/
```

### Start the Controller Services
```bash
{
  sudo systemctl daemon-reload

  sudo systemctl enable kube-apiserver \
    kube-controller-manager kube-scheduler

  sudo systemctl start kube-apiserver \
    kube-controller-manager kube-scheduler
}
```

# > Allow up to 10 seconds for the Kubernetes API Server to fully initialize.

# You can check if any of the control plane components are active using the `systemctl` command. For example, to check if the `kube-apiserver` fully initialized, and active, run the following command:
```bash
sudo systemctl is-active kube-apiserver
```

# For a more detailed status check, which includes additional process information and log messages, use the `systemctl status` command:
```bash
sudo systemctl status kube-apiserver
```

# If you run into any errors, or want to view the logs for any of the control plane components, use the `journalctl` command. For example, to view the logs for the `kube-apiserver` run the following command:
```bash
sudo journalctl -u kube-apiserver
```

### Verification

# At this point the Kubernetes control plane components should be up and running. Verify this using the `kubectl` command line tool:
```bash
kubectl cluster-info \
  --kubeconfig admin.kubeconfig
```
# OUTPUT SHOULD LOOK LIKE THIS
# ```text
# Kubernetes control plane is running at https://127.0.0.1:6443
# ```


## RBAC for Kubelet Authorization

# > This tutorial sets the Kubelet `--authorization-mode` flag to `Webhook`. Webhook mode uses the [SubjectAccessReview](https://kubernetes.io/docs/reference/access-authn-authz/authorization/#checking-api-access) API to determine authorization.

# The commands in this section will affect the entire cluster and only need to be run on the `server` machine (if not already connected to it).

# SSH INTO SERVER
```bash
ssh admin@server
```

# Create the `system:kube-apiserver-to-kubelet` [ClusterRole](https://kubernetes.io/docs/reference/access-authn-authz/rbac/#role-and-clusterrole) with permissions to access the Kubelet API and perform most common tasks associated with managing pods:
```bash
kubectl apply -f kube-apiserver-to-kubelet.yaml \
  --kubeconfig admin.kubeconfig
```

# ## Verification

# At this point the Kubernetes control plane is up and running. Run the following commands from the `jumpbox` machine to verify it's working:

# Make a HTTP request for the Kubernetes version info:
```bash
curl --cacert ca.crt \
  https://server.kubernetes.local:6443/version
```
# OUTPUT SHOULD LOOK LIKE THIS
# ```text
# {
#   "major": "1",
#   "minor": "32",
#   "gitVersion": "v1.32.3",
#   "gitCommit": "32cc146f75aad04beaaa245a7157eb35063a9f99",
#   "gitTreeState": "clean",
#   "buildDate": "2025-03-11T19:52:21Z",
#   "goVersion": "go1.23.6",
#   "compiler": "gc",
#   "platform": "linux/arm64"
# }
# ```

# ********END OF STEP 08********

# STEP 09: Bootstrapping the Kubernetes Worker Nodes

# RUN FROM THE JUMPBOX WORKING DIRECTORY

# Copy Kubernetes binaries and systemd unit files to the `node-0` and `node-1` machines:
```bash
scp \
  downloads/controller/kubelet \
  downloads/controller/kube-proxy \


# In this lab you will bootstrap two Kubernetes worker nodes. The following components will be installed: [runc](https://github.com/opencontainers/runc), [container networking plugins](https://github.com/containernetworking/cni), [containerd](https://github.com/containerd/containerd), [kubelet](https://kubernetes.io/docs/reference/command-line-tools-reference/kubelet), and [kube-proxy](https://kubernetes.io/docs/concepts/cluster-administration/proxies).

## Prerequisites

# The commands in this section must be run from the `jumpbox`.

# Copy the Kubernetes binaries and systemd unit files to each worker instance:
```bash
for HOST in node-0 node-1; do
  SUBNET=$(grep ${HOST} machines.txt | cut -d " " -f 4)
  sed "s|SUBNET|$SUBNET|g" \
    configs/10-bridge.conf > 10-bridge.conf

  sed "s|SUBNET|$SUBNET|g" \
    configs/kubelet-config.yaml > kubelet-config.yaml

  scp 10-bridge.conf kubelet-config.yaml \
  admin@${HOST}:~/
done
```

```bash
for HOST in node-0 node-1; do
  scp \
    downloads/worker/* \
    downloads/client/kubectl \
    configs/99-loopback.conf \
    configs/containerd-config.toml \
    configs/kube-proxy-config.yaml \
    units/containerd.service \
    units/kubelet.service \
    units/kube-proxy.service \
    admin@${HOST}:~/
done 
```

```bash
for HOST in node-0 node-1; do
  scp \
    downloads/cni-plugins/* \
    admin@${HOST}:~/cni-plugins/
done
```

# The commands in the next section must be run on each worker instance: `node-0`, `node-1`. Login to the worker instance using the `ssh` command. Example:
```bash
ssh admin@node-0
```

## Provisioning a Kubernetes Worker Node

# Install the OS dependencies:
```bash
{
  sudo apt-get update
  sudo apt-get -y install socat conntrack ipset kmod
}
```

> The socat binary enables support for the `kubectl port-forward` command.

# Disable Swap

# Kubernetes has limited support for the use of swap memory, as it is difficult to provide guarantees and account for pod memory utilization when swap is involved.

# Verify if swap is disabled:
```bash
sudo swapon --show
```

# If output is empty then swap is disabled. If swap is enabled run the following command to disable swap immediately:
```bash
sudo swapoff -a
```

> To ensure swap remains off after reboot consult your Linux distro documentation.

# Create the installation directories:
```bash
sudo mkdir -p \
  /etc/cni/net.d \
  /opt/cni/bin \
  /var/lib/kubelet \
  /var/lib/kube-proxy \
  /var/lib/kubernetes \
  /var/run/kubernetes
```

# Install the worker binaries:
```bash
{
  sudo mv crictl kube-proxy kubelet runc \
    /usr/local/bin/
  sudo mv containerd containerd-shim-runc-v2 containerd-stress /bin/
  sudo mv cni-plugins/* /opt/cni/bin/
}
```

### Configure CNI Networking

# Create the `bridge` network configuration file:
```bash
sudo mv 10-bridge.conf 99-loopback.conf /etc/cni/net.d/
```

# To ensure network traffic crossing the CNI `bridge` network is processed by `iptables`, load and configure the `br-netfilter` kernel module:
```bash
{
  sudo modprobe br-netfilter
  echo "br-netfilter" | sudo tee -a /etc/modules-load.d/modules.conf
}
```

```bash
{
  echo "net.bridge.bridge-nf-call-iptables = 1" | \
    sudo tee -a /etc/sysctl.d/kubernetes.conf
  echo "net.bridge.bridge-nf-call-ip6tables = 1" | \
    sudo tee -a /etc/sysctl.d/kubernetes.conf
  sudo sysctl -p /etc/sysctl.d/kubernetes.conf
}
```

### Configure containerd

# Install the `containerd` configuration files:
```bash
{
  sudo mkdir -p /etc/containerd/
  sudo mv containerd-config.toml /etc/containerd/config.toml
  sudo mv containerd.service /etc/systemd/system/
}
```

### Configure the Kubelet

# Create the `kubelet-config.yaml` configuration file:
```bash
{
  sudo mv kubelet-config.yaml /var/lib/kubelet/
  sudo mv kubelet.service /etc/systemd/system/
}
```

# Update the kubelet service to use the correct hostname override:
```bash
# For node-0
sudo sed -i 's|--v=2|--hostname-override=node-0 \\\n  --v=2|' /etc/systemd/system/kubelet.service
```

### Configure the Kubernetes Proxy

```bash
{
  sudo mv kube-proxy-config.yaml /var/lib/kube-proxy/
  sudo mv kube-proxy.service /etc/systemd/system/
}
```

### Start the Worker Services
```bash
{
  sudo systemctl daemon-reload
  sudo systemctl enable containerd kubelet kube-proxy
  sudo systemctl start containerd kubelet kube-proxy
}
```

# Check if the kubelet service is running:
```bash
sudo systemctl is-active kubelet
```
# OUTPUT SHOULD LOOK LIKE THIS
# ```text
# active
# ```

# NOW DO THE SAME FOR NODE-1
```bash
ssh admin@node-1
```

## Provisioning a Kubernetes Worker Node

# Install the OS dependencies:
```bash
{
  sudo apt-get update
  sudo apt-get -y install socat conntrack ipset kmod
}
```

> The socat binary enables support for the `kubectl port-forward` command.

# Disable Swap

# Kubernetes has limited support for the use of swap memory, as it is difficult to provide guarantees and account for pod memory utilization when swap is involved.

# Verify if swap is disabled:
```bash
sudo swapon --show
```

# If output is empty then swap is disabled. If swap is enabled run the following command to disable swap immediately:
```bash
sudo swapoff -a
```

> To ensure swap remains off after reboot consult your Linux distro documentation.

# Create the installation directories:
```bash
sudo mkdir -p \
  /etc/cni/net.d \
  /opt/cni/bin \
  /var/lib/kubelet \
  /var/lib/kube-proxy \
  /var/lib/kubernetes \
  /var/run/kubernetes
```

# Install the worker binaries:
```bash
{
  sudo mv crictl kube-proxy kubelet runc \
    /usr/local/bin/
  sudo mv containerd containerd-shim-runc-v2 containerd-stress /bin/
  sudo mv cni-plugins/* /opt/cni/bin/
}
```

### Configure CNI Networking

# Create the `bridge` network configuration file:
```bash
sudo mv 10-bridge.conf 99-loopback.conf /etc/cni/net.d/
```

# To ensure network traffic crossing the CNI `bridge` network is processed by `iptables`, load and configure the `br-netfilter` kernel module:
```bash
{
  sudo modprobe br-netfilter
  echo "br-netfilter" | sudo tee -a /etc/modules-load.d/modules.conf
}
```

```bash
{
  echo "net.bridge.bridge-nf-call-iptables = 1" | \
    sudo tee -a /etc/sysctl.d/kubernetes.conf
  echo "net.bridge.bridge-nf-call-ip6tables = 1" | \
    sudo tee -a /etc/sysctl.d/kubernetes.conf
  sudo sysctl -p /etc/sysctl.d/kubernetes.conf
}
```

### Configure containerd

# Install the `containerd` configuration files:
```bash
{
  sudo mkdir -p /etc/containerd/
  sudo mv containerd-config.toml /etc/containerd/config.toml
  sudo mv containerd.service /etc/systemd/system/
}
```

### Configure the Kubelet

# Create the `kubelet-config.yaml` configuration file:
```bash
{
  sudo mv kubelet-config.yaml /var/lib/kubelet/
  sudo mv kubelet.service /etc/systemd/system/
}
```

# Update the kubelet service to use the correct hostname override:
```bash
# For node-1
sudo sed -i 's|--v=2|--hostname-override=node-1 \\\n  --v=2|' /etc/systemd/system/kubelet.service
```

### Configure the Kubernetes Proxy

```bash
{
  sudo mv kube-proxy-config.yaml /var/lib/kube-proxy/
  sudo mv kube-proxy.service /etc/systemd/system/
}
```

### Start the Worker Services
```bash
{
  sudo systemctl daemon-reload
  sudo systemctl enable containerd kubelet kube-proxy
  sudo systemctl start containerd kubelet kube-proxy
}
```

# Check if the kubelet service is running:
```bash
sudo systemctl is-active kubelet
```
# OUTPUT SHOULD LOOK LIKE THIS
# ```text
# active
# ```

# Be sure to complete the steps in this section on each worker node, `node-0` and `node-1`, before moving on to the next section.

## Verification

# Run the following commands from the `jumpbox` machine.

# SSH INTO JUMPBOX WORKING DIRECTORY
```bash
ssh admin@jumpbox
```

# List the registered Kubernetes nodes:
```bash
ssh admin@server \
  "kubectl get nodes \
  --kubeconfig admin.kubeconfig"
```

# OUTPUT SHOULD LOOK LIKE THIS
# ```text
# NAME     STATUS   ROLES    AGE    VERSION
# node-0   Ready    <none>   1m     v1.32.3
# node-1   Ready    <none>   10s    v1.32.3
# ```

# ********END OF STEP 09********

# Configuring kubectl for Remote Access

# **Run from the Jumpbox Machine**

# In this lab you will generate a kubeconfig file for the `kubectl` command line utility based on the `admin` user credentials.

# > Run the commands in this lab from the `jumpbox` machine.

## The Admin Kubernetes Configuration File

# Each kubeconfig requires a Kubernetes API Server to connect to.

# You should be able to ping `server.kubernetes.local` based on the `/etc/hosts` DNS entry from a previous lab.
```bash
curl --cacert ca.crt \
  https://server.kubernetes.local:6443/version
```

# OUTPUT SHOULD LOOK LIKE THIS
# ```text
# {
#   "major": "1",
#   "minor": "32",
#   "gitVersion": "v1.32.3",
#   "gitCommit": "32cc146f75aad04beaaa245a7157eb35063a9f99",
#   "gitTreeState": "clean",
#   "buildDate": "2025-03-11T19:52:21Z",
#   "goVersion": "go1.23.6",
#   "compiler": "gc",
#   "platform": "linux/arm64"
# }
# ```

# Generate a kubeconfig file suitable for authenticating as the `admin` user:
```bash
{
  kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=ca.crt \
    --embed-certs=true \
    --server=https://server.kubernetes.local:6443

  kubectl config set-credentials admin \
    --client-certificate=admin.crt \
    --client-key=admin.key

  kubectl config set-context kubernetes-the-hard-way \
    --cluster=kubernetes-the-hard-way \
    --user=admin

  kubectl config use-context kubernetes-the-hard-way
}
```

# The results of running the command above should create a kubeconfig file in the default location `~/.kube/config` used by the `kubectl` commandline tool. This also means you can run the `kubectl` command without specifying a config.

## Verification

# Check the version of the remote Kubernetes cluster:

```bash
kubectl version
```
# OUTPUT SHOULD LOOK LIKE THIS
# ```text
# Client Version: v1.32.3
# Kustomize Version: v5.5.0
# Server Version: v1.32.3
# ```

# List the nodes in the remote Kubernetes cluster:
```bash
kubectl get nodes
```

# ```
# NAME     STATUS   ROLES    AGE    VERSION
# node-0   Ready    <none>   10m   v1.32.3
# node-1   Ready    <none>   10m   v1.32.3
# ```

# ********END OF STEP 10********

# Provisioning Pod Network Routes

# Pods scheduled to a node receive an IP address from the node's Pod CIDR range. At this point pods can not communicate with other pods running on different nodes due to missing network [routes](https://cloud.google.com/compute/docs/vpc/routes).

# In this lab you will create a route for each worker node that maps the node's Pod CIDR range to the node's internal IP address.

# > There are [other ways](https://kubernetes.io/docs/concepts/cluster-administration/networking/#how-to-achieve-this) to implement the Kubernetes networking model.

# The Routing Table

# In this section you will gather the information required to create routes in the `kubernetes-the-hard-way` VPC network.

# Print the internal IP address and Pod CIDR range for each worker instance:
```bash
{
  SERVER_IP=$(grep server machines.txt | cut -d " " -f 1)
  NODE_0_IP=$(grep node-0 machines.txt | cut -d " " -f 1)
  NODE_0_SUBNET=$(grep node-0 machines.txt | cut -d " " -f 4)
  NODE_1_IP=$(grep node-1 machines.txt | cut -d " " -f 1)
  NODE_1_SUBNET=$(grep node-1 machines.txt | cut -d " " -f 4)
}
```

```bash
ssh admin@server <<EOF
  sudo ip route add ${NODE_0_SUBNET} via ${NODE_0_IP}
  sudo ip route add ${NODE_1_SUBNET} via ${NODE_1_IP}
EOF
```

```bash
ssh admin@node-0 <<EOF
  sudo ip route add ${NODE_1_SUBNET} via ${NODE_1_IP}
EOF
```

```bash
ssh admin@node-1 <<EOF
  sudo ip route add ${NODE_0_SUBNET} via ${NODE_0_IP}
EOF
```

## Verification

```bash
ssh admin@server "sudo ip route"
```
# OUTPUT SHOULD LOOK LIKE THIS
# ```text
# default via XXX.XXX.XXX.XXX dev ens160
# 10.244.0.0/24 via XXX.XXX.XXX.XXX dev ens160
# 10.244.1.0/24 via XXX.XXX.XXX.XXX dev ens160
# XXX.XXX.XXX.0/24 dev ens160 proto kernel scope link src XXX.XXX.XXX.XXX
# ```

```bash
ssh admin@node-0 "sudo ip route"
```
# OUTPUT SHOULD LOOK LIKE THIS
# ```text
# default via XXX.XXX.XXX.XXX dev ens160
# 10.244.1.0/24 via XXX.XXX.XXX.XXX dev ens160
# XXX.XXX.XXX.0/24 dev ens160 proto kernel scope link src XXX.XXX.XXX.XXX
# ```

```bash
ssh admin@node-1 "sudo ip route"
```
# OUTPUT SHOULD LOOK LIKE THIS
# ```text
# default via XXX.XXX.XXX.XXX dev ens160
# 10.244.1.0/24 via XXX.XXX.XXX.XXX dev ens160
# XXX.XXX.XXX.0/24 dev ens160 proto kernel scope link src XXX.XXX.XXX.XXX
# ```

# ********END OF STEP 11********

# Smoke Test
# In this lab you will complete a series of tasks to ensure your Kubernetes cluster is functioning correctly.

## Data Encryption

# In this section you will verify the ability to [encrypt secret data at rest](https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/#verifying-that-data-is-encrypted).

# Create a generic secret:
```bash
kubectl create secret generic kubernetes-the-hard-way \
  --from-literal="mykey=mydata"
```

# Print a hexdump of the `kubernetes-the-hard-way` secret stored in etcd:
```bash
ssh admin@server \
    'sudo etcdctl get /registry/secrets/default/kubernetes-the-hard-way | hexdump -C'
```

# ```text
# 00000000  2f 72 65 67 69 73 74 72  79 2f 73 65 63 72 65 74  |/registry/secret|
# 00000010  73 2f 64 65 66 61 75 6c  74 2f 6b 75 62 65 72 6e  |s/default/kubern|
# 00000020  65 74 65 73 2d 74 68 65  2d 68 61 72 64 2d 77 61  |etes-the-hard-wa|
# 00000030  79 0a 6b 38 73 3a 65 6e  63 3a 61 65 73 63 62 63  |y.k8s:enc:aescbc|
# 00000040  3a 76 31 3a 6b 65 79 31  3a 4f 1b 80 d8 89 72 f4  |:v1:key1:O....r.|
# 00000050  60 8a 2c a0 76 1a e1 dc  98 d6 00 7a a4 2f f3 92  |`.,.v......z./..|
# 00000060  87 63 c9 22 f4 58 c8 27  b9 ff 2c 2e 1a b6 55 be  |.c.".X.'..,...U.|
# 00000070  d5 5c 4d 69 82 2f b7 e4  b3 b0 12 e1 58 c4 9c 77  |.\Mi./......X..w|
# 00000080  78 0c 1a 90 c9 c1 23 6c  73 8e 6e fd 8e 9c 3d 84  |x.....#ls.n...=.|
# 00000090  7d bf 69 81 ce c9 aa 38  be 3b dd 66 aa a3 33 27  |}.i....8.;.f..3'|
# 000000a0  df be 6d ac 1c 6d 8a 82  df b3 19 da 0f 93 94 1e  |..m..m..........|
# 000000b0  e0 7d 46 8d b5 14 d0 c5  97 e2 94 76 26 a8 cb 33  |.}F........v&..3|
# 000000c0  57 2a d0 27 a6 5a e1 76  a7 3f f0 b7 0a 7b ff 53  |W*.'.Z.v.?...{.S|
# 000000d0  cf c9 1a 18 5b 45 f8 b1  06 3b a9 45 02 76 23 61  |....[E...;.E.v#a|
# 000000e0  5e dc 86 cf 8e a4 d3 c9  5c 6a 6f e6 33 7b 5b 8f  |^.......\jo.3{[.|
# 000000f0  fb 8a 14 74 58 f9 49 2f  97 98 cc 5c d4 4a 10 1a  |...tX.I/...\.J..|
# 00000100  64 0a 79 21 68 a0 9e 7a  03 b7 19 e6 20 e4 1b ce  |d.y!h..z.... ...|
# 00000110  91 64 ce 90 d9 4f 86 ca  fb 45 2f d6 56 93 68 e1  |.d...O...E/.V.h.|
# 00000120  0b aa 8c a0 20 a6 97 fa  a1 de 07 6d 5b 4c 02 96  |.... ......m[L..|
# 00000130  31 70 20 83 16 f9 0a 22  5c 63 ad f1 ea 41 a7 1e  |1p ...."\c...A..|
# 00000140  29 1a d4 a4 e9 d7 0c 04  74 66 04 6d 73 d8 2e 3f  |).......tf.ms..?|
# 00000150  f0 b9 2f 77 bd 07 d7 7c  42 0a                    |../w...|B.|
# 0000015a
# ```

# The etcd key should be prefixed with `k8s:enc:aescbc:v1:key1`, which indicates the `aescbc` provider was used to encrypt the data with the `key1` encryption key.

## Deployments

# In this section you will verify the ability to create and manage [Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/).

# Create a deployment for the [nginx](https://nginx.org/en/) web server:
```bash
kubectl create deployment nginx \
  --image=nginx:latest
```

# List the pod created by the `nginx` deployment:
```bash
kubectl get pods -l app=nginx
```
# OUTPUT SHOULD LOOK LIKE THIS
# ```text
# NAME                     READY   STATUS    RESTARTS   AGE
# nginx-56fcf95486-c8dnx   1/1     Running   0          8s
# ```


### Port Forwarding

# In this section you will verify the ability to access applications remotely using [port forwarding](https://kubernetes.io/docs/tasks/access-application-cluster/port-forward-access-application-cluster/).

# Retrieve the full name of the `nginx` pod:
```bash
POD_NAME=$(kubectl get pods -l app=nginx -o jsonpath="{.items[0].metadata.name}")
```

# Verify the pod name was retrieved correctly:
```bash
echo $POD_NAME
```

# Forward port `8080` on your local machine to port `80` of the `nginx` pod:

```bash
kubectl port-forward $POD_NAME 8080:80
```
# OUTPUT SHOULD LOOK LIKE THIS
# ```text
# Forwarding from 127.0.0.1:8080 -> 80
# Forwarding from [::1]:8080 -> 80
# ```

# In a new terminal make an HTTP request using the forwarding address:

```bash
curl --head http://127.0.0.1:8080
```
# OUTPUT SHOULD LOOK LIKE THIS
# ```text
# HTTP/1.1 200 OK
# Server: nginx/1.27.4
# Date: Sun, 06 Apr 2025 17:17:12 GMT
# Content-Type: text/html
# Content-Length: 615
# Last-Modified: Wed, 05 Feb 2025 11:06:32 GMT
# Connection: keep-alive
# ETag: "67a34638-267"
# Accept-Ranges: bytes
# ```

# Switch back to the previous terminal and stop the port forwarding to the `nginx` pod:
# OUTPUT SHOULD LOOK LIKE THIS
# ```text
# Forwarding from 127.0.0.1:8080 -> 80
# Forwarding from [::1]:8080 -> 80
# Handling connection for 8080
# ^C
# ```

### Logs

# In this section you will verify the ability to [retrieve container logs](https://kubernetes.io/docs/concepts/cluster-administration/logging/).

# Print the `nginx` pod logs:
```bash
kubectl logs $POD_NAME
```
# OUTPUT SHOULD LOOK LIKE THIS
# ```text
# ...
# 127.0.0.1 - - [06/Apr/2025:17:17:12 +0000] "HEAD / HTTP/1.1" 200 0 "-" "curl/7.88.1" "-"
# ```

### Exec

# In this section you will verify the ability to [execute commands in a container](https://kubernetes.io/docs/tasks/debug-application-cluster/get-shell-running-container/#running-individual-commands-in-a-container).

# Print the nginx version by executing the `nginx -v` command in the `nginx` container:

```bash
kubectl exec -ti $POD_NAME -- nginx -v
```
# OUTPUT SHOULD LOOK LIKE THIS
# ```text
# nginx version: nginx/1.27.4
# ```

## Services

# In this section you will verify the ability to expose applications using a [Service](https://kubernetes.io/docs/concepts/services-networking/service/).

# Expose the `nginx` deployment using a [NodePort](https://kubernetes.io/docs/concepts/services-networking/service/#type-nodeport) service:
```bash
kubectl expose deployment nginx \
  --port 80 --type NodePort
```

# > The LoadBalancer service type can not be used because your cluster is not configured with [cloud provider integration](https://kubernetes.io/docs/getting-started-guides/scratch/#cloud-provider). Setting up cloud provider integration is out of scope for this tutorial.

# Retrieve the node port assigned to the `nginx` service:
```bash
NODE_PORT=$(kubectl get svc nginx \
  --output=jsonpath='{range .spec.ports[0]}{.nodePort}')
```

# Retrieve the hostname of the node running the `nginx` pod:
```bash
NODE_NAME=$(kubectl get pods \
  -l app=nginx \
  -o jsonpath="{.items[0].spec.nodeName}")
```

# Make an HTTP request using the IP address and the `nginx` node port:
```bash
curl -I http://${NODE_NAME}:${NODE_PORT}
```
# OUTPUT SHOULD LOOK LIKE THIS
# ```text
# Server: nginx/1.27.4
# Date: Sun, 06 Apr 2025 17:18:36 GMT
# Content-Type: text/html
# Content-Length: 615
# Last-Modified: Wed, 05 Feb 2025 11:06:32 GMT
# Connection: keep-alive
# ETag: "67a34638-267"
# Accept-Ranges: bytes
# ```

# Next: [Cleaning Up](13-cleanup.md)
