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

data "aws_vpc" "default" {
  default = true
}

data "aws_subnet" "default" {
  vpc_id            = data.aws_vpc.default.id
  availability_zone = var.availability_zone
}

locals {
  key_pair_name = coalesce(var.key_pair_name, "${var.stack_identifier}-k8s-key")
}

resource "aws_security_group" "k8s_cluster" {
  name_prefix = "k8s-cluster-sg"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH access"
  }

  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Kubernetes API server"
  }

  ingress {
    from_port   = 2379
    to_port     = 2380
    protocol    = "tcp"
    self        = true
    description = "etcd server client API"
  }

  ingress {
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    self        = true
    description = "Kubelet API"
  }

  ingress {
    from_port   = 10259
    to_port     = 10259
    protocol    = "tcp"
    self        = true
    description = "kube-scheduler"
  }

  ingress {
    from_port   = 10257
    to_port     = 10257
    protocol    = "tcp"
    self        = true
    description = "kube-controller-manager"
  }

  ingress {
    from_port   = 10256
    to_port     = 10256
    protocol    = "tcp"
    self        = true
    description = "kube-proxy"
  }

  ingress {
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "NodePort Services"
  }

  # Flannel VXLAN
  ingress {
    from_port   = 8472
    to_port     = 8472
    protocol    = "udp"
    self        = true
    description = "VXLAN for Flannel CNI"
  }

  # Calico VXLAN / common overlays
  ingress {
    from_port   = 4789
    to_port     = 4789
    protocol    = "udp"
    self        = true
    description = "VXLAN for Calico CNI"
  }

  ingress {
    from_port   = 179
    to_port     = 179
    protocol    = "tcp"
    self        = true
    description = "BGP for Calico CNI"
  }

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "4"
    self        = true
    description = "IP-in-IP for Calico CNI"
  }

  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    self        = true
    description = "ICMP for diagnostics"
  }

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
    description = "All traffic between cluster nodes"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = {
    Name  = "k8s-cluster-sg"
    Stack = var.stack_identifier
  }
}

resource "tls_private_key" "k8s_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "k8s" {
  key_name   = local.key_pair_name
  public_key = tls_private_key.k8s_key.public_key_openssh
}

resource "local_file" "k8s_private_key" {
  content         = tls_private_key.k8s_key.private_key_pem
  filename        = "${var.artifacts_directory}/${var.private_key_filename}"
  file_permission = "0600"
}

resource "local_file" "k8s_public_key" {
  content         = tls_private_key.k8s_key.public_key_openssh
  filename        = "${var.artifacts_directory}/${var.public_key_filename}"
  file_permission = "0644"
}

resource "aws_instance" "server" {
  ami           = data.aws_ami.debian.id
  instance_type = var.control_plane_instance_type
  subnet_id     = data.aws_subnet.default.id

  vpc_security_group_ids = [aws_security_group.k8s_cluster.id]
  key_name               = aws_key_pair.k8s.key_name

  associate_public_ip_address = true

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
  }

  user_data = <<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get install -y curl wget vim
              EOF

  tags = {
    Name  = "server"
    Role  = "kubernetes-control-plane"
    Stack = var.stack_identifier
  }
}

resource "aws_instance" "node_0" {
  ami           = data.aws_ami.debian.id
  instance_type = var.worker_instance_type
  subnet_id     = data.aws_subnet.default.id

  vpc_security_group_ids = [aws_security_group.k8s_cluster.id]
  key_name               = aws_key_pair.k8s.key_name

  associate_public_ip_address = true

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
  }

  user_data = <<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get install -y curl wget vim
              EOF

  tags = {
    Name  = "node-0"
    Role  = "kubernetes-worker"
    Stack = var.stack_identifier
  }
}

resource "aws_instance" "node_1" {
  ami           = data.aws_ami.debian.id
  instance_type = var.worker_instance_type
  subnet_id     = data.aws_subnet.default.id

  vpc_security_group_ids = [aws_security_group.k8s_cluster.id]
  key_name               = aws_key_pair.k8s.key_name

  associate_public_ip_address = true

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
  }

  user_data = <<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get install -y curl wget vim
              EOF

  tags = {
    Name  = "node-1"
    Role  = "kubernetes-worker"
    Stack = var.stack_identifier
  }
}

resource "local_file" "machines_txt" {
  filename = "${var.artifacts_directory}/${var.machines_txt_filename}"
  content = templatefile("${path.module}/machines.txt.tpl", {
    server_private_ip = aws_instance.server.private_ip
    node_0_private_ip = aws_instance.node_0.private_ip
    node_1_private_ip = aws_instance.node_1.private_ip
    server_public_ip  = aws_instance.server.public_ip
    node_0_public_ip  = aws_instance.node_0.public_ip
    node_1_public_ip  = aws_instance.node_1.public_ip
    key_filename      = var.private_key_filename
    pod_subnets       = var.pod_subnets
  })
}
