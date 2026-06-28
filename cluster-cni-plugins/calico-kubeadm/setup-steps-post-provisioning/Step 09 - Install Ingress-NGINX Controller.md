# Step 09 - Install Ingress-NGINX Controller

**Prerequisites:**

- Steps **01–07** are complete (cluster, Calico, Helm).
- SSH access to the master node.
- The cluster security group already allows the NodePort range **30000–32767**.

> **Manual only.** This addon is **not** in the Ansible playbook yet.

Right now every service in this cluster is exposed with its own NodePort
(Grafana 32000, Argo CD 32100, …). That doesn't scale: each app burns a port and
there is no host/path routing or shared TLS. An **ingress controller** is the
standard fix — one entry point that routes HTTP(S) by hostname and path to many
backend services, configured with `Ingress` resources.

We use **ingress-nginx** (the community NGINX controller). Because this cluster
has no cloud load balancer integration, we expose the controller itself via
**NodePort** on fixed ports.

---

## Install

SSH into the master and run:

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --set controller.service.type=NodePort \
  --set controller.service.nodePorts.http=30080 \
  --set controller.service.nodePorts.https=30443 \
  --set controller.ingressClassResource.default=true
```

Wait for the controller to be ready:

```bash
kubectl wait --for=condition=Available deploy \
  -n ingress-nginx ingress-nginx-controller --timeout=180s

kubectl get pods -n ingress-nginx
kubectl get svc  -n ingress-nginx
```

> **Why `nodePorts.http=30080` / `https=30443`:** fixed ports make the URLs
> predictable. Anything in 30000–32767 works (the security group allows the whole
> range). `ingressClassResource.default=true` makes this the default class, so
> `Ingress` objects without an explicit `ingressClassName` use it.

---

## Verify with a test app

Deploy a tiny echo service and route to it by hostname:

```bash
kubectl create deployment echo --image=ealen/echo-server
kubectl expose deployment echo --port=80 --target-port=80

cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: echo
spec:
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
EOF
```

Test it from your local machine (Git Bash). The `Host` header drives routing, so
send it explicitly against any node's public IP on port 30080:

```bash
TF_DIR="/c/Users/sleva/OneDrive/Desktop/Desktop/ActiveApps/EC2-Kubernetes/gitops-infra/cluster-cni-plugins/calico-kubeadm/terraform"
NODE_IP=$(terraform -chdir="$TF_DIR" output -raw server_public_ip)

curl -H "Host: echo.local" "http://${NODE_IP}:30080/"
```

You should get a JSON echo response. Clean up the test:

```bash
kubectl delete ingress echo
kubectl delete svc echo
kubectl delete deployment echo
```

---

## Routing real apps through ingress (optional)

Instead of giving each app a NodePort, point an `Ingress` at its **ClusterIP**
service. For example, to serve Grafana at `grafana.local` you would create an
`Ingress` in the `monitoring` namespace targeting the
`kube-prometheus-stack-grafana` service on port 80. For browser access without
real DNS, add a line to your local `hosts` file:

```
<node-public-ip>  grafana.local echo.local
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `curl` returns `404 Not Found` from nginx | `Host` header doesn't match any Ingress rule | Send the exact host (`-H "Host: echo.local"`) |
| Connection refused on :30080 | Hitting a node where the controller pod isn't scheduled, or SG blocking | NodePort works on every node; confirm SG allows 30000–32767 |
| Ingress created but no `ADDRESS` | Expected on NodePort/bare-metal | Address column stays empty; route by NodePort, not by the reported address |
| 503 from nginx | Backend service has no ready endpoints | `kubectl get endpoints <svc>` — make sure pods are Ready |

---

## Uninstall

```bash
helm uninstall ingress-nginx -n ingress-nginx
kubectl delete namespace ingress-nginx
```

---

## Next

Continue to **Step 10 - Install cert-manager** to add automated TLS certificates
that ingress-nginx can serve over HTTPS.
