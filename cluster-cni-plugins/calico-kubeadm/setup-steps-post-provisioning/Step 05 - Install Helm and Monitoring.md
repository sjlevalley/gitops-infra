# Step 05 - Install Helm and Monitoring (Prometheus + Grafana)

**Prerequisites:**

- Steps **01–04** are complete.
- All nodes are **Ready**.
- SSH access to the master node.

---

## Ansible (automated)

Both Helm and the full monitoring stack are provisioned automatically by the Ansible playbook. If you ran `ansible-playbook site.yml`, both are already installed — skip to **Access Grafana** below.

To run just these steps on an existing cluster:

```bash
ansible-playbook -i inventory.ini site.yml \
  --start-at-task="Check if Helm is already installed"
```

---

## Manual steps (if not using Ansible)

### Helm

SSH into the master and run:

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version
```

### Monitoring (Prometheus + Grafana)

`kube-prometheus-stack` bundles:

| Component | Purpose |
|-----------|---------|
| Prometheus | Metrics collection and storage |
| Grafana | Dashboards and visualization |
| Alertmanager | Alert routing |
| kube-state-metrics | Cluster object metrics (pods, deployments, nodes) |
| node-exporter | Host-level metrics (CPU, memory, disk) on every node |

**Step 1 — Install metrics-server** (run on master):

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Required on kubeadm — kubelet uses self-signed certs
kubectl patch deployment metrics-server -n kube-system --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'

kubectl rollout status deployment/metrics-server -n kube-system --timeout=90s

# Verify
kubectl top nodes
```

> **Why `--kubelet-insecure-tls` is needed:** kubeadm generates self-signed certificates for the kubelet. metrics-server validates TLS by default and rejects self-signed certs, causing it to crash-loop. This flag disables that validation. On managed clusters (EKS, GKE) this is not needed because the kubelet certs are CA-signed.

**Step 3 — Copy values file to the master** (run from your local machine in Git Bash).

Public IPs and the key path are read from Terraform state so they always match the current cluster. Run this block once per shell:

```bash
REPO="/c/Users/sleva/OneDrive/Desktop/Desktop/ActiveApps/EC2-Kubernetes"
TF_DIR="$REPO/gitops-infra/cluster-cni-plugins/calico-kubeadm/terraform"
MASTER_IP=$(terraform -chdir="$TF_DIR" output -raw server_public_ip)
KEY="$TF_DIR/k8s-key.pem"

scp -i "$KEY" \
  "$REPO/gitops-infra/cluster-addons/monitoring/values.yaml" \
  "admin@${MASTER_IP}:/tmp/monitoring-values.yaml"
```

**Step 4 — Install kube-prometheus-stack** (run on master):

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --values /tmp/monitoring-values.yaml \
  --version ">=65.0.0"
```

**Step 5 — Wait for pods to be ready:**

```bash
kubectl wait --for=condition=Ready pods --all -n monitoring --timeout=180s
kubectl get pods -n monitoring
```

---

## Access Grafana

Grafana is exposed on NodePort **32000** on any node's public IP. Print the live URLs (run from your local machine in Git Bash, after the "Load cluster values" block):

```bash
TF_DIR="/c/Users/sleva/OneDrive/Desktop/Desktop/ActiveApps/EC2-Kubernetes/gitops-infra/cluster-cni-plugins/calico-kubeadm/terraform"
for o in server_public_ip node_0_public_ip node_1_public_ip; do
  echo "http://$(terraform -chdir="$TF_DIR" output -raw $o):32000"
done
```

Open any of the printed URLs in your browser.

Login: `admin` / `admin`

Change the password after first login: **Profile → Change Password**.

Pre-built dashboards are included for:
- Kubernetes cluster overview
- Node resource usage (CPU, memory, disk)
- Pod and deployment status
- Prometheus internals

---

## Key config decisions (values.yaml)

| Setting | Value | Reason |
|---------|-------|--------|
| Persistence | Disabled (emptyDir) | No StorageClass — metrics are lost on pod restart. Acceptable for dev. |
| Prometheus retention | 24h | Limits memory growth on t3.small nodes |
| Grafana NodePort | 32000 | No ingress controller required |
| Resource limits | Conservative | Tuned for 2 GB RAM workers |

---

## Troubleshooting

### Dashboards show no data after install

This is the most common issue on kubeadm clusters. Run this to check which Prometheus targets are down:

```bash
kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090 &
sleep 2
curl -s http://localhost:9090/api/v1/targets | python3 -m json.tool | grep -E '"health"|"job"'
kill %1
```

---

### kube-scheduler, kube-controller-manager, kube-etcd, kube-proxy targets are `down`

**Why it happens:** kubeadm binds these components' metrics ports to `127.0.0.1` (localhost) as a security default. Prometheus runs in a pod on the pod network and cannot reach `127.0.0.1` on the host, so all four targets report `down` and their dashboards have no data.

**Fix — run on the master:**

```bash
# kube-proxy: patch the ConfigMap and restart the DaemonSet
kubectl -n kube-system get cm kube-proxy -o yaml | \
  sed 's/metricsBindAddress: ""/metricsBindAddress: "0.0.0.0:10249"/' | \
  kubectl apply -f -
kubectl -n kube-system rollout restart daemonset kube-proxy

# kube-controller-manager and kube-scheduler: edit the static pod manifests
sudo sed -i 's/--bind-address=127.0.0.1/--bind-address=0.0.0.0/' \
  /etc/kubernetes/manifests/kube-controller-manager.yaml

sudo sed -i 's/--bind-address=127.0.0.1/--bind-address=0.0.0.0/' \
  /etc/kubernetes/manifests/kube-scheduler.yaml

# etcd: change its metrics listen URL
sudo sed -i 's|--listen-metrics-urls=http://127.0.0.1:2381|--listen-metrics-urls=http://0.0.0.0:2381|' \
  /etc/kubernetes/manifests/etcd.yaml
```

Kubelet detects changes to `/etc/kubernetes/manifests/` automatically and restarts the affected static pods within ~30 seconds. Re-run the targets check to confirm all four come up as `"health": "up"`.

> **Note:** This is a kubeadm-specific issue. Managed clusters (EKS, GKE, AKS) expose these endpoints by default, which is what `kube-prometheus-stack` assumes. On any kubeadm cluster these fixes must be applied manually after install.

---

### Grafana is `2/3` Ready and readiness probe keeps failing

**Why it happens:** The default readiness probe timeout is 1 second. On resource-constrained nodes (t3.small, 2 GB RAM) Grafana can take longer than 1 second to respond to health checks, causing Kubernetes to mark it not-ready even though it is serving traffic normally.

**Fix:**

```bash
kubectl patch deployment kube-prometheus-stack-grafana -n monitoring --type=json \
  -p='[{"op":"replace","path":"/spec/template/spec/containers/2/readinessProbe/timeoutSeconds","value":10}]'
```

This increases the probe timeout to 10 seconds without changing any other behaviour. Grafana will cycle to `3/3` Ready within a minute.

---

## Upgrading

```bash
helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values /tmp/monitoring-values.yaml
```

## Uninstall

```bash
helm uninstall kube-prometheus-stack -n monitoring

# Clean up CRDs (not removed automatically)
kubectl get crd | grep coreos.com | awk '{print $1}' | xargs kubectl delete crd
```
