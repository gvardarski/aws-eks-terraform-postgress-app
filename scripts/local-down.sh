#!/usr/bin/env bash
# Tears down the local deployment. Argo CD owns the workloads, so they are
# removed by deleting the Application rather than with `kubectl delete`,
# which self-heal would simply undo.
#
#   ./scripts/local-down.sh          Remove the app, keep Argo CD and the database volume
#   ./scripts/local-down.sh data     Also delete the namespace, so the volume and Secret go
#   ./scripts/local-down.sh all      Also uninstall Argo CD
set -euo pipefail

SCOPE="${1:-app}"
NAMESPACE="${NAMESPACE:-inventory}"
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
APP_NAME="${APP_NAME:-inventory}"
RELEASE="${RELEASE:-argocd}"

case "${SCOPE}" in
  app|data|all) ;;
  *)
    echo "Usage: $0 [app|data|all]" >&2
    exit 1
    ;;
esac

# The Application carries a finalizer that only the Argo CD controller can
# clear, so it has to be deleted while Argo CD is still running.
if kubectl --namespace "${ARGOCD_NAMESPACE}" get application "${APP_NAME}" >/dev/null 2>&1; then
  echo "==> Deleting Argo CD Application ${APP_NAME} and the resources it manages"
  if ! kubectl --namespace "${ARGOCD_NAMESPACE}" delete application "${APP_NAME}" --timeout=5m; then
    echo "    Finalizer did not complete; dropping it so the object can be removed."
    kubectl --namespace "${ARGOCD_NAMESPACE}" patch application "${APP_NAME}" \
      --type merge -p '{"metadata":{"finalizers":[]}}' >/dev/null 2>&1 || true
    kubectl --namespace "${ARGOCD_NAMESPACE}" delete application "${APP_NAME}" \
      --ignore-not-found --timeout=1m || true
  fi
else
  echo "==> No Argo CD Application named ${APP_NAME}; nothing to remove."
fi

if [[ "${SCOPE}" == "app" ]]; then
  echo
  echo "Done. The database volume and the postgres-secret are still in namespace ${NAMESPACE},"
  echo "so re-applying argocd/application.yaml restores the app with its existing data."
  exit 0
fi

echo "==> Deleting namespace ${NAMESPACE}, including the database volume and Secret"
kubectl delete namespace "${NAMESPACE}" --ignore-not-found --timeout=5m

if [[ "${SCOPE}" == "data" ]]; then
  echo
  echo "Done. Argo CD is still installed in namespace ${ARGOCD_NAMESPACE}."
  echo "Re-create the Secret with scripts/local-secret.sh before deploying again."
  exit 0
fi

echo "==> Uninstalling Argo CD"
helm uninstall "${RELEASE}" --namespace "${ARGOCD_NAMESPACE}" --ignore-not-found --wait || true
kubectl delete namespace "${ARGOCD_NAMESPACE}" --ignore-not-found --timeout=5m

echo
echo "Done. The cluster is back to an empty state."
echo "To stop Kubernetes entirely, untick Enable Kubernetes in Docker Desktop settings."
