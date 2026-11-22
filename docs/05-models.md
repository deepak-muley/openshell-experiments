# Models

The probe proves the sandbox with no model. A real harness needs somewhere to send a completion request. OpenShell keeps that decision in a provider profile: which host, which binaries, and which credential. You attach the provider to the sandboxes that should have it.

Older OpenShell builds had a gateway-wide `openshell inference set` route and a virtual `inference.local` host. That route is gone. Clients call the provider's normal URL and send the real model name. The gateway injects the credential on the way out.

Profiles in this repo are lab copies with the probe image's binaries added (`/usr/bin/curl` and `/usr/local/bin/python`). Lint one before you import it. `scripts/50-model-check.sh` does that.

| You have | Command |
| --- | --- |
| `ANTHROPIC_API_KEY` from console.anthropic.com | `make model MODEL=anthropic` |
| `OPENAI_API_KEY` | `make model MODEL=openai` |
| `NVIDIA_API_KEY` | `make model MODEL=nvidia` |
| Nothing. Ollama runs in this cluster | `make model` |

`ANTHROPIC_API_KEY` is an API key. A Claude subscription token is a different credential and will not work here.

A hosted NVIDIA check, after the gateway is selected:

```bash
kubectl config use-context kind-openshell
export NVIDIA_API_KEY=...
make connect
make model MODEL=nvidia
./scripts/openshell logs model-nvidia
./scripts/openshell policy get model-nvidia --full
./scripts/openshell sandbox get model-nvidia
```

Use `ANTHROPIC_API_KEY` with `MODEL=anthropic`, or `OPENAI_API_KEY` with `MODEL=openai`. The sandbox name follows the model: `model-anthropic`, `model-openai`, `model-nvidia`.

The model check builds nothing new. It reuses the probe image and runs `curl` against the provider, with the filesystem policy in `policies/agent-filesystem.yaml`. The provider profile supplies the network rule and the credential placeholder. `kubectl get pods -A` still has no model pod after this. The completion request goes to the provider's host.

Watch a hosted check with the CLI wrapper. Swap the name for `model-openai`, `model-nvidia`, or `model-ollama`:

```bash
kubectl config use-context kind-openshell
make connect
./scripts/openshell logs model-nvidia
./scripts/openshell policy get model-nvidia --full
./scripts/openshell sandbox get model-nvidia
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

## Ollama in this cluster

`make model` is the free path. It applies `deploy/optional/ollama.yaml`, waits for the pod, pulls `qwen2.5:0.5b` (override with `OLLAMA_MODEL`), and creates sandbox `model-ollama`. That process curls `http://ollama.models.svc.cluster.local:11434/api/generate`. The weights stay on PVC `ollama` in the `models` namespace, so the next run does not download them again.

```bash
kubectl config use-context kind-openshell
make model
kubectl -n models get pods,svc,pvc
./scripts/openshell logs model-ollama
./scripts/openshell policy get model-ollama --full
./scripts/openshell sandbox get model-ollama
```

A passing run prints the model's reply and then `OLLAMA_RESULT=pass`. `kubectl -n models get pods` is the model process. The pod name starts with `ollama-`. `make ollama` starts the Service and stops before the sandbox.

The default prompt is `Reply with the single word pong.` Set `PROMPT` to send a different one. Each run deletes sandbox `model-ollama` and creates it again, so the log is the new prompt.

```bash
PROMPT='What is 2+2? Answer with the number only.' make model
./scripts/openshell logs model-ollama
```

```bash
PROMPT='Name three Kubernetes objects in one sentence.' make model
./scripts/openshell logs model-ollama
```

`PROMPT` is the text Ollama receives. It is not a harness plan, and it does not change the probe from `make demo`. Quotes and newlines are fine. The sandbox still needs a kernel with Landlock before this command can create `model-ollama`.

The Ollama pod does not need Landlock. The sandbox that calls it does. On a Docker Desktop VM older than Linux 6.2, `make model` still leaves Ollama running and then stops with the kernel error before it creates `model-ollama`. Upgrade the Docker VM, then run `make model` again. The weights are already on the PVC.

`providers/lab-ollama.yaml` has an empty credential list. The host string has to be the host the client dials. If you call `http://ollama.models:11434` and the profile says `ollama.models.svc.cluster.local`, the rule will not match.

For vLLM, TGI, or another OpenAI-compatible server, copy `providers/lab-ollama.yaml` or `providers/lab-openai.yaml` and set `host` to that service. Give the new file its own `id`. Importing it as `openai` would describe the wrong host.

## Where `host.openshell.internal` fits

Docker and microVM drivers can reach a model on the gateway host through `host.openshell.internal`. The Kubernetes driver does that only when `server.hostGatewayIP` is set, which adds a host alias to sandbox pods. Prefer a Service inside the cluster. It moves to a datacenter cluster without a special route back to your laptop.
