# Step 10 - Install cert-manager

**Prerequisites:**

- Steps **01–07** are complete (cluster, Calico, Helm).
- **Step 09** (ingress-nginx) recommended if you want to serve HTTPS through
  ingress, but cert-manager can be installed and exercised on its own.
- SSH access to the master node.

> **Manual only.** This addon is **not** in the Ansible playbook yet.

**cert-manager** automates issuing and renewing X.509 certificates inside
Kubernetes. You declare an `Issuer`/`ClusterIssuer` (a certificate authority) and
a `Certificate` (what you want), and cert-manager obtains it and stores it in a
TLS secret — then keeps it renewed.

On a public cluster you would use a **Let's Encrypt** `ClusterIssuer`, but that
requires a real DNS name pointing at the cluster and a public HTTP/DNS challenge.
For practice on this private setup we use a **self-signed** issuer, which works
with no external dependencies and exercises the same machinery.

---

## Install

SSH into the master and run:

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update

helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --set crds.enabled=true
```

> **Why `crds.enabled=true`:** cert-manager defines its API (`Certificate`,
> `Issuer`, `ClusterIssuer`, …) as CustomResourceDefinitions. This flag installs
> them with the chart so you don't have to apply the CRD manifest separately.

Wait for all three components (controller, webhook, cainjector) to be ready:

```bash
kubectl wait --for=condition=Available deploy --all \
  -n cert-manager --timeout=180s

kubectl get pods -n cert-manager
```

---

## Create a self-signed ClusterIssuer

A `ClusterIssuer` is cluster-scoped (usable from any namespace):

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned
spec:
  selfSigned: {}
EOF

kubectl get clusterissuer
```

---

## Verify by issuing a certificate

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: example-cert
  namespace: default
spec:
  secretName: example-cert-tls
  issuerRef:
    name: selfsigned
    kind: ClusterIssuer
  commonName: example.local
  dnsNames:
    - example.local
EOF

# Should report READY=True within a few seconds
kubectl get certificate example-cert
kubectl describe certificate example-cert | tail -n 20

# cert-manager wrote the cert+key into this secret
kubectl get secret example-cert-tls -o jsonpath='{.data.tls\.crt}' \
  | base64 -d | openssl x509 -noout -subject -dates
```

Clean up the test:

```bash
kubectl delete certificate example-cert
kubectl delete secret example-cert-tls
```

---

## Serving HTTPS through ingress (optional, needs Step 09)

cert-manager integrates with ingress-nginx via an annotation. With the
`selfsigned` issuer, an ingress can get an auto-generated TLS secret:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: echo-tls
  annotations:
    cert-manager.io/cluster-issuer: selfsigned
spec:
  tls:
    - hosts: [echo.local]
      secretName: echo-tls
  rules:
    - host: echo.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: echo
                port:
                  number: 80
```

cert-manager sees the `tls` block + annotation, issues the cert, and stores it in
`echo-tls`; nginx then terminates HTTPS on **30443**. Browsers will warn because
the cert is self-signed — expected. To remove the warning in production, swap the
issuer for a Let's Encrypt `ClusterIssuer` (ACME HTTP-01) once the cluster has a
public DNS name.

---

## Let's Encrypt issuer (reference — needs public DNS)

For a real domain pointing at the cluster, an ACME issuer looks like:

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: you@example.com
    privateKeySecretRef:
      name: letsencrypt-prod-account-key
    solvers:
      - http01:
          ingress:
            class: nginx
```

This only succeeds if Let's Encrypt can reach `http://<your-domain>/.well-known/...`
through the ingress — i.e. real public DNS and reachable port 80. Skip on this
private practice cluster.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `Certificate` stuck `READY=False` | Issuer not ready / wrong `issuerRef` | `kubectl describe certificate <name>` and check the events |
| Webhook errors on apply (`failed calling webhook`) | Webhook pod not up yet | Wait for `cert-manager-webhook` Ready, then re-apply |
| ACME challenge never completes | No public DNS / port 80 blocked | Use the self-signed issuer for this cluster |

---

## Uninstall

```bash
# Delete Certificates/Issuers first, then:
helm uninstall cert-manager -n cert-manager
kubectl delete namespace cert-manager
# CRDs are removed with the release when installed via crds.enabled=true
```

---

## Next

Continue to **Step 11 - Install Sealed Secrets** to safely store encrypted
secrets in Git for the GitOps workflow.
