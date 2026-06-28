# Step 13 - Automated etcd Backups (CronJob)

**Prerequisites:**

- Steps **01–07** are complete (a working cluster).
- **Step 08** (EBS CSI + a default StorageClass) — snapshots are stored on a
  PersistentVolume.
- SSH/`kubectl` access to the cluster.

> **Manual only.** Not in the Ansible playbook.

etcd is the **entire state of your cluster** — every object, secret, and config.
On this single-control-plane cluster there is exactly one etcd member and **no
backups**: if that node's disk is lost, the cluster is unrecoverable. This step
adds a scheduled `etcdctl snapshot save` so you always have a recent point-in-time
backup to restore from.

We run it as a Kubernetes **CronJob** pinned to the control-plane node, talking
directly to the local etcd over its client certs, and writing snapshots to an EBS
volume.

---

## 1. Find the etcd image version

The backup pod must use an `etcdctl` matching the running etcd. Get the image:

```bash
kubectl -n kube-system get pod -l component=etcd \
  -o jsonpath='{.items[0].spec.containers[0].image}'; echo
# e.g. registry.k8s.io/etcd:3.5.15-0
```

Use that exact image in the manifest below (replace `ETCD_IMAGE`).

---

## 2. Create the namespace and a PVC for snapshots

```bash
kubectl create namespace etcd-backup

cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: etcd-backups
  namespace: etcd-backup
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: ebs-gp3
  resources:
    requests:
      storage: 5Gi
EOF
```

---

## 3. Create the backup CronJob

Replace `ETCD_IMAGE` with the value from step 1, then apply:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: batch/v1
kind: CronJob
metadata:
  name: etcd-backup
  namespace: etcd-backup
spec:
  schedule: "0 */6 * * *"        # every 6 hours
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      backoffLimit: 2
      template:
        spec:
          restartPolicy: OnFailure
          hostNetwork: true       # reach etcd on 127.0.0.1:2379
          nodeSelector:
            node-role.kubernetes.io/control-plane: ""
          tolerations:
            - key: node-role.kubernetes.io/control-plane
              operator: Exists
              effect: NoSchedule
          containers:
            - name: etcd-backup
              image: ETCD_IMAGE
              command:
                - /bin/sh
                - -c
                - |
                  set -e
                  SNAP="/backup/etcd-snapshot-$(date +%Y%m%d-%H%M%S).db"
                  echo "Saving snapshot to $SNAP"
                  etcdctl snapshot save "$SNAP"
                  etcdctl snapshot status "$SNAP" -w table || true
                  echo "Pruning old snapshots (keep 14 most recent)"
                  ls -1t /backup/etcd-snapshot-*.db | tail -n +15 | xargs -r rm -f
                  ls -lh /backup
              env:
                - name: ETCDCTL_API
                  value: "3"
                - name: ETCDCTL_ENDPOINTS
                  value: "https://127.0.0.1:2379"
                - name: ETCDCTL_CACERT
                  value: "/etc/kubernetes/pki/etcd/ca.crt"
                - name: ETCDCTL_CERT
                  value: "/etc/kubernetes/pki/etcd/server.crt"
                - name: ETCDCTL_KEY
                  value: "/etc/kubernetes/pki/etcd/server.key"
              volumeMounts:
                - name: etcd-certs
                  mountPath: /etc/kubernetes/pki/etcd
                  readOnly: true
                - name: backup
                  mountPath: /backup
          volumes:
            - name: etcd-certs
              hostPath:
                path: /etc/kubernetes/pki/etcd
                type: Directory
            - name: backup
              persistentVolumeClaim:
                claimName: etcd-backups
EOF
```

> **How it works:** `hostNetwork: true` lets the pod reach the etcd client port on
> `127.0.0.1:2379`. The `nodeSelector` + `toleration` pin it to the control-plane
> node (where etcd and its certs live). The certs are mounted read-only via
> `hostPath`. It talks straight to etcd, so it needs **no Kubernetes RBAC**.

---

## 4. Test it now (don't wait 6 hours)

Trigger a one-off run from the CronJob:

```bash
kubectl -n etcd-backup create job --from=cronjob/etcd-backup etcd-backup-manual

kubectl -n etcd-backup get pods -w        # wait for Completed
kubectl -n etcd-backup logs job/etcd-backup-manual
```

You should see `Snapshot saved` and a status table with a hash and revision.
Confirm the file landed on the volume:

```bash
kubectl -n etcd-backup run snap-ls --rm -it --restart=Never \
  --image=busybox --overrides='
{"spec":{"containers":[{"name":"snap-ls","image":"busybox","command":["ls","-lh","/backup"],
"volumeMounts":[{"name":"b","mountPath":"/backup"}]}],
"volumes":[{"name":"b","persistentVolumeClaim":{"claimName":"etcd-backups"}}]}}'
```

Clean up the manual job:

```bash
kubectl -n etcd-backup delete job etcd-backup-manual
```

---

## 5. Restore drill (know this BEFORE you need it)

A backup you've never restored is a hope, not a backup. Outline for this
single-control-plane cluster (run on the master, **cluster will be briefly down**):

```bash
# 1. Copy a snapshot off the PVC to the host, e.g. /root/snapshot.db

# 2. Stop the control-plane static pods by moving the manifests aside
sudo mkdir -p /etc/kubernetes/manifests.bak
sudo mv /etc/kubernetes/manifests/*.yaml /etc/kubernetes/manifests.bak/

# 3. Restore the snapshot into a fresh data dir
sudo ETCDCTL_API=3 etcdctl snapshot restore /root/snapshot.db \
  --data-dir=/var/lib/etcd-restore

# 4. Point etcd at the restored data dir: edit the etcd manifest's hostPath
#    volume for /var/lib/etcd to /var/lib/etcd-restore (or swap the directories)

# 5. Move the manifests back so the kubelet restarts the control plane
sudo mv /etc/kubernetes/manifests.bak/*.yaml /etc/kubernetes/manifests/

# 6. Verify
until kubectl get --raw=/readyz 2>/dev/null; do sleep 3; done; echo
kubectl get nodes
```

> Practice this on a throwaway cluster at least once. The exact data-dir swap
> depends on your etcd manifest's `hostPath`; check
> `/etc/kubernetes/manifests/etcd.yaml` before doing it for real.

---

## 6. Get snapshots OFF the cluster (important for real DR)

The PVC is a **single EBS volume in one AZ/account**. It protects against a node
disk failure, but **not** against losing the AWS account, region, or accidental
deletion. For genuine disaster recovery, ship snapshots off-cluster. Options:

- Add an `aws s3 cp /backup/<snap>.db s3://<bucket>/etcd/` step to the CronJob
  command (the nodes already have an instance profile from Step 08 — extend its
  IAM policy with `s3:PutObject` to that bucket).
- Or take **EBS volume snapshots** of the backup PVC on a schedule.
- Or adopt **Velero**, which backs up cluster resources *and* PV data to S3 with
  scheduling and restore built in — the more complete production answer.

---

## Tuning

| Setting | Default here | Notes |
|---------|--------------|-------|
| `schedule` | every 6h | Tighten to hourly for lower RPO |
| retention | keep 14 | Adjust the `tail -n +15` in the command |
| PVC size | 5Gi | Each snapshot ≈ your etcd DB size (tens of MB on a small cluster) |

---

## GitOps note

This CronJob + PVC is plain YAML — commit it to the `gitops-kubernetes` repo and
let Argo CD (Step 07) manage it, so backups are reconciled like everything else.

---

## Next

With encryption at rest (Step 12) and automated, restorable backups (Step 13), the
two biggest etcd risks are covered. The remaining production gaps — **HA control
plane** and **multi-AZ** — require provisioning changes rather than addons (see
`docs/briefs/`).

Continue to **Step 14 - Deploy an Application** to run a workload on the finished
cluster.
