# Configure Kubernetes Gateway API with NGINX Gateway Fabric

## Task: Install and configure NGINX Gateway Fabric as a Gateway API implementation

### Scenario
You need to install NGINX Gateway Fabric as the Gateway controller, then configure a
GatewayClass, Gateway, and HTTPRoutes to route traffic to services in the cluster.
This cluster is self-managed on EC2 with no cloud load balancer, so the Gateway is
exposed via NodePort.

### Overview
The Gateway API is the modern replacement for Ingress. The stack has three layers:
- **GatewayClass** — names the controller that will implement Gateways
- **Gateway** — defines a listener (port/protocol) and binds to a GatewayClass
- **HTTPRoute** — attaches to a Gateway and defines routing rules to backend services

---

## Step 1: Install Gateway API CRDs

```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.1/standard-install.yaml

# Verify CRDs are installed
kubectl get crd | grep gateway.networking.k8s.io
```

Expected CRDs:
- `gatewayclasses.gateway.networking.k8s.io`
- `gateways.gateway.networking.k8s.io`
- `httproutes.gateway.networking.k8s.io`
- `referencegrants.gateway.networking.k8s.io`

---

## Step 2: Install NGINX Gateway Fabric via Helm

```bash
# Add the NGINX Gateway Fabric Helm repo
helm repo add nginx-gateway https://nginx.github.io/nginx-gateway-fabric
helm repo update

# Install NGINX Gateway Fabric into the nginx-gateway namespace
# --set service.type=NodePort because this cluster has no cloud load balancer
helm install ngf nginx-gateway/nginx-gateway-fabric \
  --namespace nginx-gateway \
  --create-namespace \
  --set service.type=NodePort

# Verify pods are running
kubectl get pods -n nginx-gateway
kubectl get svc -n nginx-gateway
```

Note the NodePort assigned to port 80 — you will use it to test routing:
```bash
kubectl get svc -n nginx-gateway ngf-nginx-gateway-fabric -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}'
```

---

## Step 3: Create a GatewayClass

```bash
kubectl apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: nginx
spec:
  controllerName: gateway.nginx.org/nginx-gateway-controller
EOF

# Verify GatewayClass is accepted
kubectl get gatewayclass nginx
kubectl describe gatewayclass nginx
```

Expected status: `Accepted: True`

---

## Step 4: Create a Gateway

```bash
kubectl apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: main-gateway
  namespace: default
spec:
  gatewayClassName: nginx
  listeners:
  - name: http
    port: 80
    protocol: HTTP
    allowedRoutes:
      namespaces:
        from: Same
EOF

# Verify Gateway is programmed
kubectl get gateway main-gateway
kubectl describe gateway main-gateway
```

Expected status: `Programmed: True`

---

## Step 5: Deploy test applications

```bash
# Deploy two apps to route between
kubectl create deployment web-app --image=nginx:stable --replicas=2
kubectl create deployment api-app --image=nginx:stable --replicas=2

# Expose them as ClusterIP services
kubectl expose deployment web-app --port=80
kubectl expose deployment api-app --port=80

kubectl get pods
kubectl get svc
```

---

## Step 6: Create HTTPRoutes

### Path-based routing
```bash
kubectl apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: web-route
  namespace: default
spec:
  parentRefs:
  - name: main-gateway
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: web-app
      port: 80
EOF

kubectl apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: api-route
  namespace: default
spec:
  parentRefs:
  - name: main-gateway
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /api
    backendRefs:
    - name: api-app
      port: 80
EOF

kubectl get httproute
kubectl describe httproute web-route
```

---

## Step 7: Test routing

```bash
# Get the NodePort for port 80
NODEPORT=$(kubectl get svc -n nginx-gateway ngf-nginx-gateway-fabric \
  -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}')

echo "NodePort: $NODEPORT"

# Test from the master node (use any node's IP)
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:$NODEPORT/
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:$NODEPORT/api
```

---

## Step 8: Advanced routing examples

### Traffic splitting (canary/blue-green)
```bash
kubectl apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: split-route
  namespace: default
spec:
  parentRefs:
  - name: main-gateway
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /split
    backendRefs:
    - name: web-app
      port: 80
      weight: 80
    - name: api-app
      port: 80
      weight: 20
EOF
```

### Header-based routing
```bash
kubectl apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: header-route
  namespace: default
spec:
  parentRefs:
  - name: main-gateway
  rules:
  - matches:
    - headers:
      - name: X-Version
        value: v2
    backendRefs:
    - name: api-app
      port: 80
  - backendRefs:
    - name: web-app
      port: 80
EOF

# Test header routing
curl -H "X-Version: v2" http://127.0.0.1:$NODEPORT/
```

### Request redirect
```bash
kubectl apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: redirect-route
  namespace: default
spec:
  parentRefs:
  - name: main-gateway
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /old
    filters:
    - type: RequestRedirect
      requestRedirect:
        path:
          type: ReplacePrefixMatch
          replacePrefixMatch: /new
        statusCode: 301
EOF

curl -I http://127.0.0.1:$NODEPORT/old
```

### Request header modification
```bash
kubectl apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: header-mod-route
  namespace: default
spec:
  parentRefs:
  - name: main-gateway
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /headers
    filters:
    - type: RequestHeaderModifier
      requestHeaderModifier:
        add:
        - name: X-Forwarded-By
          value: nginx-gateway
        remove:
        - X-Internal-Token
    backendRefs:
    - name: web-app
      port: 80
EOF
```

---

## Useful inspection commands

```bash
# Check all Gateway API resources at once
kubectl get gatewayclass,gateway,httproute

# Check NGINX Gateway Fabric logs
kubectl logs -n nginx-gateway -l app.kubernetes.io/name=nginx-gateway-fabric -c nginx-gateway

# Check nginx proxy logs
kubectl logs -n nginx-gateway -l app.kubernetes.io/name=nginx-gateway-fabric -c nginx

# Describe a route to see accepted/programmed status
kubectl describe httproute web-route
```

---

## Clean up

```bash
kubectl delete httproute --all
kubectl delete gateway main-gateway
kubectl delete gatewayclass nginx
kubectl delete deployment web-app api-app
kubectl delete service web-app api-app

helm uninstall ngf -n nginx-gateway
kubectl delete namespace nginx-gateway
kubectl delete -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.1/standard-install.yaml
```

---

## Expected Outcomes
- Gateway API CRDs installed and visible via `kubectl get crd`
- NGINX Gateway Fabric pods running in `nginx-gateway` namespace
- GatewayClass shows `Accepted: True`
- Gateway shows `Programmed: True`
- HTTPRoutes show `Accepted: True` and `Resolved: True`
- Traffic reaches correct backend based on path, headers, or weights
