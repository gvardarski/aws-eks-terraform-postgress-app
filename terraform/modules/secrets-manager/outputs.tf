output "postgres_secret_name" {
  description = "Secrets Manager secret name."
  value       = aws_secretsmanager_secret.postgres.name
}

output "postgres_secret_arn" {
  description = "Secrets Manager secret ARN."
  value       = aws_secretsmanager_secret.postgres.arn
}

