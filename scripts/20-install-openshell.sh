#!/usr/bin/env bash
# Install the Agent Sandbox controller, then the OpenShell gateway.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

need kubectl
need helm
require_lab_context

VALUES="${OPENSHELL_VALUES:-${ROOT}/deploy/openshell/values-kind.yaml}"
if [[ "$(kube_context)" != "kind-${CLUSTER_NAME}" ]]; then
  VALUES="${OPENSHELL_VALUES:-${ROOT}/deploy/openshell/values-cluster.yaml}"
fi

log "installing Agent Sandbox controller"
kube apply -f "${AGENT_SANDBOX_MANIFEST}"
kube -n agent-sandbox-system wait --for=condition=available deployment --all --timeout=180s

log "installing OpenShell ${OPENSHELL_CHART_VERSION} with ${VALUES}"
kube create namespace "${NAMESPACE}" --dry-run=client -o yaml | kube apply -f -
helm upgrade --install openshell \
  "oci://ghcr.io/nvidia/openshell/helm-chart" \
  --kube-context "$(lab_context)" \
  --version "${OPENSHELL_CHART_VERSION}" \
  --namespace "${NAMESPACE}" \
  --values "${VALUES}" \
  --wait \
  --timeout 12m

kube -n "${NAMESPACE}" rollout status statefulset/openshell --timeout=180s
kube -n "${NAMESPACE}" get pods,svc,pvc
log "gateway is up"
