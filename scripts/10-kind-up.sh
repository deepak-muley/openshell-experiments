#!/usr/bin/env bash
# Create the kind cluster, install Cilium, and install a default StorageClass.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

need kind
need kubectl
need helm
need docker
docker info >/dev/null 2>&1 || die "docker daemon is not reachable."

# kind create cluster switches the current context. Put it back on the way out
# so a lab command does not steal the context from another cluster.
previous_context="$(kubectl config current-context 2>/dev/null || true)"
restore_context() {
  if [[ -n "${previous_context}" ]]; then
    kubectl config use-context "${previous_context}" >/dev/null 2>&1 || true
  fi
}
trap restore_context EXIT

if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  log "kind cluster ${CLUSTER_NAME} already exists"
elif [[ -n "${KIND_NODE_IMAGE}" ]]; then
  log "creating kind cluster ${CLUSTER_NAME} with ${KIND_NODE_IMAGE}"
  kind create cluster --name "${CLUSTER_NAME}" --config "${ROOT}/cluster/kind.yaml" --image "${KIND_NODE_IMAGE}"
else
  log "creating kind cluster ${CLUSTER_NAME} with kind's default node image"
  kind create cluster --name "${CLUSTER_NAME}" --config "${ROOT}/cluster/kind.yaml"
fi

require_lab_context

if ! kube -n kube-system get ds cilium >/dev/null 2>&1; then
  log "installing Cilium ${CILIUM_VERSION}"
  helm repo add cilium https://helm.cilium.io/ >/dev/null 2>&1 || true
  helm repo update cilium
  helm upgrade --install cilium cilium/cilium \
    --kube-context "$(lab_context)" \
    --version "${CILIUM_VERSION}" \
    --namespace kube-system \
    --values "${ROOT}/cluster/cilium-values.yaml" \
    --wait \
    --timeout 10m
else
  log "Cilium already installed"
fi

log "waiting for nodes"
kube wait --for=condition=Ready nodes --all --timeout=180s

# kind 0.27+ already installs a local-path StorageClass named standard.
# Adding a second default class makes PVCs fail to bind.
default_sc="$(kube get sc -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}{"\n"}{end}' | awk '$2=="true"{print $1; exit}')"
if [[ -n "${default_sc}" ]]; then
  log "default StorageClass is ${default_sc}"
else
  log "installing local-path-provisioner ${LOCAL_PATH_VERSION}"
  kube apply -f "https://raw.githubusercontent.com/rancher/local-path-provisioner/${LOCAL_PATH_VERSION}/deploy/local-path-storage.yaml"
  kube -n local-path-storage rollout status deploy/local-path-provisioner --timeout=180s
  kube annotate storageclass local-path storageclass.kubernetes.io/is-default-class=true --overwrite >/dev/null
fi

log "checking that NetworkPolicy is enforced"
"${ROOT}/scripts/11-verify-netpol.sh"

log "cluster ${CLUSTER_NAME} is ready"
kube get nodes -o wide
if ! "${ROOT}/scripts/12-check-kernel.sh"; then
  log "the cluster is up. Sandbox pods will not start until the node kernel has Landlock ABI v3."
fi
