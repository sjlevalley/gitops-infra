# Monitoring — Prometheus + Grafana

Installs [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack), which bundles:

- **Prometheus** — metrics collection and storage
- **Grafana** — dashboards and visualization
- **Alertmanager** — alert routing
- **kube-state-metrics** — cluster object metrics (pods, deployments, nodes, etc.)
- **node-exporter** — host-level metrics (CPU, memory, disk) on every node

## Configuration

[`values.yaml`](./values.yaml) contains all tuning. Key decisions for this cluster:

| Setting | Value | Reason |
|---------|-------|--------|
| Prometheus persistence | disabled (emptyDir) | No StorageClass configured |
| Alertmanager persistence | disabled (emptyDir) | Same |
| Grafana persistence | disabled | Dashboards provisioned from ConfigMaps |
| Grafana service type | NodePort 32000 | No ingress controller |
| Prometheus retention | 24h | Limits memory growth without a PVC |
| Resource limits | Conservative | t3.small workers (2 GB RAM) |

> **Note on persistence:** Disabling persistence means Prometheus loses all historical metrics when the pod restarts (upgrade, eviction, node reboot). This is acceptable for a dev/learning cluster. To add persistence later, install the [EBS CSI driver](https://github.com/kubernetes-sigs/aws-ebs-csi-driver), create a StorageClass, and update `storageSpec` / `persistence.enabled` in `values.yaml`.

## Install — Option A: Direct Helm (no ArgoCD required)

Use this path to install immediately without ArgoCD, or to test changes before committing.

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --values values.yaml \
  --version ">=65.0.0"
```

Wait for all pods to become ready:

```bash
kubectl wait --for=condition=Ready pods --all -n monitoring --timeout=180s
```

## Install — Option B: ArgoCD Application (recommended once ArgoCD is running)

Apply the Application manifest — ArgoCD will pull the chart and sync the cluster:

```bash
kubectl apply -f argocd-application.yaml
```

Monitor sync status:

```bash
kubectl get application kube-prometheus-stack -n argocd
# or in the ArgoCD UI
```

## Accessing Grafana

Grafana is exposed on NodePort **32000**. Get any worker node's public IP:

```bash
kubectl get nodes -o wide
```

Open `http://<node-public-ip>:32000` in your browser.

Login: `admin` / `admin` (change after first login — Grafana UI → Profile → Change Password).

Pre-built dashboards are included for:
- Kubernetes cluster overview
- Node resource usage (CPU, memory, disk)
- Pod and deployment status
- Prometheus internals

## Upgrading

**Helm install:** run `helm upgrade` with the same values file:

```bash
helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values values.yaml
```

**ArgoCD:** update `targetRevision` in `argocd-application.yaml`, commit, and push. ArgoCD will detect the change and sync automatically (or trigger a manual sync from the UI).

## Uninstall

```bash
# Helm
helm uninstall kube-prometheus-stack -n monitoring

# ArgoCD — delete the Application (cascade-deletes all managed resources)
kubectl delete application kube-prometheus-stack -n argocd
```

CRDs installed by the chart are not removed automatically. To clean them up:

```bash
kubectl get crd | grep coreos.com | awk '{print $1}' | xargs kubectl delete crd
```
