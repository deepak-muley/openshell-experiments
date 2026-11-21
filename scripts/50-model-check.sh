#!/usr/bin/env bash
# Optional. Attach a model provider and run one curl from a sandbox.
#   ANTHROPIC_API_KEY=... make model MODEL=anthropic
#   OPENAI_API_KEY=...    make model MODEL=openai
#   NVIDIA_API_KEY=...    make model MODEL=nvidia
#   make model MODEL=ollama     # after deploy/optional/ollama.yaml is serving a model
set -euo pipefail
source "$(dirname "$0")/lib.sh"

require_cli
require_lab_context

MODEL="${MODEL:-}"
[[ -n "${MODEL}" ]] || die "set MODEL=anthropic|openai|nvidia|ollama"

case "${MODEL}" in
  anthropic)
    profile="${ROOT}/providers/lab-anthropic.yaml"
    provider=lab-anthropic
    [[ -n "${ANTHROPIC_API_KEY:-}" ]] || die "export ANTHROPIC_API_KEY from console.anthropic.com"
    cmd=(sh -c 'curl -fsS --max-time 40 -H "x-api-key: ${ANTHROPIC_API_KEY}" -H "anthropic-version: 2023-06-01" https://api.anthropic.com/v1/models')
    ;;
  openai)
    profile="${ROOT}/providers/lab-openai.yaml"
    provider=lab-openai
    [[ -n "${OPENAI_API_KEY:-}" ]] || die "export OPENAI_API_KEY"
    cmd=(sh -c 'curl -fsS --max-time 40 -H "authorization: Bearer ${OPENAI_API_KEY}" https://api.openai.com/v1/models')
    ;;
  nvidia)
    profile="${ROOT}/providers/lab-nvidia.yaml"
    provider=lab-nvidia
    [[ -n "${NVIDIA_API_KEY:-}" ]] || die "export NVIDIA_API_KEY"
    cmd=(sh -c 'curl -fsS --max-time 40 -H "authorization: Bearer ${NVIDIA_API_KEY}" https://integrate.api.nvidia.com/v1/models')
    ;;
  ollama)
    profile="${ROOT}/providers/lab-ollama.yaml"
    provider=lab-ollama
    cmd=(sh -c 'curl -fsS --max-time 40 http://ollama.models.svc.cluster.local:11434/api/tags')
    ;;
  *)
    die "unknown MODEL=${MODEL}"
    ;;
esac

log "lint and import ${profile}"
lint_profile "${profile}"
import_profile "${profile}" || log "profile import returned non-zero (it may already exist)"

if oscli provider list 2>/dev/null | grep -q "${provider}"; then
  log "provider ${provider} already exists"
else
  if [[ "${MODEL}" == "ollama" ]]; then
    oscli provider create --name "${provider}" --type "${provider}"
  else
    oscli provider create --name "${provider}" --type "${provider}" --from-existing
  fi
fi

name="model-${MODEL}"
log "creating sandbox ${name}"
oscli sandbox create \
  --name "${name}" \
  --from "${SAMPLE_IMAGE}" \
  --policy "${ROOT}/policies/agent-filesystem.yaml" \
  --provider "${provider}" \
  --cpu 1 \
  --memory 1Gi \
  --detach \
  --no-auto-providers \
  -- "${cmd[@]}"

log "follow it with: openshell logs ${name} --tail"
log "effective policy: openshell policy get ${name} --full"
