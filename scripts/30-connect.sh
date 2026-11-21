#!/usr/bin/env bash
# Port-forward the gateway and register it with the OpenShell CLI.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

need kubectl
PYTHON="$(python_bin)"
require_cli
require_lab_context

log "copying the gateway client bundle"
bundle="${HOME}/.config/openshell/gateways/${GATEWAY_NAME}/mtls"
mkdir -p "${bundle}"
chmod 700 "${HOME}/.config/openshell" "${HOME}/.config/openshell/gateways" "${HOME}/.config/openshell/gateways/${GATEWAY_NAME}" "${bundle}"

"${PYTHON}" - "${NAMESPACE}" "${bundle}" <<'PY'
import base64, json, pathlib, subprocess, sys
namespace, dest = sys.argv[1], pathlib.Path(sys.argv[2])
raw = subprocess.check_output([
    "kubectl", "-n", namespace, "get", "secret", "openshell-client-tls", "-o", "json",
])
data = json.loads(raw)["data"]
for key, filename in (("ca.crt", "ca.crt"), ("tls.crt", "tls.crt"), ("tls.key", "tls.key")):
    path = dest / filename
    path.write_bytes(base64.b64decode(data[key]))
    path.chmod(0o600)
PY

pidfile="${STATE}/port-forward.pid"
if [[ -f "${pidfile}" ]] && kill -0 "$(cat "${pidfile}")" 2>/dev/null; then
  log "port-forward already running (pid $(cat "${pidfile}"))"
else
  bind="$(port_forward_address)"
  log "port-forward ${bind}:${GATEWAY_PORT} -> svc/openshell:8080"
  # Detach from this shell so the forward keeps running after the script exits.
  "${PYTHON}" - "${pidfile}" "${STATE}/port-forward.log" "${NAMESPACE}" "${bind}" "${GATEWAY_PORT}" <<'PY'
import os, subprocess, sys
pidfile, logpath, namespace, bind, port = sys.argv[1:]
if os.fork() > 0:
    os._exit(0)
os.setsid()
if os.fork() > 0:
    os._exit(0)
log = open(logpath, "ab", buffering=0)
proc = subprocess.Popen(
    ["kubectl", "-n", namespace, "port-forward", "--address", bind,
     "svc/openshell", f"{port}:8080"],
    stdin=subprocess.DEVNULL,
    stdout=log,
    stderr=subprocess.STDOUT,
    start_new_session=True,
)
open(pidfile, "w").write(str(proc.pid))
PY
  sleep 1
  kill -0 "$(cat "${pidfile}")" 2>/dev/null || {
    cat "${STATE}/port-forward.log" >&2 || true
    die "port-forward exited. See ${STATE}/port-forward.log"
  }
fi

url="$(gateway_url)"
if oscli gateway list 2>/dev/null | grep -q "${GATEWAY_NAME}"; then
  log "selecting existing gateway ${GATEWAY_NAME}"
  oscli gateway select "${GATEWAY_NAME}"
else
  log "registering ${url} as ${GATEWAY_NAME}"
  oscli gateway add "${url}" --local --name "${GATEWAY_NAME}"
  oscli gateway select "${GATEWAY_NAME}"
fi

oscli status
log "CLI is pointed at the in-cluster gateway"
