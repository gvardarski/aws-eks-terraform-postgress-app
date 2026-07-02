variable "name_prefix" {
  description = "Prefix used for ECR resource names."
  type        = string
}

variable "force_delete_ecr" {
  description = "Allow repository deletion even if it contains images."
  type        = bool
}

