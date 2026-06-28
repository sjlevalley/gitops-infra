# Step 15 - Deploy Trino via Argo CD (GitOps)

Deploys the **Trino** query engine (TPC-H / TPC-DS benchmark catalogs only — no
external databases, no custom image) using the GitOps flow: manifests live in the
`gitops-kubernetes` repo and **Argo CD** reconciles them onto the cluster.

**Prerequisites:**

- Step 07 complete — Argo CD is running and reachable on NodePort `32100`.
- `git` push access to `github.com/sjlevalley/gitops-kubernetes`.

---

## How it fits together

```
gitops-kubernetes/base/trino/  ──(git push)──►  GitHub
        │                                          │
        │                                   Argo CD watches
        ▼                                          ▼
  Kustomize manifests  ─────────────────►  trino namespace (Deployment+Service)
 (trinodb/trino:latest, tpch/tpcds)            NodePort 32200 → Trino Web UI
```

Unlike Step 14 (manual `kubectl apply`), here **Argo CD applies the manifests**.
You never run `kubectl apply` against the workloads — you commit to Git and Argo
syncs.

---

## Step 1 — Push the Trino manifests to GitHub

Argo CD pulls from the **remote**, so the manifests must be pushed before it can
see them. They already exist locally at `gitops-kubernetes/base/trino/`.

```bash
cd "/c/Users/sleva/OneDrive/Desktop/Desktop/ActiveApps/EC2-Kubernetes/gitops-kubernetes"
git add base/trino
git commit -m "add: Trino-only (tpch/tpcds) base manifests"
git push origin main
```

Manifests in this directory:

| File | Purpose |
|------|---------|
| `namespace.yaml` | `trino` namespace |
| `configmap-catalogs.yaml` | `tpch` + `tpcds` catalog properties (mounted at `/etc/trino/catalog`) |
| `configmap-jvm.yaml` | pins JVM heap to `-Xmx2G` so the pod can't OOM the node |
| `deployment.yaml` | single `trinodb/trino:latest` coordinator (1Gi req / 3Gi limit) |
| `service.yaml` | NodePort `32200` → Trino `:8080` |
| `kustomization.yaml` | ties them together (`namespace: trino`) |

---

## Step 2 — Register the Argo CD Application

The Argo `Application` (pointing at `base/trino`) is at
`gitops-infra/cluster-addons/trino/argocd-application.yaml`. Apply it once to tell
Argo CD to manage Trino. Copy it to the master and apply:

```bash
# From your local machine (Git Bash) — reuse the "Load cluster values" block from Step 14
scp -i "$KEY" \
  "/c/Users/sleva/OneDrive/Desktop/Desktop/ActiveApps/EC2-Kubernetes/gitops-infra/cluster-addons/trino/argocd-application.yaml" \
  "admin@${MASTER_IP}:/tmp/trino-application.yaml"

ssh -i "$KEY" "admin@${MASTER_IP}" \
  "kubectl apply -f /tmp/trino-application.yaml"
```

(Alternatively, in the Argo CD UI from Step 07: **+ NEW APP → EDIT AS YAML**, paste
the file, **CREATE**.)

---

## Step 3 — Watch Argo CD sync

In the Argo CD UI (`http://<node-ip>:32100`) the `trino` Application appears and
moves to **Synced / Healthy**. Or from the master:

```bash
kubectl get applications -n argocd
kubectl get pods -n trino -w
# Ctrl+C once trino-xxxxx is 1/1 Running
```

The pod may sit at `0/1` for ~30–60s while Trino's coordinator starts and the
`/v1/info` readiness probe begins passing — this is normal.

---

## Step 4 — Query Trino

Trino's Web UI / client endpoint is on **NodePort 32200**. Print the URLs:

```bash
TF_DIR="/c/Users/sleva/OneDrive/Desktop/Desktop/ActiveApps/EC2-Kubernetes/gitops-infra/cluster-cni-plugins/calico-kubeadm/terraform"
for o in server_public_ip node_0_public_ip node_1_public_ip; do
  echo "http://$(terraform -chdir="$TF_DIR" output -raw $o):32200/ui/"
done
```

Open a URL and log in to the Trino Web UI with **any username** (e.g. `admin`) —
no password is configured. The UI shows running/finished queries.

To actually run SQL, use the Trino CLI from the master (no external deps):

```bash
ssh -i "$KEY" "admin@${MASTER_IP}"

# Run a query through the in-cluster service
kubectl exec -n trino deploy/trino -- \
  trino --execute "SELECT * FROM tpch.tiny.nation LIMIT 5;"

kubectl exec -n trino deploy/trino -- \
  trino --execute "SELECT count(*) FROM tpch.sf1.orders;"

# Interactive shell
kubectl exec -it -n trino deploy/trino -- trino
#   trino> SHOW CATALOGS;        -- tpch, tpcds, system, ...
#   trino> SHOW SCHEMAS FROM tpch;
#   trino> SELECT * FROM tpcds.tiny.customer LIMIT 10;
```

---

## Step 5 — Verify GitOps reconciliation (optional)

Confirm Argo CD owns the deployment: scale the Deployment by hand and watch Argo
heal it back (because `selfHeal: true`):

```bash
kubectl scale deployment/trino -n trino --replicas=0
# Within ~1 min Argo CD reverts it to replicas=1
kubectl get pods -n trino -w
```

To change Trino for real, edit `gitops-kubernetes/base/trino/` and `git push` —
Argo CD applies the change.

---

## Troubleshooting

### Application stuck `OutOfSync` / `Unknown`
```bash
kubectl describe application trino -n argocd
# Common causes: manifests not pushed to GitHub yet (Step 1), or wrong repoURL/path
```

### Trino pod `CrashLoopBackOff` or `OOMKilled`
```bash
kubectl logs -n trino deploy/trino --tail=40
kubectl describe pod -n trino -l app=trino | grep -A3 -i "last state\|reason"
# If OOMKilled, lower -Xmx in configmap-jvm.yaml or raise the memory limit in
# deployment.yaml, then git push (Argo re-syncs).
```

### NodePort 32200 unreachable from browser
The security group allows TCP 30000–32767. Confirm you're using a **node public
IP** and that the service exists: `kubectl get svc -n trino`.

---

## Clean up

```bash
# Deleting the Application cascades to all Trino resources (finalizer is set)
kubectl delete application trino -n argocd
```
