**Initial Setup of Jumpbox**

In this lab you will set up one of the four machines to be a jumpbox. This machine will be used to run commands throughout this tutorial. While a dedicated machine is being used to ensure consistency, these commands can also be run from just about any machine including your personal workstation running macOS or Linux.

Think of the jumpbox as the administration machine that you will use as a home base when setting up your Kubernetes cluster from the ground up. Before we get started we need to install a few command line utilities and clone the Kubernetes The Hard Way git repository, which contains some additional configuration files that will be used to configure various Kubernetes components throughout this tutorial.

1. Log into Jumpbox

- `ssh -i "k8s-key.pem" admin@<JUMPBOX_IP>`

---

All commands will be run as the admin user. This is being done for the sake of convenience, and will help reduce the number of commands required to set everything up.

**Install Command Line Utilities**

2. Update the Server
   {
   sudo apt-get update && sudo apt-get -y install wget curl vim openssl git
   }

---

3. Clone the Git Repo

- `git clone --depth 1 https://github.com/kelseyhightower/kubernetes-the-hard-way.git`

---

4. CD into the repo directory

- `cd kubernetes-the-hard-way`

---

5. Confirm that you are in the correct directory

- `pwd`

- Output should be '/home/admin/kubernetes-the-hard-way'

---

**Download Binaries**

In this section you will download the binaries for the various Kubernetes components. The binaries will be stored in the downloads directory on the jumpbox, which will reduce the amount of internet bandwidth required to complete this tutorial as we avoid downloading the binaries multiple times for each machine in our Kubernetes cluster.

The binaries that will be downloaded are listed in either the downloads-amd64.txt or downloads-arm64.txt file depending on your hardware architecture, which you can review using the cat command:

6. `cat downloads-$(dpkg --print-architecture).txt`

---

7. Download the binaries into a directory called downloads using the wget command:

`wget -q --show-progress --https-only --timestamping -P downloads -i downloads-$(dpkg --print-architecture).txt`

Depending on your internet connection speed it may take a while to download over 500 megabytes of binaries, and once the download is complete, you can list them using the ls command:

`ls -oh downloads`

8. Extract the component binaries from the release archives and organize them under the downloads directory.

{
ARCH=$(dpkg --print-architecture)
  mkdir -p downloads/{client,cni-plugins,controller,worker}
  tar -xvf downloads/crictl-v1.32.0-linux-${ARCH}.tar.gz \
 -C downloads/worker/
tar -xvf downloads/containerd-2.1.0-beta.0-linux-${ARCH}.tar.gz \
    --strip-components 1 \
    -C downloads/worker/
  tar -xvf downloads/cni-plugins-linux-${ARCH}-v1.6.2.tgz \
 -C downloads/cni-plugins/
tar -xvf downloads/etcd-v3.6.0-rc.3-linux-${ARCH}.tar.gz \
    -C downloads/ \
    --strip-components 1 \
    etcd-v3.6.0-rc.3-linux-${ARCH}/etcdctl \
 etcd-v3.6.0-rc.3-linux-${ARCH}/etcd
  mv downloads/{etcdctl,kubectl} downloads/client/
  mv downloads/{etcd,kube-apiserver,kube-controller-manager,kube-scheduler} \
    downloads/controller/
  mv downloads/{kubelet,kube-proxy} downloads/worker/
  mv downloads/runc.${ARCH} downloads/worker/runc
}

`rm -rf downloads/*gz`

9. Make the binaries executable.

`chmod +x downloads/{client,cni-plugins,controller,worker}/*`

**Install kubectl**

In this section you will install the kubectl, the official Kubernetes client command line tool, on the jumpbox machine. kubectl will be used to interact with the Kubernetes control plane once your cluster is provisioned later in this tutorial.

10. Use the chmod command to make the `kubectl` binary executable and move it to the `/usr/local/bin/` directory:

`sudo cp downloads/client/kubectl /usr/local/bin/`

At this point `kubectl` is installed and can be verified by running the `kubectl` command:

`kubectl version --client`

The output should look like this

Client Version: v1.32.3
Kustomize Version: v5.5.0

At this point the `jumpbox` has been set up with all the command line tools and utilities necessary to complete the labs in this tutorial.

**Copy Existing SSH Keypair**

Since you already have the `k8s-key.pem` and `k8s-key.pub` files from your Terraform script, copy them to the jumpbox for use in the next steps:

11. Copy the key files to your jumpbox:

    ```bash
    # From your local machine, copy the key files to the jumpbox
    scp -i "k8s-key.pem" k8s-key.pem admin@{IP}:~/
    scp -i "k8s-key.pem" k8s-key.pub admin@{IP}:~/
    ```

12. SSH into your jumpbox and set up the keys:

    ```bash
    ssh -i "k8s-key.pem" admin@{IP}

    # Create .ssh directory if it doesn't exist
    mkdir -p ~/.ssh

    # Copy the keys to the correct location
    cp k8s-key.pem ~/.ssh/id_rsa && cp k8s-key.pub ~/.ssh/id_rsa.pub

    # Set proper permissions
    chmod 700 ~/.ssh && chmod 400 ~/.ssh/id_rsa && chmod 644 ~/.ssh/id_rsa.pub

    # Also fix permissions on the original key files (AWS recommends chmod 400)
    chmod 400 k8s-key.pem && chmod 644 k8s-key.pub
    ```

13. Test the key setup:
    ```bash
    # Test that the key works
    ssh-keygen -y -f ~/.ssh/id_rsa
    ```

<!-- Provisioning Compute Resources -->


