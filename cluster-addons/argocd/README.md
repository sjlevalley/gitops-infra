# ArgoCD

ArgoCD is the GitOps controller. It watches Git repositories and reconciles cluster state to match what is declared in Git.

ArgoCD cannot install itself via ArgoCD, so it is bootstrapped once via direct Helm, then left to manage all other addons.

## Prerequisites

- `kubectl` configured and pointing at the cluster
- `helm` v3 installed locally

## Install

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

helm install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  --version ">=7.0.0"
```

Wait for all pods to become ready:

```bash
kubectl wait --for=condition=Ready pods --all -n argocd --timeout=120s
```

## Access the UI

Port-forward to reach the UI from your local machine:

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Open `https://localhost:8080` (accept the self-signed certificate).

Get the generated admin password:

```bash
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath="{.data.password}" | base64 -d && echo
```

Login: `admin` / `<password from above>`

Change the password after first login: **Settings → Account → Update Password**.

## Expose via NodePort (alternative to port-forward)

The cluster security group already allows NodePort range 30000–32767. Patch the service to make the UI available via any node's public IP:

```bash
kubectl patch svc argocd-server -n argocd \
  -p '{"spec": {"type": "NodePort"}}'

# Find the assigned port
kubectl get svc argocd-server -n argocd
```

Access via `https://<node-public-ip>:<nodePort>`.

## ArgoCD CLI (optional)

```bash
# Download CLI (Linux/Mac)
curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x argocd && sudo mv argocd /usr/local/bin/

# Login (while port-forwarding on 8080)
argocd login localhost:8080 --username admin --insecure

# List applications
argocd app list
```

## Next Steps

Once ArgoCD is running, apply the addon Application manifests to hand management over to ArgoCD:

```bash
# Monitoring (Prometheus + Grafana)
kubectl apply -f ../monitoring/argocd-application.yaml
```

ArgoCD will detect the Application, pull the Helm chart, and sync the cluster.
