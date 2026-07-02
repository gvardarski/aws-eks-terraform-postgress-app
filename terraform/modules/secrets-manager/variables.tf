variable "name_prefix" {
  description = "Prefix used for tags and description."
  type        = string
}

variable "postgres_secret_name" {
  description = "Secrets Manager secret name for PostgreSQL credentials."
  type        = string
}

variable "recovery_window_in_days" {
  description = "Recovery window for deleting the secret."
  type        = number
}

