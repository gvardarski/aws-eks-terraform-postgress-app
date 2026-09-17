#!/usr/bin/env bash
# Creates the PostgreSQL credentials Secret that the Helm chart expects.
# The password is generated locally and never stored in Git.
set -euo pipefail

NAMESPACE="${NAMESPACE:-inventory}"
SECRET_NAME="${SECRET_NAME:-postgres-secret}"
DB_NAME="${DB_NAME:-inventory}"
DB_USER="${DB_USER:-inventory}"

kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

if kubectl --namespace "${NAMESPACE}" get secret "${SECRET_NAME}" >/dev/null 2>&1; then
  echo "Secret ${SECRET_NAME} already exists in namespace ${NAMESPACE}; keeping the current password."
  exit 0
fi

DB_PASSWORD="${DB_PASSWORD:-$(openssl rand -hex 16)}"

# POSTGRES_* initialise the database container, DB_* configure the API container.
kubectl --namespace "${NAMESPACE}" create secret generic "${SECRET_NAME}" \
  --from-literal=POSTGRES_DB="${DB_NAME}" \
  --from-literal=POSTGRES_USER="${DB_USER}" \
  --from-literal=POSTGRES_PASSWORD="${DB_PASSWORD}" \
  --from-literal=DB_NAME="${DB_NAME}" \
  --from-literal=DB_USER="${DB_USER}" \
  --from-literal=DB_PASSWORD="${DB_PASSWORD}"

echo "Created secret ${SECRET_NAME} in namespace ${NAMESPACE}."
