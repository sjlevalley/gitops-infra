# Step 06 - Install Loki and Promtail (Log Aggregation)

**Prerequisites:**

- Step 05 is complete — Helm, metrics-server, and kube-prometheus-stack (Prometheus + Grafana) are installed.
- Grafana is accessible on NodePort `32000` of any node's public IP (use the URL printed by Step 05's "Access Grafana" block).

---

## How it fits together

```
Every pod/node
    └── Promtail (DaemonSet)   ← tails container logs, ships to Loki
            └── Loki           ← stores and indexes logs
                    └── Grafana ← queries Loki to display log streams
```

Grafana already visualizes metrics from Prometheus. Adding Loki gives it a second data source for logs. You can switch between them in the Grafana UI or correlate them — click a spike on a metrics graph and jump to the logs from that pod at that exact timestamp.

---

## Ansible (automated)

Loki + Promtail are provisioned automatically by the Ansible playbook after the monitoring role. If you ran `ansible-playbook site.yml`, they are already installed.

To run just this step on an existing cluster:

```bash
ansible-playbook -i inventory.ini site.yml \
  --start-at-task="Add Grafana Helm repo"
```

---

## Manual steps

### Step 1 — Copy values file to the master (run from your local machine in Git Bash)

Public IPs and the key path are read from Terraform state so they always match the current cluster. Run this block once per shell:

```bash
REPO="/c/Users/sleva/OneDrive/Desktop/Desktop/ActiveApps/EC2-Kubernetes"
TF_DIR="$REPO/gitops-infra/cluster-cni-plugins/calico-kubeadm/terraform"
MASTER_IP=$(terraform -chdir="$TF_DIR" output -raw server_public_ip)
KEY="$TF_DIR/k8s-key.pem"

scp -i "$KEY" \
  "$REPO/gitops-infra/cluster-addons/loki/values.yaml" \
  "admin@${MASTER_IP}:/tmp/loki-values.yaml"
```

### Step 2 — Install loki-stack (run on master)

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

helm install loki-stack grafana/loki-stack \
  --namespace monitoring \
  --values /tmp/loki-values.yaml
```

### Step 3 — (no manual datasource needed)

**Do not create a manual datasource ConfigMap.** The `loki-stack` chart already auto-creates a Grafana datasource ConfigMap (labelled `grafana_datasource: "1"`), which the `grafana-sc-datasources` sidecar loads automatically. Adding a second manual one creates a duplicate `Loki` datasource and, combined with the chart's default-marking, breaks Grafana — see the troubleshooting note below. With `loki.isDefault: false` set in `values.yaml` (Step 2), the chart's datasource loads cleanly alongside Prometheus.

### Step 4 — Wait for pods to be ready

```bash
# Loki is a StatefulSet in the loki-stack chart (pod is loki-stack-0), not a Deployment
kubectl rollout status statefulset/loki-stack -n monitoring --timeout=180s
kubectl rollout status daemonset/loki-stack-promtail -n monitoring --timeout=120s
kubectl get pods -n monitoring | grep loki
```

> `loki-stack-0` may sit at `0/1 Running` for ~45–90s after install — its readiness probe (`/ready`) reports not-ready until the ring and storage initialize. This is normal; wait for it to reach `1/1`. If it is still `0/1` after ~3 minutes, check `kubectl logs loki-stack-0 -n monitoring --tail=30`.

---

## Viewing logs in Grafana

1. Open Grafana on NodePort `32000` of any node's public IP (print the live URLs with the loop in Step 05's "Access Grafana" block)
2. Go to **Explore** (compass icon in the left sidebar)
3. Switch the data source dropdown from **Prometheus** to **Loki**
4. Use the log browser to filter by namespace, pod, or container:
   ```
   {namespace="default"}
   {app="vote"}
   {namespace="kube-system"} |= "error"
   ```

Pre-built log dashboards are not included by default — the **Explore** view is the primary way to query logs.

---

## Key config decisions (values.yaml)

| Setting | Value | Reason |
|---------|-------|--------|
| Persistence | Disabled (emptyDir) | No StorageClass — logs lost on Loki restart. Acceptable for dev. |
| Grafana | Disabled | Already installed via kube-prometheus-stack |
| Prometheus | Disabled | Already installed via kube-prometheus-stack |
| Resource limits | Conservative | Tuned for t3.large nodes |

---

## Troubleshooting

### Loki doesn't appear in Grafana's datasource dropdown

Grafana provisions datasources at **startup** and the sidecar usually doesn't hot-reload them. After the `loki-stack` ConfigMap exists, restart Grafana:

```bash
kubectl rollout restart deployment kube-prometheus-stack-grafana -n monitoring
```

Then hard-refresh the Grafana tab (Ctrl+Shift+R) → **Explore**.

### Grafana CrashLoopBackOff: "Only one datasource per organization can be marked as default"

**Symptom:** After installing loki-stack, new Grafana pods crashloop (`2/3`), while the old pod keeps running. Logs from the `grafana` container show:

```
Datasource provisioning error: datasource.yaml config is invalid.
Only one datasource per organization can be marked as default
```

**Cause:** The `loki-stack` chart auto-creates a Loki datasource marked `isDefault: true` (chart default). Prometheus (from kube-prometheus-stack) is already the default, so Grafana refuses to start. A leftover **manual** `loki-datasource` ConfigMap makes it worse by adding a duplicate `Loki`.

**Fix:**

```bash
# Remove any redundant manual datasource ConfigMap (not needed — see Step 3)
kubectl delete configmap loki-datasource -n monitoring --ignore-not-found

# Make the chart's Loki datasource non-default
helm upgrade loki-stack grafana/loki-stack -n monitoring --reuse-values --set loki.isDefault=false

# Confirm
kubectl get cm loki-stack -n monitoring -o go-template='{{range .data}}{{.}}{{end}}' | grep isDefault   # isDefault: false

# Delete the crashlooping Grafana pod so a fresh one reads the corrected datasources
kubectl delete pod -n monitoring -l app.kubernetes.io/name=grafana --field-selector=status.phase!=Running
```

> The repo `values.yaml` now sets `loki.isDefault: false`, so fresh installs won't hit this. The `helm upgrade` above is only needed to repair a cluster installed before that fix.

## Uninstall

```bash
helm uninstall loki-stack -n monitoring
kubectl delete configmap loki-datasource -n monitoring
```
