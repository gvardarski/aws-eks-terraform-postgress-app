module "vpc" {
  source = "./modules/vpc"

  name_prefix        = local.name_prefix
  cluster_name       = local.cluster_name
  vpc_cidr           = var.vpc_cidr
  az_count           = var.az_count
  enable_nat_gateway = var.enable_nat_gateway
  single_nat_gateway = var.single_nat_gateway
}

module "ecr" {
  source = "./modules/ecr"

  name_prefix      = local.name_prefix
  force_delete_ecr = var.force_delete_ecr
}

module "secrets_manager" {
  source = "./modules/secrets-manager"

  name_prefix             = local.name_prefix
  postgres_secret_name    = local.postgres_secret_name
  recovery_window_in_days = var.postgres_secret_recovery_window_in_days
}

module "eks" {
  source = "./modules/eks"

  name_prefix                          = local.name_prefix
  cluster_name                         = local.cluster_name
  kubernetes_version                   = var.kubernetes_version
  enable_control_plane_logs            = var.enable_control_plane_logs
  cluster_endpoint_public_access_cidrs = [var.admin_cidr]

  public_subnet_ids  = module.vpc.public_subnet_ids
  private_subnet_ids = module.vpc.private_subnet_ids

  node_instance_types = var.node_instance_types
  node_capacity_type  = var.node_capacity_type
  node_desired_size   = var.node_desired_size
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size
  node_disk_size_gib  = var.node_disk_size_gib

  postgres_secret_arn = module.secrets_manager.postgres_secret_arn

  depends_on = [module.vpc]
}
