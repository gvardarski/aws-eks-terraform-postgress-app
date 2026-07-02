variable "name_prefix" {
  description = "Prefix used for VPC resource names."
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name used for Kubernetes subnet discovery tags."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR range for the VPC."
  type        = string
}

variable "az_count" {
  description = "Number of Availability Zones to use."
  type        = number
}

variable "enable_nat_gateway" {
  description = "Create NAT Gateways for private subnet egress."
  type        = bool
}

variable "single_nat_gateway" {
  description = "Use one NAT Gateway instead of one per AZ."
  type        = bool
}

