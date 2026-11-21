# Models

The probe proves the sandbox with no model. A real harness needs somewhere to send a completion request. OpenShell keeps that decision in a provider profile: which host, which binaries, and which credential. You attach the provider to the sandboxes that should have it.

Older OpenShell builds had a gateway-wide `openshell inference set` route and a virtual `inference.local` host. That route is gone. Clients call the provider's normal URL and send the real model name. The gateway injects the credential on the way out.

Profiles in this repo are lab copies with the probe image's binaries added (`/usr/bin/curl` and `/usr/local/bin/python`). Lint one before you import it. `scripts/50-model-check.sh` does that.

| You have | Command |
| --- | --- |
| `ANTHROPIC_API_KEY` from console.anthropic.com | `make model MODEL=anthropic` |
| `OPENAI_API_KEY` | `make model MODEL=openai` |
| `NVIDIA_API_KEY` | `make model MODEL=nvidia` |
| Ollama applied from `deploy/optional/ollama.yaml` | `make model MODEL=ollama` |

`ANTHROPIC_API_KEY` is an API key. A Claude subscription token is a different credential and will not work here.

The model check builds nothing new. It reuses the probe image and runs `curl` against the provider, with the filesystem policy in `policies/agent-filesystem.yaml`. The provider profile supplies the network rule and the credential placeholder. Watch it with:

```bash
openshell logs model-anthropic
openshell policy get model-anthropic --full
```

`--full` shows the provider-derived network rules next to the filesystem policy. A global policy override would hide those rules. This lab does not set one.

## Claude, OpenAI, NVIDIA

The three hosted profiles differ by host and by how the key is sent.

- Anthropic: header `x-api-key` to `api.anthropic.com`
- OpenAI: bearer `authorization` to `api.openai.com`
- NVIDIA catalog: bearer `authorization` to `integrate.api.nvidia.com`

Nemotron models are requested by id in the body, for example `nvidia/nemotron-3-super-120b-a12b`, against the NVIDIA host. OpenShell does not choose or rewrite that id. The same pattern works for any other model that host serves.

A curl that lists models:

```bash
# inside the sandbox, after --provider lab-nvidia
curl -fsS \
  -H "authorization: Bearer ${NVIDIA_API_KEY}" \
  https://integrate.api.nvidia.com/v1/models
```

`${NVIDIA_API_KEY}` inside the sandbox is a placeholder. The supervisor replaces it when the profile authorizes that host. Pointing the same variable at a different host does not take the secret with it.

## An open model in the cluster

`deploy/optional/ollama.yaml` is a Deployment and Service, `ollama.models.svc.cluster.local:11434`. It is optional because the image is large and you still have to pull a model:

```bash
kubectl apply -f deploy/optional/ollama.yaml
kubectl -n models rollout status deploy/ollama
kubectl -n models exec deploy/ollama -- ollama pull qwen2.5:0.5b
make model MODEL=ollama
```

`providers/lab-ollama.yaml` has an empty credential list. The host string has to be the host the client dials. If you call `http://ollama.models:11434` and the profile says `ollama.models.svc.cluster.local`, the rule will not match.

For vLLM, TGI, or another OpenAI-compatible server, copy `providers/lab-ollama.yaml` or `providers/lab-openai.yaml` and set `host` to that service. Give the new file its own `id`. Importing it as `openai` would describe the wrong host.

## Where `host.openshell.internal` fits

Docker and microVM drivers can reach a model on the gateway host through `host.openshell.internal`. The Kubernetes driver does that only when `server.hostGatewayIP` is set, which adds a host alias to sandbox pods. Prefer a Service inside the cluster. It moves to a datacenter cluster without a special route back to your laptop.
