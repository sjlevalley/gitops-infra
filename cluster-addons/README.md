# Cluster Addons

Infrastructure-level services installed on top of the Kubernetes cluster. These are cluster-wide tools — not application workloads.

## Install Order

| Step | Addon | Namespace | Method |
|------|-------|-----------|--------|
| 1 | [ArgoCD](./argocd/README.md) | `argocd` | Direct Helm (bootstrap) |
| 2 | [Monitoring](./monitoring/README.md) | `monitoring` | Helm or ArgoCD Application |

ArgoCD must be installed first — it manages everything else. For the first install on a fresh cluster, use the direct Helm commands in each addon's README. Once ArgoCD is running, switch to applying the `argocd-application.yaml` manifests and let ArgoCD own the lifecycle.

## Directory Layout

```
cluster-addons/
├── argocd/
│   └── README.md               # Bootstrap install instructions
└── monitoring/
    ├── README.md               # Install instructions (both paths)
    ├── values.yaml             # Helm values for kube-prometheus-stack
    └── argocd-application.yaml # ArgoCD Application manifest
```

## General Conventions

- Each addon lives in its own subdirectory with a `README.md`.
- `values.yaml` files are the source of truth for Helm configuration — edit these, not the ArgoCD Application inline values.
- ArgoCD Applications use [multi-source](https://argo-cd.readthedocs.io/en/stable/user-guide/multiple_sources/) to pull the Helm chart from the chart registry and values from this Git repo.
- Namespaces are created by ArgoCD (`CreateNamespace=true` sync option) — no need to create them manually.
