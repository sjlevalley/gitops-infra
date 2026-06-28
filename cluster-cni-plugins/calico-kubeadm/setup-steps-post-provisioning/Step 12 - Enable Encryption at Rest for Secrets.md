# Step 12 - Enable Encryption at Rest for Secrets (etcd)

**Prerequisites:**

- Steps **01–07** are complete (a working cluster).
- SSH access to the **control-plane (master)** node.
- A short maintenance window — the API server restarts (~30–60s of API
  downtime on this single-control-plane cluster).

> **Manual only.** Not in the Ansible playbook. These are control-plane host
> changes, performed with `sudo` on the master.

By default Kubernetes stores `Secret` objects in etcd **base64-encoded but not
encrypted** — anyone who can read the etcd data files or take an etcd snapshot
can read every secret in plaintext. "Encryption at rest" fixes this by telling
the **kube-apiserver** to encrypt resources (Secrets) with a key before writing
them to etcd, using an `EncryptionConfiguration`.

> **Two different layers — don't confuse them:**
> - **This step** encrypts Secrets *inside* etcd at the Kubernetes layer. This is
>   what protects an etcd snapshot/backup.
> - **EBS volume encryption** (the `encrypted: "true"` on the root volume and the
>   `ebs-gp3` StorageClass) encrypts the underlying *disk*. It protects against
>   stolen disks, not against someone reading the etcd contents.
>
> A hardened cluster wants **both**. This step adds the first.

---

## 1. Generate an encryption key

On the master:

```bash
# 32 random bytes, base64-encoded
ENC_KEY=$(head -c 32 /dev/urandom | base64)
echo "$ENC_KEY"
```

Keep this value — losing it means you cannot decrypt existing secrets after a
restore.

---

## 2. Write the EncryptionConfiguration

```bash
sudo mkdir -p /etc/kubernetes/enc

sudo tee /etc/kubernetes/enc/encryption-config.yaml >/dev/null <<EOF
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
    providers:
      - secretbox:
          keys:
            - name: key1
              secret: ${ENC_KEY}
      - identity: {}
EOF

sudo chmod 600 /etc/kubernetes/enc/encryption-config.yaml
```

> **Why this order:** the **first** provider (`secretbox`) encrypts all new
> writes. `identity` (plaintext) is listed **last** so the API server can still
> *read* secrets written before encryption was enabled. After the one-time
> re-encrypt in step 5, everything is encrypted, but keep `identity` last so old
> data stays readable during the transition.
>
> **Provider choice:** `secretbox` (XSalsa20-Poly1305) is a strong, simple option
> for a self-managed cluster. For real production, use **KMS v2** with an external
> key manager (e.g. AWS KMS) so the data-encryption key never lives on disk —
> that is what EKS does for you automatically.

---

## 3. Mount the config into the kube-apiserver static pod

The API server runs as a static pod from
`/etc/kubernetes/manifests/kube-apiserver.yaml`. **Back it up first** — a typo
here stops the API server from starting:

```bash
sudo cp /etc/kubernetes/manifests/kube-apiserver.yaml ~/kube-apiserver.yaml.bak
```

Edit `/etc/kubernetes/manifests/kube-apiserver.yaml` (`sudo vim ...`) and make
three additions:

**a) Add the flag** under `spec.containers[0].command:` (alongside the other
`--` flags):

```yaml
    - --encryption-provider-config=/etc/kubernetes/enc/encryption-config.yaml
```

**b) Add a volumeMount** under `spec.containers[0].volumeMounts:`:

```yaml
    - name: enc
      mountPath: /etc/kubernetes/enc
      readOnly: true
```

**c) Add a volume** under `spec.volumes:`:

```yaml
  - name: enc
    hostPath:
      path: /etc/kubernetes/enc
      type: DirectoryOrCreate
```

Save the file. The kubelet detects the change and restarts the API server
automatically within ~30 seconds.

---

## 4. Confirm the API server came back

```bash
# Wait for the API to respond again (may take ~30-60s)
until kubectl get --raw='/readyz' 2>/dev/null; do sleep 3; done; echo

kubectl get pods -n kube-system -l component=kube-apiserver
```

> **If the API server does NOT come back:** your edit is likely malformed.
> Restore the backup and let the kubelet restart it:
> ```bash
> sudo cp ~/kube-apiserver.yaml.bak /etc/kubernetes/manifests/kube-apiserver.yaml
> ```

---

## 5. Re-encrypt all existing secrets

New secrets are now encrypted, but secrets created *before* this change are still
plaintext in etcd. Rewrite every secret so the API server re-stores it encrypted:

```bash
kubectl get secrets --all-namespaces -o json | kubectl replace -f -
```

---

## 6. Verify the data in etcd is actually encrypted

Read a secret straight from etcd and check the stored bytes. Create a test secret
first:

```bash
kubectl create secret generic enc-test --from-literal=foo=bar

sudo ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  get /registry/secrets/default/enc-test | hexdump -C | head
```

You should see the value prefixed with **`k8s:enc:secretbox:v1:key1`** and the
secret contents as ciphertext — **not** the plaintext `bar`. Clean up:

```bash
kubectl delete secret enc-test
```

> `etcdctl` ships in the etcd static-pod image; if it's not on the host, install
> it (`sudo apt-get install -y etcd-client`) or run the command via
> `kubectl -n kube-system exec etcd-master -- etcdctl ...`.

---

## Key rotation (later)

To rotate: add a new key as the **first** entry under `secretbox.keys`, keep the
old key second, restart the API server, then re-run the re-encrypt in step 5, and
finally remove the old key. Always keep the currently-used key until everything is
re-encrypted.

---

## Multi–control-plane note

This cluster has a single control plane, so you edit one manifest. On an HA
cluster the **same `encryption-config.yaml` and the same key** must be present on
**every** control-plane node, and each API server manifest patched identically.

---

## Next

Continue to **Step 13 - Automated etcd Backups** — encryption protects the
*contents* of a backup; the next step makes sure you actually *have* backups.
