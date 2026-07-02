#!/usr/bin/env bash
set -euo pipefail

AWS_REGION="${AWS_REGION:-eu-north-1}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
REPOSITORY_URL="${1:-}"

if [[ -z "${REPOSITORY_URL}" ]]; then
  echo "Usage: $0 <ecr_repository_url>"
  echo "Example: $0 123456789012.dkr.ecr.eu-north-1.amazonaws.com/inventory-dev-api"
  exit 1
fi

REGISTRY="${REPOSITORY_URL%/*}"
IMAGE="${REPOSITORY_URL}:${IMAGE_TAG}"

aws ecr get-login-password --region "${AWS_REGION}" \
  | docker login --username AWS --password-stdin "${REGISTRY}"

docker build -t "${IMAGE}" ./app
docker push "${IMAGE}"

echo "Pushed ${IMAGE}"
