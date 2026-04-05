[all]
server ansible_host={{ server_public_ip }} ansible_user=admin ansible_ssh_private_key_file={{ ssh_key_path }}
node0 ansible_host={{ node0_public_ip }} ansible_user=admin ansible_ssh_private_key_file={{ ssh_key_path }}
node1 ansible_host={{ node1_public_ip }} ansible_user=admin ansible_ssh_private_key_file={{ ssh_key_path }}

[master]
server

[workers]
node0
node1

[all:vars]
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
ansible_python_interpreter=/usr/bin/python3
