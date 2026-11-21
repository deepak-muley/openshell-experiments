#!/usr/bin/env bash
# OpenShell 0.1.9 refuses to start a sandbox unless the node kernel has
# Landlock ABI v3: Linux 6.2 or newer, built with CONFIG_SECURITY_LANDLOCK.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

node="${CLUSTER_NAME}-control-plane"
if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "${node}"; then
  log "kernel check skipped (no kind node named ${node}). The cluster still needs Linux 6.2+ with CONFIG_SECURITY_LANDLOCK."
  exit 0
fi

kver="$(docker exec "${node}" uname -r)"
cfg="$(docker exec "${node}" sh -c 'zcat /proc/config.gz 2>/dev/null || true')"
major="${kver%%.*}"
rest="${kver#*.}"
minor="${rest%%.*}"

log "kind node kernel ${kver}"
if ! grep -q '^CONFIG_SECURITY_LANDLOCK=y' <<<"${cfg}"; then
  die "kernel ${kver} was built without CONFIG_SECURITY_LANDLOCK. OpenShell 0.1.9 will not start a sandbox on it. Docker Desktop's Linux VM has to be 6.2 or newer with Landlock enabled. A current Ubuntu node in a datacenter usually is."
fi
if (( major < 6 || (major == 6 && minor < 2) )); then
  die "kernel ${kver} is older than 6.2. OpenShell 0.1.9 requires Landlock ABI v3."
fi
log "Landlock ABI v3 is available on this kernel"
