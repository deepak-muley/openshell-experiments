#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

if [[ -f "${STATE}/port-forward.pid" ]]; then
  pid="$(cat "${STATE}/port-forward.pid")"
  if kill -0 "${pid}" 2>/dev/null; then
    kill "${pid}" || true
    log "stopped port-forward ${pid}"
  fi
  rm -f "${STATE}/port-forward.pid"
fi

if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  kind delete cluster --name "${CLUSTER_NAME}"
  log "deleted kind cluster ${CLUSTER_NAME}"
else
  log "kind cluster ${CLUSTER_NAME} is not present"
fi
