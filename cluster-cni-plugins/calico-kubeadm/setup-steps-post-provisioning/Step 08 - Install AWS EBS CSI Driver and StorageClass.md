# Step 08 - Install AWS EBS CSI Driver and StorageClass

**Prerequisites:**

- Steps **01–07** are complete (cluster, Calico, Helm).
- SSH access to the master node.
- An AWS IAM user (or role) whose credentials the driver can use — see **IAM prerequisite** below.

> **Manual only.** Unlike Steps 05–07, this addon is **not** in the Ansible
> playbook yet. These are the manual steps to practice installing it.

The cluster currently has **no StorageClass**, so every `PersistentVolumeClaim`
stays `Pending` and stateful addons (Prometheus, Grafana, Loki) fall back to
`emptyDir` — data is lost on pod restart (see the note in Step 05). The AWS EBS
CSI driver lets Kubernetes dynamically provision EBS volumes as PVs.

---

## IAM prerequisite (important on this cluster)

The EBS CSI driver needs AWS credentials to create/attach volumes. On a managed
cluster (EKS) it would use IRSA; on this self-managed kubeadm cluster it uses the
node instance profile instead. You have two options.

### Option B — Node instance profile via Terraform (recommended, already wired)

The calico stack sets `enable_ebs_csi_iam = true`
(`cluster-cni-plugins/calico-kubeadm/terraform/main.tf`), which makes the module
attach an IAM role granting the AWS-managed `AmazonEBSCSIDriverPolicy` to **all**
nodes. With this in place the driver picks up credentials from instance metadata
automatically — **no secret is required**, so you can skip straight to
**Install the driver** below.

> If you provisioned the cluster *before* this was added, re-apply Terraform so
> the instance profile is attached:
> ```bash
> terraform -chdir=cluster-cni-plugins/calico-kubeadm/terraform apply
> ```
> Attaching an instance profile to a running instance does not require a replace.

Use **Option A** only if you deliberately set `enable_ebs_csi_iam = false`.

### Option A — Static IAM user credentials (alternative, no instance profile)

1. In the AWS console, create an IAM user (programmatic access) and attach the
   AWS-managed policy **`AmazonEBSCSIDriverPolicy`**
   (`arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy`).
2. Note the **Access Key ID** and **Secret Access Key**.
3. Create the secret the chart expects (run on the master). The chart reads a
   secret named `aws-secret` with keys `key_id` / `access_key` by default:

   ```bash
   kubectl create secret generic aws-secret \
     --namespace kube-system \
     --from-literal "key_id=${AWS_ACCESS_KEY_ID}" \
     --from-literal "access_key=${AWS_SECRET_ACCESS_KEY}"
   ```

> Treat these keys like any credential — do not commit them. Delete the IAM user
> when you tear the cluster down.

---

## Install the driver

SSH into the master and run:

```bash
helm repo add aws-ebs-csi-driver https://kubernetes-sigs.github.io/aws-ebs-csi-driver
helm repo update

helm install aws-ebs-csi-driver aws-ebs-csi-driver/aws-ebs-csi-driver \
  --namespace kube-system
```

With **Option B** (instance profile) the controller obtains credentials from
instance metadata — nothing extra to configure. With **Option A** it picks up the
`aws-secret` automatically. Confirm the controller and node pods are running:

```bash
kubectl get pods -n kube-system -l "app.kubernetes.io/name=aws-ebs-csi-driver"
```

You should see `ebs-csi-controller-*` (on the control plane) and an
`ebs-csi-node-*` pod on every node.

---

## Create a default StorageClass

The driver does not create a StorageClass for you. Apply a `gp3` class and mark
it default so PVCs without an explicit class use it:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ebs-gp3
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.aws.com
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
parameters:
  type: gp3
  encrypted: "true"
EOF

kubectl get storageclass
```

> **Why `WaitForFirstConsumer`:** an EBS volume lives in one Availability Zone
> and can only attach to a node in that same AZ. This binding mode delays volume
> creation until a pod is scheduled, so the volume is created in the right AZ.
> The driver derives the node's AZ from instance metadata (IMDS).

---

## Verify with a test PVC + pod

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ebs-test-claim
spec:
  accessModes: ["ReadWriteOnce"]
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: ebs-test-pod
spec:
  containers:
    - name: app
      image: public.ecr.aws/docker/library/busybox:latest
      command: ["sh", "-c", "echo hello > /data/test && sleep 3600"]
      volumeMounts:
        - name: vol
          mountPath: /data
  volumes:
    - name: vol
      persistentVolumeClaim:
        claimName: ebs-test-claim
EOF

# The PVC should move Pending -> Bound once the pod schedules
kubectl get pvc ebs-test-claim -w
```

Once `Bound`, confirm the file persists and clean up:

```bash
kubectl exec ebs-test-pod -- cat /data/test     # -> hello
kubectl delete pod ebs-test-pod
kubectl delete pvc ebs-test-claim
```

---

## Using it for the monitoring stack (optional)

With a default StorageClass in place you can re-enable persistence in
`gitops-infra/cluster-addons/monitoring/values.yaml` (Prometheus/Grafana
`persistence.enabled: true`, `storageClassName: ebs-gp3`) and `helm upgrade` the
release so metrics survive pod restarts.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| PVC stuck `Pending`, event `failed to provision volume ... NoCredentialProviders` | `aws-secret` missing or wrong keys | Recreate the secret with keys `key_id` / `access_key` in `kube-system` |
| PVC `Pending`, event `UnauthorizedOperation` | IAM user lacks EBS permissions | Attach `AmazonEBSCSIDriverPolicy` to the user |
| `ebs-csi-controller` `CrashLoopBackOff` | Bad credentials | Check `kubectl logs -n kube-system deploy/ebs-csi-controller -c csi-provisioner` |
| Volume created in wrong AZ / won't attach | StorageClass used `Immediate` binding | Use `WaitForFirstConsumer` (as above) |

---

## Uninstall

```bash
# Delete any PVCs using the class first, then:
kubectl delete storageclass ebs-gp3
helm uninstall aws-ebs-csi-driver -n kube-system
kubectl delete secret aws-secret -n kube-system   # Option A only
```

---

## Next

Continue to **Step 09 - Install Ingress-NGINX Controller** to replace raw
NodePorts with proper HTTP routing.
