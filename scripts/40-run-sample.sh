#!/usr/bin/env bash
# Build the probe image, load it into kind, and create the sandbox.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

need docker
need kubectl
require_cli
require_lab_context

log "building ${SAMPLE_IMAGE}"
docker build \
  --build-arg "BASE=${SAMPLE_BASE_IMAGE:-alpine:3.20}" \
  -t "${SAMPLE_IMAGE}" \
  "${ROOT}/samples/probe-agent"

ctx="$(kube_context)"
if [[ "${ctx}" == "kind-${CLUSTER_NAME}" ]]; then
  log "loading ${SAMPLE_IMAGE} into kind node containerd"
  kind load docker-image "${SAMPLE_IMAGE}" --name "${CLUSTER_NAME}"
elif [[ "${PUSH_IMAGE:-}" == "1" ]]; then
  log "pushing ${SAMPLE_IMAGE}"
  docker push "${SAMPLE_IMAGE}"
else
  die "context ${ctx} is not the kind cluster. Set SAMPLE_IMAGE to a registry reference and PUSH_IMAGE=1."
fi

delete_help="$(oscli sandbox delete --help 2>&1 || true)"
if grep -q -- '--yes' <<<"${delete_help}"; then
  oscli sandbox delete "${SAMPLE_SANDBOX_NAME}" --yes >/dev/null 2>&1 || true
elif grep -q -- '--force' <<<"${delete_help}"; then
  oscli sandbox delete "${SAMPLE_SANDBOX_NAME}" --force >/dev/null 2>&1 || true
else
  oscli sandbox delete "${SAMPLE_SANDBOX_NAME}" >/dev/null 2>&1 || true
fi

"${ROOT}/scripts/12-check-kernel.sh"

log "creating sandbox ${SAMPLE_SANDBOX_NAME}"
oscli sandbox create \
  --name "${SAMPLE_SANDBOX_NAME}" \
  --from "${SAMPLE_IMAGE}" \
  --policy "${ROOT}/policies/sample-agent.yaml" \
  --cpu 1 \
  --memory 1Gi \
  --detach \
  --no-auto-providers \
  -- /usr/local/bin/python /opt/sample-agent/agent.py

snapshot_logs() {
  # `openshell logs` may follow. Bound each read so the wait loop can proceed.
  oscli logs "${SAMPLE_SANDBOX_NAME}" >"${STATE}/sample-agent.log" 2>&1 &
  local pid=$!
  local _
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
    if grep -q 'SAMPLE_AGENT_RESULT=' "${STATE}/sample-agent.log" 2>/dev/null; then
      kill "${pid}" 2>/dev/null || true
      wait "${pid}" 2>/dev/null || true
      return 0
    fi
    if ! kill -0 "${pid}" 2>/dev/null; then
      wait "${pid}" 2>/dev/null || true
      grep -q 'SAMPLE_AGENT_RESULT=' "${STATE}/sample-agent.log" 2>/dev/null
      return $?
    fi
    sleep 1
  done
  kill "${pid}" 2>/dev/null || true
  wait "${pid}" 2>/dev/null || true
  return 1
}

log "waiting for the probe result"
found=""
for _ in $(seq 1 40); do
  if snapshot_logs; then
    found=1
    break
  fi
  sleep 3
done

log "sandbox objects"
kube -n "${NAMESPACE}" get pods,sandboxes,svc,pvc,networkpolicy || true
echo
oscli sandbox get "${SAMPLE_SANDBOX_NAME}" || true
echo
if [[ -f "${STATE}/sample-agent.log" ]]; then
  log "sandbox log"
  cat "${STATE}/sample-agent.log"
fi

if [[ "${found}" != "1" ]]; then
  log "probe line was not in openshell logs yet; dumping sandbox pod logs"
  kube -n "${NAMESPACE}" get pods -o name | while read -r pod; do
    case "${pod}" in
      pod/openshell-0|pod/openshell-*) continue ;;
    esac
    echo "-- ${pod}"
    kube -n "${NAMESPACE}" logs "${pod}" --all-containers --tail=200 || true
  done
  die "the probe did not report SAMPLE_AGENT_RESULT. See the logs above."
fi

if grep -q 'SAMPLE_AGENT_RESULT=pass' "${STATE}/sample-agent.log"; then
  log "sample agent passed inside the sandbox"
else
  die "sample agent reported a failure. Read ${STATE}/sample-agent.log"
fi
