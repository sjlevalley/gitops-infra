# Configure the AWS Provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.0"
}

provider "aws" {
  region = "us-east-1"  # Free tier is available in us-east-1
}

# Data source to get the latest Debian 12 (bookworm) AMI
data "aws_ami" "debian" {
  most_recent = true
  owners      = ["136693071363"] # Debian Cloud Team

  filter {
    name   = "name"
    values = ["debian-12-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# Data source to get the default VPC
data "aws_vpc" "default" {
  default = true
}

# Data source to get the default subnet
data "aws_subnet" "default" {
  vpc_id            = data.aws_vpc.default.id
  availability_zone = "us-east-1a"
}

# Create a security group for Kubernetes cluster
resource "aws_security_group" "k8s_cluster" {
  name_prefix = "k8s-cluster-sg"
  vpc_id      = data.aws_vpc.default.id

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH access"
  }

  # Kubernetes API server
  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Kubernetes API server"
  }

  # etcd server client API
  ingress {
    from_port   = 2379
    to_port     = 2380
    protocol    = "tcp"
    self        = true
    description = "etcd server client API"
  }

  # Kubelet API
  ingress {
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    self        = true
    description = "Kubelet API"
  }

  # kube-scheduler
  ingress {
    from_port   = 10259
    to_port     = 10259
    protocol    = "tcp"
    self        = true
    description = "kube-scheduler"
  }

  # kube-controller-manager
  ingress {
    from_port   = 10257
    to_port     = 10257
    protocol    = "tcp"
    self        = true
    description = "kube-controller-manager"
  }

  # kube-proxy
  ingress {
    from_port   = 10256
    to_port     = 10256
    protocol    = "tcp"
    self        = true
    description = "kube-proxy"
  }

  # NodePort services
  ingress {
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "NodePort Services"
  }

  # All outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = {
    Name = "k8s-cluster-sg"
  }
}

# Generate SSH key pair
resource "tls_private_key" "k8s_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Create a key pair for SSH access
resource "aws_key_pair" "k8s-key" {
  key_name   = "k8s-key"
  public_key = tls_private_key.k8s_key.public_key_openssh
}

# Save the private key to a file
resource "local_file" "k8s_private_key" {
  content  = tls_private_key.k8s_key.private_key_pem
  filename = "${path.module}/k8s-key.pem"
  file_permission = "0600"
}

# Save the public key to a file (optional)
resource "local_file" "k8s_public_key" {
  content  = tls_private_key.k8s_key.public_key_openssh
  filename = "${path.module}/k8s-key.pub"
  file_permission = "0644"
}

# Jumpbox - Administration host (1 vCPU, 512MB RAM, 10GB storage)
resource "aws_instance" "jumpbox" {
  ami           = data.aws_ami.debian.id
  instance_type = "t3.micro"  # 1 vCPU, 1GB RAM (closest to 512MB requirement)
  subnet_id     = data.aws_subnet.default.id

  vpc_security_group_ids = [aws_security_group.k8s_cluster.id]
  key_name               = aws_key_pair.k8s-key.key_name

  associate_public_ip_address = true

  root_block_device {
    volume_size = 10  # 10GB storage requirement
    volume_type = "gp3"
  }

  user_data = <<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get install -y curl wget vim
              EOF

  tags = {
    Name = "jumpbox"
    Role = "administration"
  }
}

# Server - Kubernetes control plane (1 vCPU, 2GB RAM, 20GB storage)
resource "aws_instance" "server" {
  ami           = data.aws_ami.debian.id
  instance_type = "t3.small"  # 1 vCPU, 2GB RAM
  subnet_id     = data.aws_subnet.default.id

  vpc_security_group_ids = [aws_security_group.k8s_cluster.id]
  key_name               = aws_key_pair.k8s-key.key_name

  associate_public_ip_address = true

  root_block_device {
    volume_size = 20  # 20GB storage requirement
    volume_type = "gp3"
  }

  user_data = <<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get install -y curl wget vim
              EOF

  tags = {
    Name = "server"
    Role = "kubernetes-control-plane"
  }
}

# Node-0 - Kubernetes worker node (1 vCPU, 2GB RAM, 20GB storage)
resource "aws_instance" "node_0" {
  ami           = data.aws_ami.debian.id
  instance_type = "t3.small"  # 1 vCPU, 2GB RAM
  subnet_id     = data.aws_subnet.default.id

  vpc_security_group_ids = [aws_security_group.k8s_cluster.id]
  key_name               = aws_key_pair.k8s-key.key_name

  associate_public_ip_address = true

  root_block_device {
    volume_size = 20  # 20GB storage requirement
    volume_type = "gp3"
  }

  user_data = <<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get install -y curl wget vim
              EOF

  tags = {
    Name = "node-0"
    Role = "kubernetes-worker"
  }
}

# Node-1 - Kubernetes worker node (1 vCPU, 2GB RAM, 20GB storage)
resource "aws_instance" "node_1" {
  ami           = data.aws_ami.debian.id
  instance_type = "t3.small"  # 1 vCPU, 2GB RAM
  subnet_id     = data.aws_subnet.default.id

  vpc_security_group_ids = [aws_security_group.k8s_cluster.id]
  key_name               = aws_key_pair.k8s-key.key_name

  associate_public_ip_address = true

  root_block_device {
    volume_size = 20  # 20GB storage requirement
    volume_type = "gp3"
  }

  user_data = <<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get install -y curl wget vim
              EOF

  tags = {
    Name = "node-1"
    Role = "kubernetes-worker"
  }
}




# Generate machines.txt file for Kubernetes "the hard way" tutorial
resource "local_file" "machines_txt" {
  filename = "${path.module}/machines.txt"
  content = templatefile("${path.module}/machines.txt.tpl", {
    server_private_ip = aws_instance.server.private_ip
    node_0_private_ip = aws_instance.node_0.private_ip
    node_1_private_ip = aws_instance.node_1.private_ip
    jumpbox_public_ip = aws_instance.jumpbox.public_ip
    server_public_ip  = aws_instance.server.public_ip
    node_0_public_ip  = aws_instance.node_0.public_ip
    node_1_public_ip  = aws_instance.node_1.public_ip
    pod_subnets       = var.pod_subnets
  })
}


