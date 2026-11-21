# Harnesses

Once the probe sandbox is boring, replace the process. The gateway, the policy file, and the provider stay. The image and the command change.

A harness image has to contain its own CLI and the CA store the language runtime uses. OpenShell adds the sandbox runtime and the trust bundle; it does not install Hermes, Deep Agents, or OpenClaw for you. Build that image, push it to a registry the cluster can pull, and create a sandbox with the harness command as the main process.

The filesystem baseline is `policies/agent-filesystem.yaml`. Attach a provider from [05-models.md](05-models.md) so the harness binary is allowed to call the model and so the API key stays in the gateway. The profile `binaries` list has to include the harness executable path inside *that* image. The lab profiles list `curl` and the probe's Python. Add the harness path before you import, or write a new profile id.

## Hermes Agent

Hermes, from Nous Research, is a harness that keeps skills as you correct it. NemoClaw's Hermes blueprint starts it with `hermes gateway run` behind OpenShell's proxy and writes a managed config at startup. On this cluster you do the same job with the CLI:

```bash
openshell sandbox create \
  --name hermes \
  --from registry.example.com/team/hermes-agent:1.0 \
  --policy policies/agent-filesystem.yaml \
  --provider lab-nvidia \
  --cpu 2 \
  --memory 4Gi \
  --detach \
  --no-auto-providers \
  -- hermes gateway run
```

Use the command your image actually expects. If the binary is `/usr/local/bin/hermes`, that path belongs in the provider profile. Interactive use is `openshell sandbox exec -n hermes --tty -- /bin/bash` or an attach, depending on whether the main process is the agent itself.

## LangChain Deep Agents

Deep Agents Code is the terminal coding harness. The NemoClaw blueprint calls it `dcode`, with `dcode -n` for a headless turn, and writes config under `/sandbox/.deepagents`. `/sandbox` is already the writable workspace on Kubernetes, so that state lands on the PVC and survives a pod restart.

```bash
openshell sandbox create \
  --name deepagents \
  --from registry.example.com/team/deepagents:1.0 \
  --policy policies/agent-filesystem.yaml \
  --provider lab-anthropic \
  --cpu 2 \
  --memory 4Gi \
  --detach \
  --no-auto-providers \
  -- dcode
```

The provider profile has to name the `dcode` binary, not only `curl`, when `dcode` is the process that opens the TLS connection.

## OpenClaw

OpenClaw is the default harness in NemoClaw's blueprints: files, tools, subagents, and a long-lived session. Treat it like the others. The image contains OpenClaw, the main process is OpenClaw's server or gateway command, and the provider profile lists that Node (or other) binary.

```bash
openshell sandbox create \
  --name openclaw \
  --from registry.example.com/team/openclaw:1.0 \
  --policy policies/agent-filesystem.yaml \
  --provider lab-nvidia \
  --cpu 2 \
  --memory 4Gi \
  --detach \
  --no-auto-providers \
  -- openclaw
```

Confirm the real entrypoint from the image you built. A wrong command still creates a sandbox; it just exits, and the sandbox record shows the main process failed.

## What NemoClaw adds when you want it

NemoClaw's CLI (`nemoclaw`, or `nemo-deepagents` for the Deep Agents path) is a host-side installer. It knows the image, the startup wrapper, the default policy, and the inference wiring for each supported harness. That is useful when you want NVIDIA's tested combination. It is optional. OpenShell will run a harness image you built yourself, which is the path this lab teaches, because that path is the one you repeat on a datacenter cluster: same chart, same CLI, your registry.

## Credentials, again

Do not bake `ANTHROPIC_API_KEY` or `NVIDIA_API_KEY` into the harness image or into a Kubernetes Secret mounted by the workload. Create the provider from your shell so the gateway stores the key, and attach it with `--provider`. The process environment receives a placeholder. The supervisor adds the real header only when the request matches the profile.

```bash
openshell provider list
openshell sandbox provider list hermes
openshell policy get hermes --full
```

A new process picks up a provider attached after the sandbox started. A process that is already running keeps the environment it was given. Start a new exec after `openshell sandbox provider attach`.
