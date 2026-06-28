# Step 11 - Install Sealed Secrets

**Prerequisites:**

- Steps **01–07** are complete (cluster, Calico, Helm).
- SSH access to the master node.
- `kubectl` available locally or on the master.

> **Manual only.** This addon is **not** in the Ansible playbook yet.

A plain Kubernetes `Secret` is only base64-encoded, not encrypted — you can't
safely commit it to Git. **Sealed Secrets** (Bitnami) solves this for GitOps: a
cluster-side controller holds a private key, and you use the `kubeseal` CLI to
encrypt a Secret into a `SealedSecret` resource with the matching public key. The
`SealedSecret` is safe to commit; only the controller in *this* cluster can
decrypt it back into a real `Secret`.

This pairs naturally with Argo CD (Step 07): commit `SealedSecret` manifests to
the GitOps repo and let Argo CD apply them.

---

## Install the controller

SSH into the master and run:

```bash
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm repo update

helm install sealed-secrets sealed-secrets/sealed-secrets \
  --namespace kube-system

kubectl rollout status deploy/sealed-secrets -n kube-system --timeout=120s
```

> The controller generates a private/public key pair on first start and stores it
> as a secret in `kube-system`. **Back this key up** if you care about decrypting
> old SealedSecrets after a cluster rebuild (see *Back up the key* below).

---

## Install the kubeseal CLI

Install on the master (or your local machine — wherever you'll build manifests):

```bash
KUBESEAL_VERSION=$(curl -s https://api.github.com/repos/bitnami-labs/sealed-secrets/releases/latest \
  | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')

curl -sL "https://github.com/bitnami-labs/sealed-secrets/releases/download/v${KUBESEAL_VERSION}/kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz" \
  | tar xz kubeseal

sudo install -m 0755 kubeseal /usr/local/bin/kubeseal && rm kubeseal
kubeseal --version
```

---

## Verify: seal a secret, apply it, read it back

```bash
# 1. Build a normal Secret manifest WITHOUT applying it
kubectl create secret generic db-cred \
  --from-literal=username=admin \
  --from-literal=password='s3cr3t!' \
  --dry-run=client -o yaml > db-cred.yaml

# 2. Seal it -> produces an encrypted SealedSecret (safe to commit)
kubeseal --controller-namespace kube-system \
  --format yaml < db-cred.yaml > db-cred-sealed.yaml

# Inspect: the values are now encrypted ciphertext, not base64
cat db-cred-sealed.yaml

# 3. Apply the SealedSecret. The controller decrypts it into a real Secret.
kubectl apply -f db-cred-sealed.yaml

# 4. Confirm the controller produced the plaintext Secret
kubectl get secret db-cred -o jsonpath='{.data.password}' | base64 -d; echo
# -> s3cr3t!
```

Clean up:

```bash
kubectl delete sealedsecret db-cred
rm -f db-cred.yaml db-cred-sealed.yaml
# deleting the SealedSecret also garbage-collects the managed Secret
```

> **Never commit `db-cred.yaml`** (the plaintext input). Only the
> `*-sealed.yaml` output is safe for Git.

---

## Back up the encryption key (recommended)

If the cluster is rebuilt, a new controller generates a new key and old
SealedSecrets become undecryptable. Export the active key to restore later:

```bash
kubectl get secret -n kube-system \
  -l sealedsecrets.bitnami.com/sealed-secrets-key=active \
  -o yaml > sealed-secrets-key-backup.yaml
```

Store this file somewhere secure and **out of Git**. To restore on a new cluster:
apply the backup before (or instead of) letting the controller generate a fresh
key, then restart the controller.

---

## Using it with Argo CD (optional)

Commit the `*-sealed.yaml` manifests into the `gitops-kubernetes` repo alongside
your app manifests. Argo CD applies the `SealedSecret`; the controller decrypts
it into a `Secret` your workloads mount. Secrets stay encrypted at rest in Git
while the rest of your config remains plain GitOps.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `kubeseal` hangs or `cannot fetch certificate` | CLI can't reach the controller | Pass `--controller-namespace kube-system` (controller is here, not the default `kube-system`/`sealed-secrets` guess) and ensure kubeconfig is valid |
| SealedSecret applied but no Secret appears | Sealed for a different cluster/key | Re-seal against this cluster's controller |
| `no key could decrypt secret` after rebuild | Controller key changed | Restore the key backup (above) and restart the controller |

---

## Uninstall

```bash
# Delete SealedSecrets first (this removes the managed Secrets), then:
helm uninstall sealed-secrets -n kube-system
```

---

## Next

You now have storage (Step 08), ingress (Step 09), TLS automation (Step 10), and
encrypted secrets (Step 11) on top of the core cluster and observability stack.

Continue to **Step 12 - Enable Encryption at Rest for Secrets** to harden how
Kubernetes stores secrets in etcd. (You can also fold any of these addons into the
Ansible playbook as new roles, mirroring the existing `monitoring`/`loki`/`argocd`
roles.)
