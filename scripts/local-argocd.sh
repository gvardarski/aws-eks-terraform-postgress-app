#!/usr/bin/env bash
# Installs Argo CD into the local Docker Desktop cluster and prints the
# admin password. Safe to re-run; the Helm release is upgraded in place.
set -euo pipefail

NAMESPACE="${NAMESPACE:-argocd}"
RELEASE="${RELEASE:-argocd}"
CHART_VERSION="${CHART_VERSION:-10.9.1}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALUES_FILE="${SCRIPT_DIR}/../argocd/values.yaml"

helm repo add argo https://argoproj.github.io/argo-helm >/dev/null
helm repo update argo >/dev/null

helm upgrade --install "${RELEASE}" argo/argo-cd \
  --namespace "${NAMESPACE}" \
  --create-namespace \
  --version "${CHART_VERSION}" \
  --values "${VALUES_FILE}" \
  --wait \
  --timeout 10m

echo
echo "Argo CD is installed."
echo "Admin password: $(kubectl --namespace "${NAMESPACE}" get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"
echo
echo "Open the UI with:"
echo "  kubectl --namespace ${NAMESPACE} port-forward svc/argocd-server 8080:80"
echo "  then browse to http://localhost:8080 and log in as 'admin'."
