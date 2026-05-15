**Provisioning Compute Resources**

Kubernetes requires a set of machines to host the Kubernetes control plane and the worker nodes where containers are ultimately run. In this lab you will provision the machines required for setting up a Kubernetes cluster.

**Machine Database**

This tutorial will leverage a text file, which will serve as a machine database, to store the various machine attributes that will be used when setting up the Kubernetes control plane and worker nodes. The following schema represents entries in the machine database, one entry per line:

`IPV4_ADDRESS FQDN HOSTNAME POD_SUBNET`

Each of the columns corresponds to a machine IP address IPV4_ADDRESS, fully qualified domain name FQDN, host name HOSTNAME, and the IP subnet POD_SUBNET. Kubernetes assigns one IP address per pod and the POD_SUBNET represents the unique IP address range assigned to each machine in the cluster for doing so.

Here is an example machine database similar to the one used when creating this tutorial. Notice the IP addresses have been masked out. Your machines can be assigned any IP address as long as each machine is reachable from each other and the jumpbox.

1. `cat machines.txt`

```
XXX.XXX.XXX.XXX server.kubernetes.local server
XXX.XXX.XXX.XXX node-0.kubernetes.local node-0 10.244.0.0/24
XXX.XXX.XXX.XXX node-1.kubernetes.local node-1 10.244.1.0/24
```

Now it's your turn to create a machines.txt file with the details for the three machines you will be using to create your Kubernetes cluster. Use the example machine database from above and add the details for your machines.

**Section Not needed as we copy keys to jumpbox in Step 02

<!-- **Configuring SSH Access**

SSH will be used to configure the machines in the cluster. We'll use the admin user for all SSH operations, which is the default user on AWS EC2 instances.

**SSH Access Setup**

SSH will be used to configure the machines in the cluster. We'll use the admin user for all SSH operations, which is the default user on AWS EC2 instances.

**Generate and Distribute SSH Keys**

In this section you will generate and distribute an SSH keypair to the server, node-0, and node-1, machines, which will be used to run commands on those machines throughout this tutorial. Run the following commands from the jumpbox machine.

Generate a new SSH key:

2. `ssh-keygen`

```
Generating public/private rsa key pair.
Enter file in which to save the key (/home/admin/.ssh/id_rsa):
Enter passphrase (empty for no passphrase):
Enter same passphrase again:
Your identification has been saved in /home/admin/.ssh/id_rsa
Your public key has been saved in /home/admin/.ssh/id_rsa.pub
```

Copy the SSH public key to each machine:

3. Copy SSH keys to admin user first, then set up root access:

   # Copy key to admin user

   {
   while read IP FQDN HOST SUBNET; do
   ssh-copy-id admin@${IP}
   done < machines.txt
   }

   # Copy admin's key to root and enable root SSH

   {
   while read IP FQDN HOST SUBNET; do
   ssh admin@${IP} "sudo cp -r /home/admin/.ssh /root/ && sudo chown -R root:root /root/.ssh && sudo chmod 700 /root/.ssh && sudo chmod 600 /root/.ssh/authorized_keys"
   done < machines.txt
   }

Once each key is added, verify SSH public key access is working:

4.  {
    while read IP FQDN HOST SUBNET; do
    ssh -n admin@${IP} hostname
    done < machines.txt
    } -->

**Hostnames**

In this section you will assign hostnames to the server, node-0, and node-1 machines. The hostname will be used when executing commands from the jumpbox to each machine. The hostname also plays a major role within the cluster. Instead of Kubernetes clients using an IP address to issue commands to the Kubernetes API server, those clients will use the server hostname instead. Hostnames are also used by each worker machine, node-0 and node-1 when registering with a given Kubernetes cluster.

To configure the hostname for each machine, run the following commands on the jumpbox.

Set the hostname on each machine listed in the machines.txt file:

5.  {
    while read IP FQDN HOST SUBNET; do
    CMD="sudo sed -i 's/^127.0.1.1.\*/127.0.1.1\t${FQDN} ${HOST}/' /etc/hosts"
    ssh -n admin@${IP} "$CMD"
    ssh -n admin@${IP} "sudo hostnamectl set-hostname ${FQDN}"
    ssh -n admin@${IP} "sudo systemctl restart systemd-hostnamed"
    done < machines.txt
    }

Verify the hostname is set on each machine:

6.  {
    while read IP FQDN HOST SUBNET; do
    ssh -n admin@${IP} "hostname --fqdn"
    done < machines.txt
    }

```
server.kubernetes.local
node-0.kubernetes.local
node-1.kubernetes.local
```

**Host Lookup Table**

In this section you will generate a hosts file which will be appended to /etc/hosts file on the jumpbox and to the /etc/hosts files on all three cluster members used for this tutorial. This will allow each machine to be reachable using a hostname such as server, node-0, or node-1.

Create a new hosts file and add a header to identify the machines being added:

7. `echo "" > hosts && echo "# Kubernetes The Hard Way" >> hosts`
   

Generate a host entry for each machine in the machines.txt file and append it to the hosts file:

8. {
   while read IP FQDN HOST SUBNET; do
   ENTRY="${IP} ${FQDN} ${HOST}"
   echo $ENTRY >> hosts
   done < machines.txt
   }

Review the host entries in the hosts file:

9. `cat hosts`

```
# Kubernetes The Hard Way
XXX.XXX.XXX.XXX server.kubernetes.local server
XXX.XXX.XXX.XXX node-0.kubernetes.local node-0
XXX.XXX.XXX.XXX node-1.kubernetes.local node-1
```

**Adding /etc/hosts Entries To A Local Machine**

In this section you will append the DNS entries from the hosts file to the local /etc/hosts file on your jumpbox machine.

Append the DNS entries from hosts to /etc/hosts:

10. `sudo sh -c "cat hosts >> /etc/hosts"`

Verify that the /etc/hosts file has been updated:

11. `cat /etc/hosts`

```
127.0.0.1       localhost
127.0.1.1       jumpbox

# The following lines are desirable for IPv6 capable hosts
::1     localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters

# Kubernetes The Hard Way
XXX.XXX.XXX.XXX server.kubernetes.local server
XXX.XXX.XXX.XXX node-0.kubernetes.local node-0
XXX.XXX.XXX.XXX node-1.kubernetes.local node-1
```

At this point you should be able to SSH to each machine listed in the machines.txt file using a hostname.

12. {
    for host in server node-0 node-1
    do ssh admin@${host} hostname
    done
    }

```
server.kubernetes.local
node-0.kubernetes.local
node-1.kubernetes.local
```

**Adding /etc/hosts Entries To The Remote Machines**

In this section you will append the host entries from hosts to /etc/hosts on each machine listed in the machines.txt text file.

Copy the hosts file to each machine and append the contents to /etc/hosts:

13. {
    while read IP FQDN HOST SUBNET; do
    scp hosts admin@${HOST}:~/
    ssh -n admin@${HOST} "sudo sh -c \"cat hosts >> /etc/hosts\""
    done < machines.txt
    }

** TODO: This does not yet work
At this point, hostnames can be used when connecting to machines from your jumpbox machine, or any of the three machines in the Kubernetes cluster. Instead of using IP addresses you can now connect to machines using a hostname such as server, node-0, or node-1.

This is one of the steps in Kelsey Hightower's 'Kubernetes the hard way' github repo, which I am attempting to set up on AWS EC2 instances
