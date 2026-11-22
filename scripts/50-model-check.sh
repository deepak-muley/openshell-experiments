#!/usr/bin/env bash
# Attach a model provider and run one request from a sandbox.
#   make model                         # in-cluster Ollama, no API key
#   ANTHROPIC_API_KEY=... make model MODEL=anthropic
#   OPENAI_API_KEY=...    make model MODEL=openai
#   NVIDIA_API_KEY=...    make model MODEL=nvidia
set -euo pipefail
source "$(dirname "$0")/lib.sh"

require_cli
require_lab_context
"${ROOT}/scripts/30-connect.sh"

MODEL="${MODEL:-ollama}"

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
    "${ROOT}/scripts/55-ollama-up.sh"
    PROMPT="${PROMPT:-Reply with the single word pong.}"
    # base64 keeps quotes and newlines in the prompt out of the shell quoting.
    prompt_b64="$(printf '%s' "${PROMPT}" | base64 | tr -d '\n')"
    log "prompt: ${PROMPT}"
    # The URL host must match providers/lab-ollama.yaml. A short name will not.
    # /usr/local/bin/python is the binary the profile allows to open that host.
    cmd=(
      /usr/local/bin/python -c
      "import base64,json,urllib.request
prompt=base64.b64decode('${prompt_b64}').decode()
body=json.dumps({'model':'${OLLAMA_MODEL}','prompt':prompt,'stream':False}).encode()
req=urllib.request.Request('http://ollama.models.svc.cluster.local:11434/api/generate',data=body,headers={'Content-Type':'application/json'})
with urllib.request.urlopen(req,timeout=180) as resp:
    data=json.load(resp)
print(data.get('response',''),flush=True)
print('OLLAMA_RESULT=pass',flush=True)"
    )
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

if ! docker image inspect "${SAMPLE_IMAGE}" >/dev/null 2>&1; then
  log "building ${SAMPLE_IMAGE}"
  docker build -t "${SAMPLE_IMAGE}" "${ROOT}/samples/probe-agent"
fi
if [[ "$(lab_context)" == "kind-${CLUSTER_NAME}" ]]; then
  log "loading ${SAMPLE_IMAGE} into the kind node"
  kind load docker-image "${SAMPLE_IMAGE}" --name "${CLUSTER_NAME}"
fi

if [[ "${MODEL}" == "ollama" ]]; then
  "${ROOT}/scripts/12-check-kernel.sh"
fi

name="model-${MODEL}"
oscli sandbox delete "${name}" --yes >/dev/null 2>&1 || oscli sandbox delete "${name}" >/dev/null 2>&1 || true
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

log "follow it with: ./scripts/openshell logs ${name}"
log "effective policy: ./scripts/openshell policy get ${name} --full"

if [[ "${MODEL}" == "ollama" ]]; then
  logfile="${STATE}/model-ollama.log"
  log "waiting for the Ollama reply"
  found=""
  for _ in $(seq 1 40); do
    oscli logs "${name}" >"${logfile}" 2>&1 &
    pid=$!
    for _ in $(seq 1 15); do
      if grep -q 'OLLAMA_RESULT=' "${logfile}" 2>/dev/null; then
        kill "${pid}" 2>/dev/null || true
        wait "${pid}" 2>/dev/null || true
        found=1
        break
      fi
      if ! kill -0 "${pid}" 2>/dev/null; then
        wait "${pid}" 2>/dev/null || true
        break
      fi
      sleep 1
    done
    kill "${pid}" 2>/dev/null || true
    wait "${pid}" 2>/dev/null || true
    if [[ "${found}" == "1" ]]; then
      break
    fi
    sleep 3
  done
  if [[ -f "${logfile}" ]]; then
    cat "${logfile}"
  fi
  if grep -q 'OLLAMA_RESULT=pass' "${logfile}" 2>/dev/null; then
    log "sandbox reached Ollama and ${OLLAMA_MODEL} answered"
  else
    kube -n "${NAMESPACE}" get pods,sandboxes || true
    die "the sandbox did not report OLLAMA_RESULT=pass. Read ${logfile}"
  fi
fi
