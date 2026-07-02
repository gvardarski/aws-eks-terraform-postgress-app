variable "name_prefix" {
  description = "Prefix used for EKS resource names."
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
}

variable "kubernetes_version" {
  description = "Optional EKS Kubernetes version."
  type        = string
  default     = null
}

variable "enable_control_plane_logs" {
  description = "Enable EKS control plane logs."
  type        = bool
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDR blocks allowed to reach the public EKS API endpoint."
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "Public subnet IDs used by the EKS control plane and public ALBs."
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Private subnet IDs used by worker nodes."
  type        = list(string)
}

variable "node_instance_types" {
  description = "EC2 instance types for the managed node group."
  type        = list(string)
}

variable "node_capacity_type" {
  description = "Capacity type for the managed node group."
  type        = string
}

variable "node_desired_size" {
  description = "Desired worker node count."
  type        = number
}

variable "node_min_size" {
  description = "Minimum worker node count."
  type        = number
}

variable "node_max_size" {
  description = "Maximum worker node count."
  type        = number
}

variable "node_disk_size_gib" {
  description = "Root EBS volume size for each worker node."
  type        = number
}

variable "postgres_secret_arn" {
  description = "Secrets Manager ARN that External Secrets Operator can read."
  type        = string
}
