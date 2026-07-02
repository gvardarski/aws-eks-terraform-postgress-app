locals {
  name_prefix          = "${var.project_name}-${var.environment}"
  cluster_name         = var.cluster_name
  postgres_secret_name = "${var.project_name}/${var.environment}/postgres"

  common_tags = {
    Application = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Repository  = var.repository
  }
}
