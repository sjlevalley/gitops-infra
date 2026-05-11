# Step 05 - Deploy an Application (Voting App)

**Prerequisites:**

- Steps **01-02**, **03**, and **04 (Calico)** are complete.
- All nodes are **Ready** and **`calico-system`** pods are healthy (Step 04).
- **`kubectl`** works on the control plane node (master).
- **No Flannel-only steps** apply in this track; ignore any doc that refers to “Setup Flannel on worker nodes.”

**Replace placeholders** below:

| Placeholder | Value |
|-------------|--------|
| `<REPO_ROOT>` | `c:\Users\sleva\OneDrive\Desktop\Desktop\ActiveApps\EC2-Kubernetes` (Git Bash: `/c/Users/sleva/OneDrive/Desktop/Desktop/ActiveApps/EC2-Kubernetes`) |
| `<CONTROL_PLANE_PUBLIC_IP>` | `18.208.246.42` |
| `<PATH_TO_K8S_KEY>` | `gitops-infra/calico-kubeadm/terraform/k8s-key.pem` (relative to repo root) |
| `<ANY_NODE_PUBLIC_IP>` | `18.208.246.42` (master), `54.82.93.211` (node-0), or `98.94.5.234` (node-1) |

Manifests live in this repo at **`gitops-application/applications/voting-app/k8s/`** (not under `kubeadm-with-calico`).

---

## Step 1: Copy voting app manifests to the control plane

***Run from your local machine (not on the cluster).***

```bash
cd "/c/Users/sleva/OneDrive/Desktop/Desktop/ActiveApps/EC2-Kubernetes"

scp -i "gitops-infra/calico-kubeadm/terraform/k8s-key.pem" -r "gitops-application/applications/voting-app" "admin@18.208.246.42:~/"
```

Verify on the control plane:

```bash
ssh -i "gitops-infra/calico-kubeadm/terraform/k8s-key.pem" "admin@18.208.246.42" "ls -la ~/voting-app/k8s/"
```

You should see the YAML files (`vote-deployment.yaml`, `result-service.yaml`, etc.).

---

## Step 2: Deploy the voting application

***Run on the control plane (SSH session on the master).***

```bash
cd ~/voting-app/k8s

kubectl apply -f .

kubectl get pods
kubectl get services
```

---

## Step 3: Verify deployment

***Run on the control plane***

```bash
kubectl get pods -w
# Ctrl+C when all pods are Running

kubectl get services
kubectl get nodes -o wide
```

---

## Step 4: Test the application (browser)

NodePorts are defined in the voting app manifests (typically **30001** for vote, **30002** for result). Confirm ports:

```bash
kubectl get svc vote result
```

Open in a browser (use **any** node’s **public** IP — NodePort is exposed on every node):

- **Vote:**
  - `http://18.208.246.42:30001` (master)
  - `http://54.82.93.211:30001` (node-0)
  - `http://98.94.5.234:30001` (node-1)
- **Result:**
  - `http://18.208.246.42:30002` (master)
  - `http://54.82.93.211:30002` (node-0)
  - `http://98.94.5.234:30002` (node-1)

**Terraform security group** for this lab already allows **TCP 30000–32767** (NodePort range) from `0.0.0.0/0`, so you normally **do not** need extra rules for 30001–30002.

---

## Step 5: Monitor and troubleshoot

***Run on the control plane***

```bash
kubectl logs -f deployment/vote
kubectl logs -f deployment/result
kubectl logs -f deployment/worker

kubectl describe pod <pod-name>
kubectl get endpoints
kubectl get events --sort-by=.metadata.creationTimestamp
```

---

## Troubleshooting

### Pods stuck in Pending

```bash
kubectl describe nodes
kubectl describe pod <pod-name>
```

### Cannot reach NodePort from your browser

```bash
kubectl get svc
# Confirm NodePort numbers under PORT(S)

curl -sS -o /dev/null -w "%{http_code}" "http://127.0.0.1:30001" --max-time 3
```

If **curl from the node works** but the **browser from the internet does not**, check AWS **security group** (ingress TCP **30000–32767** to the instances) and that you are using a **node public IP**, not only the private IP.

### Database / Redis issues

```bash
kubectl get pods | grep -E "redis|db|postgres"
kubectl logs deployment/redis
kubectl logs deployment/db
kubectl exec -it deployment/redis -- redis-cli ping
```

### Redis / vote errors: “Temporary failure in name resolution” only on worker pods

If **`kubectl run dns-test … nslookup`** works **without** pinning a node, but fails when **`nodeName`** is set to a **worker**, pods on workers cannot reach **ClusterIP** services such as **kube-dns (`10.96.0.10:53`)**. On **EC2**, enable **forwarded/routed pod traffic** by turning **source/destination check** **off** on **every** Kubernetes instance (control plane and workers):

**Console:** EC2 → instance → **Networking** → **Change source/destination check** → **Disabled**.

**CLI:** `aws ec2 modify-instance-attribute --instance-id <id> --no-source-dest-check`

Then re-test DNS from a pod scheduled on a worker (same `kubectl run … --overrides nodeName` pattern).

---

## Useful commands

```bash
kubectl scale deployment vote --replicas=3

kubectl top pods   # requires metrics-server
kubectl top nodes

cd ~/voting-app/k8s && kubectl delete -f .
kubectl rollout restart deployment/vote
```

---

## Expected results

- Pods: **vote**, **result**, **worker**, **redis**, **db** in **Running**.
- Services: vote and result as **NodePort** (ports per `kubectl get svc`).
- Apps reachable on **`http://<node-public-ip>:<nodeport>`**.

---

## Clean up

```bash
cd ~/voting-app/k8s
kubectl delete -f .
kubectl get pods
kubectl get svc
```

---

## Note on Flannel / checksum docs (Calico lab)

This cluster uses **Calico**, not Flannel. You **do not** need:

- Flannel **VXLAN** / UDP **4789** rules for the app (overlay is handled per your Calico install).
- **TX checksum** workarounds on **`flannel.1`** — those apply to **Flannel on Ubuntu/AWS**, not to this Calico setup.

If you later run the **same voting app** on a **Flannel** cluster, see the Flannel troubleshooting scripts under `kubeadm-with-calico/setup-steps-post-provisioning/scripts/` and the older admin-practice notes.
