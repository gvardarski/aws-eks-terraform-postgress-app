#!/usr/bin/env bash
# One-shot bootstrap of the local environment:
# builds the API image, creates the database Secret, installs Argo CD and
# registers the Argo CD Application that deploys the Helm chart.
set -euo pipefail

NAMESPACE="${NAMESPACE:-inventory}"
IMAGE="${IMAGE:-inventory-api:local}"
EXPECTED_CONTEXT="${EXPECTED_CONTEXT:-docker-desktop}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

current_context="$(kubectl config current-context)"
if [[ "${current_context}" != "${EXPECTED_CONTEXT}" ]]; then
  echo "Refusing to run: kubectl context is '${current_context}', expected '${EXPECTED_CONTEXT}'." >&2
  echo "Switch with: kubectl config use-context ${EXPECTED_CONTEXT}" >&2
  exit 1
fi

echo "==> Building ${IMAGE} into the local Docker Desktop image store"
docker build -t "${IMAGE}" "${REPO_ROOT}/app"

echo "==> Creating the PostgreSQL Secret"
"${SCRIPT_DIR}/local-secret.sh"

echo "==> Installing Argo CD"
"${SCRIPT_DIR}/local-argocd.sh"

echo "==> Registering the Argo CD Application"
kubectl apply -f "${REPO_ROOT}/argocd/application.yaml"

echo "==> Waiting for the application to become healthy"
kubectl --namespace argocd wait --for=jsonpath='{.status.health.status}'=Healthy \
  application/inventory --timeout=10m

echo
echo "Deployed. The API is published on http://localhost/"
kubectl --namespace "${NAMESPACE}" get pods,svc
