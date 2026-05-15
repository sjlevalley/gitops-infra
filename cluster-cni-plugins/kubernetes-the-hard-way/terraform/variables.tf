# Variables for the EC2 instance configuration

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t2.micro"  # Free tier eligible
}

variable "instance_name" {
  description = "Name tag for the EC2 instance"
  type        = string
  default     = "main-instance"
}

variable "pod_subnets" {
  description = "Pod subnets for worker nodes"
  type = map(string)
  default = {
    node-0 = "10.244.0.0/24"
    node-1 = "10.244.1.0/24"
  }
} 