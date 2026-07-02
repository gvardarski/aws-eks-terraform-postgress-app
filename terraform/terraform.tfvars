aws_region   = "eu-north-1"
project_name = "inventory"
environment  = "dev"
cluster_name = "eks-demo-cluster"

repository = "aws-eks-terraform-postgres-app"

# Replace this with your own public IP followed by /32 before applying.
# Example lookup: curl https://checkip.amazonaws.com
admin_cidr = "203.0.113.10/32"

vpc_cidr           = "10.42.0.0/16"
az_count           = 2
enable_nat_gateway = true
single_nat_gateway = true

force_delete_ecr                        = true
postgres_secret_recovery_window_in_days = 0
kubernetes_version                      = "1.36"
enable_control_plane_logs               = false
node_instance_types                     = ["t3.small"]
node_capacity_type                      = "ON_DEMAND"
node_desired_size                       = 2
node_min_size                           = 2
node_max_size                           = 2
node_disk_size_gib                      = 20
