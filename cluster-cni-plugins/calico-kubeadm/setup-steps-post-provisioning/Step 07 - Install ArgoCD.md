# Step 07 - Install Argo CD (GitOps Controller)

**Prerequisites:**

- Steps **01–06** are complete (cluster, Calico, monitoring, and logging are up).
- Helm is installed on the master (Step 05).
- SSH access to the master node.

Argo CD is the GitOps controller: it watches a Git repository and reconciles the
cluster to match what is declared there. It is bootstrapped once via Helm, then
used to deploy applications (e.g. Trino in Step 09).

---

## Ansible (automated)

Argo CD is provisioned automatically by the playbook (the `argocd` role, run after
Loki). If you ran `ansible-playbook site.yml`, it is already installed — skip to
**Access the UI** below.

To install/refresh just Argo CD on an existing cluster, use the play's tag:

```bash
ansible-playbook -i inventory.ini site.yml --tags argocd \
  -e ansible_ssh_private_key_file=~/k8s-key.pem
```

The role:
- `helm install argocd argo/argo-cd` (v7.x) into the `argocd` namespace
- exposes the server as **NodePort 32100** with `server.insecure=true`
- waits for all pods to be Ready and prints the initial admin password

---

## Manual steps (if not using Ansible)

SSH into the master and follow the canonical instructions in
[`gitops-infra/cluster-addons/argocd/README.md`](../../../cluster-addons/argocd/README.md).
In short:

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

helm install argocd argo/argo-cd \
  --namespace argocd --create-namespace \
  --version ">=7.0.0 <8.0.0" \
  --set configs.params."server\.insecure"=true \
  --set server.service.type=NodePort \
  --set server.service.nodePortHttp=32100

kubectl wait --for=condition=Ready pods --all -n argocd --timeout=300s
```

---

## Access the UI

Argo CD is on **NodePort 32100** of any node's public IP. Print the live URLs
(run from your local machine in Git Bash, after the "Load cluster values" block
in Step 08):

```bash
TF_DIR="/c/Users/sleva/OneDrive/Desktop/Desktop/ActiveApps/EC2-Kubernetes/gitops-infra/cluster-cni-plugins/calico-kubeadm/terraform"
for o in server_public_ip node_0_public_ip node_1_public_ip; do
  echo "http://$(terraform -chdir="$TF_DIR" output -raw $o):32100"
done
```

Open any of the printed URLs in your browser.

**Login:** `admin` / the initial password. The Ansible run prints it; otherwise
fetch it on the master:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo
```

Change the password after first login: **User Info → Update Password**.

---

## Next

With Argo CD running you can hand application deployment over to GitOps. See
**Step 09 - Deploy Trino via ArgoCD** for a worked example that points Argo CD at
the `gitops-kubernetes` repo.
