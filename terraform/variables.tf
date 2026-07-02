variable "aws_region" {
  description = "AWS region where the demo infrastructure is created."
  type        = string
}

variable "project_name" {
  description = "Short lowercase project name used in resource names."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,24}$", var.project_name))
    error_message = "Project name must be lowercase, start with a letter, and contain only letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment suffix used in resource names."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,12}$", var.environment))
    error_message = "Environment must be lowercase and contain only letters, numbers, and hyphens."
  }
}

variable "cluster_name" {
  description = "Friendly EKS cluster name shown in the AWS console and kubeconfig."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,32}$", var.cluster_name))
    error_message = "Cluster name must be lowercase, start with a letter, and contain only letters, numbers, and hyphens."
  }
}

variable "admin_cidr" {
  description = "Your public IP as a /32 CIDR. This is allowed to reach the EKS API endpoint."
  type        = string

  validation {
    condition     = can(cidrhost(var.admin_cidr, 0))
    error_message = "admin_cidr must be a valid CIDR block, for example 198.51.100.10/32."
  }
}

variable "repository" {
  description = "Repository tag value for all AWS resources."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR range for the VPC."
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid CIDR block, for example 10.42.0.0/16."
  }
}

variable "az_count" {
  description = "Number of Availability Zones to use."
  type        = number

  validation {
    condition     = var.az_count >= 2
    error_message = "az_count must be at least 2 so the public ALB can span multiple Availability Zones."
  }
}

variable "enable_nat_gateway" {
  description = "Create NAT Gateways for private subnet egress."
  type        = bool
}

variable "single_nat_gateway" {
  description = "Use one NAT Gateway instead of one per Availability Zone."
  type        = bool
}

variable "force_delete_ecr" {
  description = "Allow Terraform destroy to delete the ECR repository even if it contains images."
  type        = bool
}

variable "postgres_secret_recovery_window_in_days" {
  description = "Recovery window for deleting the PostgreSQL Secrets Manager secret. Use 0 for immediate demo cleanup."
  type        = number

  validation {
    condition     = var.postgres_secret_recovery_window_in_days == 0 || (var.postgres_secret_recovery_window_in_days >= 7 && var.postgres_secret_recovery_window_in_days <= 30)
    error_message = "postgres_secret_recovery_window_in_days must be 0 for immediate deletion or between 7 and 30."
  }
}

variable "kubernetes_version" {
  description = "EKS Kubernetes minor version."
  type        = string

  validation {
    condition     = can(regex("^1\\.[0-9]{2}$", var.kubernetes_version))
    error_message = "kubernetes_version must look like 1.36."
  }
}

variable "enable_control_plane_logs" {
  description = "Enable EKS control plane logs."
  type        = bool
}

variable "node_instance_types" {
  description = "EC2 instance types for the EKS managed node group."
  type        = list(string)

  validation {
    condition     = length(var.node_instance_types) > 0
    error_message = "node_instance_types must contain at least one EC2 instance type."
  }
}

variable "node_capacity_type" {
  description = "Capacity type for the EKS managed node group."
  type        = string

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.node_capacity_type)
    error_message = "node_capacity_type must be ON_DEMAND or SPOT."
  }
}

variable "node_desired_size" {
  description = "Desired worker node count."
  type        = number

  validation {
    condition     = var.node_desired_size >= 1
    error_message = "node_desired_size must be at least 1."
  }
}

variable "node_min_size" {
  description = "Minimum worker node count."
  type        = number

  validation {
    condition     = var.node_min_size >= 1
    error_message = "node_min_size must be at least 1."
  }
}

variable "node_max_size" {
  description = "Maximum worker node count."
  type        = number

  validation {
    condition     = var.node_max_size >= 1
    error_message = "node_max_size must be at least 1."
  }
}

variable "node_disk_size_gib" {
  description = "Root EBS volume size for each worker node."
  type        = number

  validation {
    condition     = var.node_disk_size_gib >= 20
    error_message = "node_disk_size_gib must be at least 20."
  }
}
