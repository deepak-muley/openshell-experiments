#!/usr/bin/env bash
# Start Ollama in this cluster and pull the pinned model.
# make model runs this before it asks the sandbox to call the Service.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

need kubectl
require_lab_context

log "applying in-cluster Ollama"
kube apply -f "${ROOT}/deploy/optional/ollama.yaml"
kube -n models rollout status deploy/ollama --timeout=600s

if kube -n models exec deploy/ollama -- ollama list | awk 'NR>1 {print $1}' | grep -qx "${OLLAMA_MODEL}"; then
  log "model ${OLLAMA_MODEL} already present"
else
  log "pulling ${OLLAMA_MODEL} into the Ollama pod"
  kube -n models exec deploy/ollama -- ollama pull "${OLLAMA_MODEL}"
fi

kube -n models exec deploy/ollama -- ollama list
kube -n models get pods,svc,pvc
log "Ollama is serving ${OLLAMA_MODEL} at http://ollama.models.svc.cluster.local:11434"
