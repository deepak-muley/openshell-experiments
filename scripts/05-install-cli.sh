#!/usr/bin/env bash
# Install the OpenShell CLI at the pinned release.
# Apple Silicon and Linux use the upstream installer.
# Intel macOS has no published CLI build, so this downloads the Linux musl
# binary and scripts/lib.sh runs it with Docker.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

if command -v openshell >/dev/null 2>&1; then
  log "openshell already installed: $(openshell --version 2>/dev/null || openshell version 2>/dev/null || echo present)"
  exit 0
fi

log "installing OpenShell CLI ${OPENSHELL_CLI_VERSION}"
set +e
curl -LsSf https://raw.githubusercontent.com/NVIDIA/OpenShell/main/install.sh | OPENSHELL_VERSION="${OPENSHELL_CLI_VERSION}" sh
install_rc=$?
set -e
if command -v openshell >/dev/null 2>&1; then
  log "installed $(openshell --version 2>/dev/null || true)"
  exit 0
fi

log "native installer did not put openshell on PATH (exit ${install_rc})"
log "downloading the Linux CLI and running it through Docker"
mkdir -p "${STATE}/cli"
asset="openshell-x86_64-unknown-linux-musl.tar.gz"
case "$(uname -m)" in
  arm64|aarch64) asset="openshell-aarch64-unknown-linux-musl.tar.gz" ;;
esac
url="https://github.com/NVIDIA/OpenShell/releases/download/${OPENSHELL_CLI_VERSION}/${asset}"
curl -fsSL -o "${STATE}/cli/openshell.tgz" "${url}"
tar -xzf "${STATE}/cli/openshell.tgz" -C "${STATE}/cli"
chmod 755 "${STATE}/cli/openshell"
oscli --help >/dev/null
log "CLI is ready via Docker ($(cli_mode))"
