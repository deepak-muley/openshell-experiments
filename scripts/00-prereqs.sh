#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

need docker "Install Docker Desktop or Docker Engine. kind uses it as the node host."
need kind "Install kind: https://kind.sigs.k8s.io/docs/user/quick-start/#installation"
need kubectl "Install kubectl matching your cluster."
need helm "Install Helm 3."
python_bin >/dev/null
need curl "curl is used by the host-side checks."

docker info >/dev/null 2>&1 || die "docker is installed but the daemon is not reachable."

log "docker $(docker version --format '{{.Server.Version}}' 2>/dev/null || echo present)"
log "kind $(kind version | head -n 1)"
log "kubectl $(kubectl version --client --output=yaml 2>/dev/null | awk '/gitVersion:/ {print $2; exit}')"
log "helm $(helm version --short)"
log "python $(python_bin) $( "$(python_bin)" -c 'import sys; print(sys.version.split()[0])' )"
log "pins: openshell chart ${OPENSHELL_CHART_VERSION}, cilium ${CILIUM_VERSION}"
