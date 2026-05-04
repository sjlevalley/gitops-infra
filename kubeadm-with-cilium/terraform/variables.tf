variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "pod_subnets" {
  description = "Pod subnets for worker nodes (machines.txt)"
  type        = map(string)
  default = {
    node-0 = "10.244.0.0/24"
    node-1 = "10.244.1.0/24"
  }
}
