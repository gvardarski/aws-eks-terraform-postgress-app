resource "aws_secretsmanager_secret" "postgres" {
  name                    = var.postgres_secret_name
  description             = "PostgreSQL credentials for ${var.name_prefix} demo workloads."
  recovery_window_in_days = var.recovery_window_in_days
}

