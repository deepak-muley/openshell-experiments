#!/usr/bin/env bash
# Shared helpers. Source this; do not execute it.
if [[ -n "${__OPENSHELL_LAB_LIB:-}" ]]; then
  return 0
fi
__OPENSHELL_LAB_LIB=1

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/scripts/versions.env"

STATE="${ROOT}/.state"
mkdir -p "${STATE}"

log() { printf '==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

need() {
  local cmd="$1"
  local hint="${2:-}"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    die "missing '${cmd}'. ${hint}"
  fi
}

# Prefer a working interpreter. Some machines have a broken python3 earlier on PATH.
python_bin() {
  local candidate
  for candidate in python3.13 python3.12 python3.11 python3.10 python3; do
    if command -v "${candidate}" >/dev/null 2>&1 \
      && "${candidate}" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 9) else 1)' >/dev/null 2>&1; then
      command -v "${candidate}"
      return 0
    fi
  done
  die "need Python 3.9 or newer. python3 on PATH is missing or too old."
}

# Cluster these scripts talk to. The default is kind-${CLUSTER_NAME}, which
# does not follow kubectl's current context. CONFIRM_CLUSTER=1 selects the
# current context for a cluster that is not this kind lab.
lab_context() {
  if [[ "${CONFIRM_CLUSTER:-}" == "1" ]]; then
    kubectl config current-context
    return
  fi
  printf 'kind-%s\n' "${CLUSTER_NAME}"
}

kube_context() { lab_context; }

require_lab_context() {
  local ctx
  ctx="$(lab_context)"
  if [[ "${CONFIRM_CLUSTER:-}" == "1" ]]; then
    log "CONFIRM_CLUSTER=1, using context ${ctx}"
  fi
  # Do not pipe this into grep -q. grep exits at the first match, kubectl
  # dies with SIGPIPE, and pipefail then reports the context as missing.
  if ! kubectl config get-contexts "${ctx}" >/dev/null 2>&1; then
    die "kubectl context '${ctx}' is missing. Create the cluster with: make kind"
  fi
}

kube() {
  kubectl --context "$(lab_context)" "$@"
}

# native: openshell is on PATH (Apple Silicon and Linux release assets).
# docker: Intel macOS has no published CLI, so the Linux musl binary runs in a container.
cli_mode() {
  if command -v openshell >/dev/null 2>&1; then
    printf 'native\n'
  elif [[ -x "${STATE}/cli/openshell" ]]; then
    printf 'docker\n'
  else
    printf 'missing\n'
  fi
}

require_cli() {
  [[ "$(cli_mode)" != "missing" ]] || die "OpenShell CLI is missing. Run: make cli"
}

gateway_url() {
  if [[ "$(cli_mode)" == "docker" ]]; then
    printf 'https://host.docker.internal:%s\n' "${GATEWAY_PORT}"
  else
    printf 'https://127.0.0.1:%s\n' "${GATEWAY_PORT}"
  fi
}

port_forward_address() {
  if [[ "$(cli_mode)" == "docker" ]]; then
    # The CLI container reaches the host by name. 127.0.0.1 is not that path.
    printf '0.0.0.0\n'
  else
    printf '127.0.0.1\n'
  fi
}

cli_docker_platform() {
  case "$(uname -m)" in
    arm64|aarch64) printf 'linux/arm64\n' ;;
    *) printf 'linux/amd64\n' ;;
  esac
}

# Prefer an image already on the machine so a lab run does not wait on a registry pull.
cli_docker_image() {
  if [[ -n "${OPENSHELL_CLI_IMAGE:-}" ]]; then
    printf '%s\n' "${OPENSHELL_CLI_IMAGE}"
    return
  fi
  local candidate
  for candidate in alpine:3.20 alpine:3.14.0 alpine:3.14; do
    if docker image inspect "${candidate}" >/dev/null 2>&1; then
      printf '%s\n' "${candidate}"
      return
    fi
  done
  printf 'alpine:3.20\n'
}

oscli() {
  require_cli
  if [[ "$(cli_mode)" == "native" ]]; then
    command openshell "$@"
    return
  fi
  mkdir -p "${HOME}/.config/openshell"
  docker run --rm \
    --platform "$(cli_docker_platform)" \
    -v "${HOME}/.config/openshell:/root/.config/openshell" \
    -v "${ROOT}:${ROOT}" \
    -v "${STATE}/cli/openshell:/usr/local/bin/openshell:ro" \
    -w "${ROOT}" \
    -e HOME=/root \
    "$(cli_docker_image)" \
    openshell "$@"
}

# v0.1.9 exposes 'openshell provider profile'. Newer builds expose 'openshell profile'.
profile_bin() {
  if oscli provider profile --help >/dev/null 2>&1; then
    printf '%s\n' "provider profile"
    return 0
  fi
  if oscli profile --help >/dev/null 2>&1; then
    printf '%s\n' "profile"
    return 0
  fi
  die "this openshell CLI has neither 'provider profile' nor 'profile'. Install ${OPENSHELL_CLI_VERSION}."
}

lint_profile() {
  local file="$1"
  local sub
  sub="$(profile_bin)"
  # shellcheck disable=SC2086
  oscli ${sub} lint -f "${file}"
}

import_profile() {
  local file="$1"
  local sub
  sub="$(profile_bin)"
  # shellcheck disable=SC2086
  if oscli ${sub} import --help 2>&1 | grep -q -- '--global'; then
    # shellcheck disable=SC2086
    oscli ${sub} import -f "${file}" --global
  else
    # shellcheck disable=SC2086
    oscli ${sub} import -f "${file}"
  fi
}
