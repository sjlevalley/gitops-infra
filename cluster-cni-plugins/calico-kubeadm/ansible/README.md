# Calico Kubeadm - Ansible Provisioning

Automates everything in Steps 01-04 of the manual post-provisioning guide.
Run this after Terraform has provisioned the EC2 instances.

## Prerequisites

- Ansible installed on your local machine (`pip install ansible`)
- EC2 instances running (provisioned by `../terraform/`)
- SSH key at `../terraform/k8s-key.pem`

## Setup

### 1. Generate the inventory file

Fill in the public IPs from your Terraform output:

```bash
cd ../terraform
terraform output
```

Then create `ansible/inventory.ini` from the template:

```bash
cd ../ansible
cp inventory.ini.tpl inventory.ini
```

Edit `inventory.ini` and replace the placeholders:
- `{{ server_public_ip }}` — master node public IP
- `{{ node0_public_ip }}` — node-0 public IP
- `{{ node1_public_ip }}` — node-1 public IP
- `{{ ssh_key_path }}` — path to k8s-key.pem (e.g. `../terraform/k8s-key.pem`)

### 2. Verify connectivity

```bash
ansible all -i inventory.ini -m ping
```

## Run the playbook

```bash
ansible-playbook -i inventory.ini site.yml
```

The playbook runs four plays in order:

| Play | Hosts | What it does |
|------|-------|-------------|
| common-setup | all | Installs kubelet, kubeadm, kubectl, containerd, CNI plugins, sysctl settings |
| master-init | master | Runs kubeadm init, configures kubectl, saves the join command |
| worker-join | workers | Fetches the join command from master and joins each worker |
| calico | master | Installs Tigera operator, applies custom resources, restarts containerd+kubelet |

## What is automated (Steps 01-04)

- Step 01-02: All node bootstrapping (packages, containerd config, CNI plugins, sysctl)
- Step 03: kubeadm init on master, worker joins
- Step 04: Calico v3.32.0 via Tigera operator with BGP routing (encapsulation: None)

The playbook also applies the containerd + kubelet restart on the master after Calico
is installed — this resolves the "cni plugin not initialized" NotReady state that
occurs when containerd starts before the Calico CNI config is written.

## Step 05 (Deploy application)

Step 05 (voting app deployment) is not automated here. Run it manually after
the playbook completes using the instructions in:
`setup-steps-post-provisioning/Step 05 - Deploy an Application.md`

## Key differences from flannel-kubeadm ansible

| | flannel-kubeadm | calico-kubeadm |
|---|---|---|
| containerd `bin_dir` | `/usr/lib/cni` | `/opt/cni/bin` |
| CNI install | symlinks to /usr/lib/cni | direct install to /opt/cni/bin |
| CNI plugin | Flannel manifest | Tigera operator + custom resources |
| Encapsulation | VXLAN | None (BGP) |
| Worker join | placeholder only | fully implemented |
| Post-CNI restart | no | yes (fixes master NotReady) |
