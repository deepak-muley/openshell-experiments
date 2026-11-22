#!/usr/bin/env bash
# Prove the CNI enforces egress NetworkPolicy.
# A default-deny namespace must fail a curl that succeeds in the default namespace.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

require_lab_context

NS=openshell-netpol-check
POD=curl-deny
OPEN_POD=openshell-curl-allow
IMAGE=curlimages/curl:8.11.1

cleanup() {
  kube delete namespace "${NS}" --wait=false >/dev/null 2>&1 || true
  kube -n default delete pod "${OPEN_POD}" --wait=false >/dev/null 2>&1 || true
}
trap cleanup EXIT

kube delete namespace "${NS}" --wait=true >/dev/null 2>&1 || true
kube -n default delete pod "${OPEN_POD}" --wait=true >/dev/null 2>&1 || true

kube create namespace "${NS}"
kube -n "${NS}" apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-egress
spec:
  podSelector: {}
  policyTypes:
    - Egress
EOF

kube -n "${NS}" run "${POD}" \
  --image="${IMAGE}" \
  --restart=Never \
  --command -- curl -fsS --max-time 8 -o /dev/null https://example.com
kube -n default run "${OPEN_POD}" \
  --image="${IMAGE}" \
  --restart=Never \
  --command -- curl -fsS --max-time 8 -o /dev/null https://example.com

phase_of() {
  local ns="$1"
  local pod="$2"
  kube -n "${ns}" get pod "${pod}" -o jsonpath='{.status.phase}' 2>/dev/null || true
}

deadline=$((SECONDS + 180))
deny_phase=""
allow_phase=""
while (( SECONDS < deadline )); do
  deny_phase="$(phase_of "${NS}" "${POD}")"
  allow_phase="$(phase_of default "${OPEN_POD}")"
  if [[ "${deny_phase}" == "Succeeded" || "${deny_phase}" == "Failed" ]]; then
    if [[ "${allow_phase}" == "Succeeded" || "${allow_phase}" == "Failed" ]]; then
      break
    fi
  fi
  sleep 3
done

log "deny-namespace pod phase=${deny_phase:-unknown}  open-namespace pod phase=${allow_phase:-unknown}"

if [[ "${allow_phase}" != "Succeeded" ]]; then
  kube -n default logs "${OPEN_POD}" || true
  die "the open pod could not reach example.com, so this check cannot tell whether NetworkPolicy is enforced."
fi

if [[ "${deny_phase}" == "Succeeded" ]]; then
  die "the default-deny pod reached example.com. This CNI is not enforcing NetworkPolicy. OpenShell must not be installed on it."
fi

if [[ "${deny_phase}" != "Failed" ]]; then
  die "timed out waiting for the NetworkPolicy check (deny=${deny_phase:-unknown})."
fi

log "NetworkPolicy egress deny is enforced"
