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
argocd/     Argo CD install values and the Application that deploys the chart
chart/      Helm chart used for the local Docker Desktop deployment
k8s/        Kubernetes manifests for PostgreSQL, secrets, API, service, and ingress
scripts/    Helper scripts for image build and for the local Argo CD workflow
secrets/    Example PostgreSQL secret payload
terraform/  AWS infrastructure code split into local modules
```

The repository supports two deployment paths that do not overlap. Sections 1 to 4
describe the AWS EKS path built from `terraform/` and `k8s/`. Section 5 describes a
local path built from `chart/` and `argocd/`, which needs no AWS account.

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

## 5. Local Deployment With Docker Desktop And Argo CD

This section replaces sections 1 to 4 with a local workflow. It needs no AWS
account: the cluster is the one built into Docker Desktop, and the application is
deployed by Argo CD from the Helm chart in `chart/`.

### What Differs From The AWS Path

The chart deliberately drops the pieces that only exist on EKS:

```text
ALB Ingress            replaced by a LoadBalancer Service on localhost
gp3 EBS StorageClass   replaced by the cluster default StorageClass
External Secrets       replaced by a Secret created with scripts/local-secret.sh
ECR image              replaced by an image built into the local image store
```

Everything else is unchanged. PostgreSQL is still a StatefulSet with a persistent
volume, it is still reachable only through an internal `ClusterIP` service, and the
API still reads its credentials from a Secret rather than from the manifests.

### Prerequisites

Docker Desktop, `kubectl`, and Helm. Enable Kubernetes in Docker Desktop under
Settings, Kubernetes, Enable Kubernetes, and wait until it reports running:

```bash
docker desktop kubernetes status
kubectl config use-context docker-desktop
```

### Quick Start

One script performs the whole bootstrap:

```bash
./scripts/local-up.sh
```

It builds the image, creates the database Secret, installs Argo CD, registers the
Argo CD Application, and waits until the application reports healthy.

### What The Bootstrap Does

The same steps can be run individually.

Build the API image. Docker Desktop shares its image store with the Kubernetes
node, so no registry and no push are involved, and the chart sets
`imagePullPolicy: IfNotPresent` so the image is never fetched remotely:

```bash
docker build -t inventory-api:local ./app
```

Create the database credentials. The password is generated locally and only ever
exists in the cluster, which keeps it out of Git:

```bash
./scripts/local-secret.sh
```

Install Argo CD and print the admin password:

```bash
./scripts/local-argocd.sh
```

Register the Application, which is the only imperative step. From here on Argo CD
pulls from Git:

```bash
kubectl apply -f argocd/application.yaml
```

### How The Deployment Works

Argo CD runs inside the cluster and pulls the chart from GitHub, so it can only
deploy what has been pushed. `argocd/application.yaml` points at a branch and a
path:

```yaml
source:
  repoURL: https://github.com/gvardarski/aws-eks-terraform-postgress-app.git
  targetRevision: feature/local-testing
  path: chart
```

Change `targetRevision` if the chart is tracked on a different branch.

Argo CD renders the chart with `helm template` and applies the result itself, so no
Helm release is stored in the cluster and `helm list -n inventory` stays empty. It
then reports two independent values: `Sync`, which compares the cluster against
Git, and `Health`, which reports whether the workloads actually work.

Because `syncPolicy.automated` sets `prune` and `selfHeal`, Argo CD owns the
resources. Editing them with `kubectl` is reverted within seconds, and removing a
template from the chart deletes the matching resource from the cluster.

### Using The Application

Docker Desktop publishes LoadBalancer services on localhost:

```bash
curl http://localhost/healthz
curl http://localhost/items
curl -X POST http://localhost/items \
  -H 'Content-Type: application/json' \
  -d '{"name":"laptop","description":"dev machine"}'
```

The Swagger UI is at `http://localhost/docs`.

Open the Argo CD UI with a port-forward, then log in as `admin`:

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:80
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d
```

Inspect the workloads:

```bash
kubectl -n inventory get pods,svc,pvc
kubectl -n argocd get application inventory
```

### Changing The Deployment

Configuration changes go through Git, which is the whole point of the Argo CD
setup. Edit `chart/values.yaml`, commit, and push; Argo CD applies the change on
its next refresh, or immediately if the Application is refreshed from the UI.

Application code changes are the exception. The image tag stays `inventory-api:local`,
so Git does not change and Argo CD sees nothing to do. Rebuild and restart instead:

```bash
docker build -t inventory-api:local ./app
kubectl -n inventory rollout restart deployment/inventory-api
```

### Stopping And Cleaning Up

Deleting workloads with `kubectl` does not stop them, because self-heal recreates
them. Remove the Application instead, which is what `scripts/local-down.sh` does:

```bash
./scripts/local-down.sh        # remove the app, keep Argo CD and the database volume
./scripts/local-down.sh data   # also delete the namespace, volume, and Secret
./scripts/local-down.sh all    # also uninstall Argo CD
```

The default keeps the volume and the Secret, because neither is managed by Argo CD,
so re-applying the Application restores the app with its existing data.

Always delete the Application before uninstalling Argo CD. The Application carries a
finalizer that only the Argo CD controller can clear, so removing Argo CD first
leaves the object stuck in `Terminating`.

To stop Kubernetes itself, untick Enable Kubernetes in Docker Desktop settings, or
reset the cluster with `docker desktop kubernetes reset-cluster`.
