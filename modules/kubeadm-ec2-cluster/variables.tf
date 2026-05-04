variable "stack_identifier" {
  description = "Unique label for this deployment (instance tagging, machines.txt context). Use one value per stack (e.g. kubeadm-flannel, kubeadm-calico)."
  type        = string
}

variable "key_pair_name" {
  description = "AWS EC2 key pair name. If null, uses stack_identifier with suffix -k8s-key. Set explicitly when migrating old state that used the fixed name k8s-key."
  type        = string
  default     = null
}

variable "pod_subnets" {
  description = "Pod subnets per worker hostname key (used in machines.txt)"
  type        = map(string)
  default = {
    node-0 = "10.244.0.0/24"
    node-1 = "10.244.1.0/24"
  }
}

variable "availability_zone" {
  description = "AZ for the default subnet"
  type        = string
  default     = "us-east-1a"
}

variable "control_plane_instance_type" {
  description = "EC2 instance type for the Kubernetes control plane"
  type        = string
  default     = "t3.small"
}

variable "worker_instance_type" {
  description = "EC2 instance type for worker nodes"
  type        = string
  default     = "t3.small"
}

variable "root_volume_size" {
  description = "Root disk size (GiB) for all cluster nodes"
  type        = number
  default     = 20
}

variable "artifacts_directory" {
  description = "Directory where k8s-key.pem, k8s-key.pub, and machines.txt are written (typically path.module of the root stack)."
  type        = string
}

variable "private_key_filename" {
  description = "Filename for the generated PEM (under artifacts_directory)"
  type        = string
  default     = "k8s-key.pem"
}

variable "public_key_filename" {
  description = "Filename for the generated public key (under artifacts_directory)"
  type        = string
  default     = "k8s-key.pub"
}

variable "machines_txt_filename" {
  description = "Filename for generated machines.txt (under artifacts_directory)"
  type        = string
  default     = "machines.txt"
}
