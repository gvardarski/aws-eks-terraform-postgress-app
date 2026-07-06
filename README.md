# AWS EKS Terraform PostgreSQL CRUD App

This repository demonstrates a simple containerized CRUD application on AWS using:

- Terraform for AWS infrastructure
- Amazon EKS for Kubernetes
- Amazon ECR for the application image
- PostgreSQL running as a container inside Kubernetes
- EBS-backed persistent storage for PostgreSQL
- AWS Secrets Manager and External Secrets Operator for database credentials
- AWS Load Balancer Controller for public application access through an ALB

The goal is to show the full path from infrastructure provisioning to a running Kubernetes application with persistent data and external access.

## Prerequisites

Use an AWS account with permissions to create VPC, EKS, ECR, IAM, Secrets Manager, EBS, and load balancer resources. The local workstation needs Terraform, AWS CLI, kubectl, Helm, and Docker.

This project uses EKS Kubernetes `1.36`, so `kubectl` should normally be within one minor version of the cluster version: `1.35`, `1.36`, or `1.37`.


## General Architecture

```text
User Browser
    |
    v
AWS Application Load Balancer
    |
    v
Kubernetes Ingress
    |
    v
api Service -> 2 FastAPI pods
                  |
                  v
            postgres Service
                  |
                  v
          PostgreSQL StatefulSet
                  |
                  v
        EBS gp3 Persistent Volume

AWS Secrets Manager -> External Secrets Operator -> Kubernetes Secret
```

The application is exposed publicly through the ALB. PostgreSQL is not public; it is reachable only inside the Kubernetes cluster through an internal `ClusterIP` service.

## Repository Layout

```text
app/        FastAPI CRUD application and Dockerfile
k8s/        Kubernetes manifests for PostgreSQL, secrets, API, service, and ingress
scripts/    Helper script for building and pushing the Docker image
secrets/    Example PostgreSQL secret payload
terraform/  AWS infrastructure code split into local modules
```

## 1. Provisioning Infrastructure With Terraform

Terraform provisions the AWS foundation required for the EKS deployment. The root stack is in `terraform/main.tf` and uses local modules:

```text
terraform/modules/vpc              VPC, public/private subnets, routes, NAT Gateway
terraform/modules/eks              EKS cluster, managed node group, EBS CSI, IAM roles
terraform/modules/ecr              ECR repository for the app image
terraform/modules/secrets-manager  Secrets Manager secret metadata
```

Important configuration values are defined in `terraform/terraform.tfvars`. Before applying, set `admin_cidr` to your own public IP with `/32`, and adjust names, region, NAT shape, Kubernetes version, and node sizing if needed.

The Terraform backend is configured for S3 remote state using:

```text
terraform/backend.tf
terraform/backend.dev.tfbackend
```

The S3 bucket for Terraform state must exist before `terraform init`, because Terraform cannot create the backend bucket it is trying to use. Create it once from the AWS Console in S3, using a globally unique bucket name, with versioning enabled, server-side encryption enabled, and public access blocked.

Then edit `terraform/backend.dev.tfbackend` and set the bucket name:

```hcl
bucket       = "replace-with-globally-unique-bucket-name"
key          = "inventory/dev/terraform.tfstate"
region       = "eu-north-1"
encrypt      = true
use_lockfile = true
```

Initialize Terraform with that backend config:

```bash
terraform -chdir=terraform init -backend-config=backend.dev.tfbackend
```

If the backend is already initialized, the infrastructure provisioning flow is:

```bash
terraform -chdir=terraform plan
terraform -chdir=terraform apply
```

After Terraform finishes, configure local access to the EKS cluster:

```bash
aws eks update-kubeconfig \
  --region "$(terraform -chdir=terraform output -raw aws_region)" \
  --name "$(terraform -chdir=terraform output -raw cluster_name)"
```

The worker nodes are created in private subnets. Public subnets are used for the internet-facing ALB and NAT Gateway. IAM Roles for Service Accounts are created for the EBS CSI driver, External Secrets Operator, and AWS Load Balancer Controller.

## 2. PostgreSQL Setup And Data Persistence

PostgreSQL runs inside the Kubernetes cluster as a containerized StatefulSet:

```text
k8s/postgres-statefulset.yaml
```

It uses the `postgres:16-alpine` image and mounts its data directory at:

```text
/var/lib/postgresql/data
```

Persistent storage is provided through:

```text
k8s/storageclass.yaml
k8s/postgres-statefulset.yaml
```

The `gp3` StorageClass uses the AWS EBS CSI driver and enables encrypted EBS volumes. The PostgreSQL StatefulSet defines a `volumeClaimTemplate` requesting a `5Gi` `ReadWriteOnce` volume, so PostgreSQL data survives container restarts and pod rescheduling.

PostgreSQL is exposed only inside Kubernetes through:

```text
k8s/postgres-service.yaml
```

That service is named `postgres`, uses `type: ClusterIP`, and exposes port `5432`. The API receives this internal hostname through:

```text
k8s/app-configmap.yaml
```

The connection path is:

```text
FastAPI pod -> postgres ClusterIP service -> postgres-0 pod -> EBS volume
```

Database credentials are stored in AWS Secrets Manager. Terraform creates the secret metadata, and the real secret value is inserted after infrastructure creation. External Secrets Operator syncs the AWS secret into Kubernetes as `postgres-secret`:

```text
k8s/external-secret-store.yaml
k8s/external-secret.yaml
secrets/postgres-secret.example.json
```

This keeps the database password out of Terraform state and out of the committed Kubernetes manifests.

In `secrets/postgres-secret.example.json`, `POSTGRES_DB` must match `DB_NAME`, `POSTGRES_USER` must match `DB_USER`, and `POSTGRES_PASSWORD` must match `DB_PASSWORD`. The `POSTGRES_*` values initialize the PostgreSQL container, while the `DB_*` values are consumed by the FastAPI application.

After Terraform creates the Secrets Manager secret, create a local `secrets/postgres-secret.json` from the example file and insert that JSON value into the Terraform-created secret name shown by the `postgres_secret_name` output. This can be done from the AWS Console or AWS CLI. The real secret JSON is a local-only file and should not be committed.

## 3. Docker Image Build Process And ECR Setup

The application is a FastAPI CRUD API in `app/main.py`. It connects to PostgreSQL and exposes basic item operations:

```text
GET    /healthz
GET    /readyz
POST   /items
GET    /items
GET    /items/{item_id}
PUT    /items/{item_id}
DELETE /items/{item_id}
```

The API also exposes the FastAPI Swagger UI at `/docs`, which can be opened in a browser and used to test the CRUD operations after the ALB is ready.

The Docker image is defined in:

```text
app/Dockerfile
```

Terraform creates an ECR repository through:

```text
terraform/modules/ecr/
```

The ECR repository uses AES256 encryption, image scanning on push, and a lifecycle policy that keeps only the latest demo images.

After Terraform creates ECR, build and push the application image:

```bash
ECR_REPOSITORY_URL="$(terraform -chdir=terraform output -raw ecr_repository_url)"
AWS_REGION="$(terraform -chdir=terraform output -raw aws_region)"
AWS_REGION="$AWS_REGION" bash scripts/build-and-push.sh "$ECR_REPOSITORY_URL"
```

The script logs in to ECR, builds the Docker image from `app/Dockerfile`, tags it as `latest`, and pushes it to the Terraform-created ECR repository.

## 4. Kubernetes Deployment

Kubernetes manifests live in `k8s/` and are applied with Kustomize:

```text
k8s/namespace.yaml
k8s/storageclass.yaml
k8s/external-secret-store.yaml
k8s/external-secret.yaml
k8s/postgres-service.yaml
k8s/postgres-statefulset.yaml
k8s/app-configmap.yaml
k8s/app-deployment.yaml
k8s/app-service.yaml
k8s/app-ingress.yaml
k8s/kustomization.yaml
```

Before applying the application manifests, install the required controllers with Helm:

- AWS Load Balancer Controller, which creates the ALB from `k8s/app-ingress.yaml`
- External Secrets Operator, which syncs the PostgreSQL credentials from AWS Secrets Manager

The Helm chart values should use the IAM role ARNs created by Terraform. External Secrets Operator uses the `external_secrets_role_arn` output on the `external-secrets` service account. AWS Load Balancer Controller uses the `aws_load_balancer_controller_role_arn` output on the `aws-load-balancer-controller` service account, together with the Terraform outputs for cluster name, region, and VPC ID.

Collect the Terraform outputs used by the Helm charts:

```bash
AWS_REGION="$(terraform -chdir=terraform output -raw aws_region)"
CLUSTER_NAME="$(terraform -chdir=terraform output -raw cluster_name)"
VPC_ID="$(terraform -chdir=terraform output -raw vpc_id)"
EXTERNAL_SECRETS_ROLE_ARN="$(terraform -chdir=terraform output -raw external_secrets_role_arn)"
AWS_LBC_ROLE_ARN="$(terraform -chdir=terraform output -raw aws_load_balancer_controller_role_arn)"
```

Add the Helm chart repositories:

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm repo add eks https://aws.github.io/eks-charts
helm repo update
```

Install External Secrets Operator:

```bash
helm upgrade --install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --create-namespace \
  --set installCRDs=true \
  --set serviceAccount.create=true \
  --set serviceAccount.name=external-secrets \
  --set-string serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="$EXTERNAL_SECRETS_ROLE_ARN"
```

Install AWS Load Balancer Controller:

```bash
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --set clusterName="$CLUSTER_NAME" \
  --set region="$AWS_REGION" \
  --set vpcId="$VPC_ID" \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set-string serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="$AWS_LBC_ROLE_ARN"
```

Verify the controllers before applying the application manifests:

```bash
kubectl -n external-secrets rollout status deployment/external-secrets
kubectl -n kube-system rollout status deployment/aws-load-balancer-controller
kubectl wait --for=condition=Established \
  crd/externalsecrets.external-secrets.io \
  crd/secretstores.external-secrets.io \
  --timeout=120s
```

The API deployment is configured in:

```text
k8s/app-deployment.yaml
```

It runs two application instances:

```yaml
replicas: 2
```

Before deployment, replace the example image in `k8s/app-deployment.yaml` with the ECR repository URL created by Terraform:

```text
<terraform ecr_repository_url output>:latest
```

Render and apply the manifests:

```bash
kubectl kustomize k8s
kubectl apply -k k8s
```

Verify the running workloads:

```bash
kubectl -n inventory get pods -o wide
kubectl -n inventory get pvc
kubectl -n inventory get svc
kubectl -n inventory get ingress
kubectl -n inventory get externalsecret
```

After the Ingress receives an ALB hostname, the application is available at:

```text
http://<alb-dns-name>/docs
```
