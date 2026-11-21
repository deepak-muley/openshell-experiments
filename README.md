# OpenShell on Kubernetes

A local lab for running a sandboxed agent on Kubernetes, then taking the same install to another cluster.

The first process you run is a small probe. It has no model and no API key. It writes a file, tries a write the policy rejects, and calls one host that is allowed and one host that is denied. After that, the same gateway can attach Claude, an OpenAI-compatible API, NVIDIA's catalog (Nemotron and others), or an in-cluster Ollama, and it can start a real harness in place of the probe.

## Run it

You need Docker, kind, kubectl, Helm 3, curl, and Python 3.9 or newer. Give Docker about 6 GB of memory. The first run pulls Cilium, the Agent Sandbox controller, and the OpenShell images.

The sandbox runtime needs the node's kernel to be Linux 6.2 or newer with Landlock (`CONFIG_SECURITY_LANDLOCK`). On kind that kernel is Docker's Linux VM. `make sample` checks it and stops with the reason when the VM is older. Apple Silicon and Linux install the OpenShell CLI natively. Intel macOS has no published CLI, so the scripts run the Linux CLI in a container.

```bash
make demo
```

That creates a one-node kind cluster named `openshell`, installs Cilium, checks that NetworkPolicy is enforced, installs OpenShell `0.1.9`, and runs the probe. A passing run prints `SAMPLE_AGENT_RESULT=pass`.

```bash
make down
```

Deletes that kind cluster.

Pins live in [`scripts/versions.env`](scripts/versions.env).

## What each piece is

An agent you would actually use has three layers. This repo keeps them separate so you can swap one without rewriting the others.

| Layer | Job | What this lab uses |
| --- | --- | --- |
| Harness | The loop that plans, calls tools, and keeps memory | The probe, or later Hermes, LangChain Deep Agents, or OpenClaw |
| Runtime | The boundary around that process: filesystem, network, credentials, lifecycle | OpenShell on Kubernetes |
| Model | The system that produces the next action | None for the probe. Then Claude, OpenAI, NVIDIA-hosted open models, or Ollama |

OpenShell is the runtime. It is not a harness and it does not pick a model for you. Hermes, LangChain Deep Agents, and OpenClaw are harnesses. They run *inside* the sandbox. NemoClaw is NVIDIA's reference stack that packages one of those harnesses with OpenShell and a Nemotron-oriented setup. This lab drives OpenShell directly with the `openshell` CLI, which is the same control plane a blueprint would call.

Other OpenShell runtimes exist for a single machine: Docker, Podman, a microVM, and a Windows container. The CLI commands stay the same. Kubernetes is the one that matches a shared cluster and a datacenter.

Read [docs/01-concepts.md](docs/01-concepts.md) before changing anything. The rest of the docs follow the script order.

## Docs

1. [Concepts: harness, runtime, model](docs/01-concepts.md)
2. [Kind cluster and why Cilium is here](docs/02-kind-cluster.md)
3. [Install OpenShell](docs/03-install-openshell.md)
4. [Run the probe sandbox](docs/04-sample-agent.md)
5. [Attach a model](docs/05-models.md)
6. [Put a harness in the sandbox](docs/06-harnesses.md)
7. [Move the same install to another cluster](docs/07-any-cluster.md)
8. [Troubleshooting](docs/08-troubleshooting.md)

## Layout

```text
cluster/                 kind config and Cilium values
deploy/openshell/        Helm values for kind and for a real cluster
deploy/optional/         in-cluster Ollama, not started by make demo
policies/                sandbox filesystem and network policy
providers/               provider profiles for Claude, OpenAI, NVIDIA, Ollama
samples/probe-agent/     the image the sandbox runs
scripts/                 the commands behind the Makefile
```

## Safety

`deploy/openshell/values-kind.yaml` sets `server.auth.allowUnauthenticatedUsers: true`. That is for a gateway you can reach only through a port-forward on your machine. [`values-cluster.yaml`](deploy/openshell/values-cluster.yaml) leaves authentication off until you configure OIDC. Scripts refuse to install into a kubectl context other than `kind-openshell` unless you set `CONFIRM_CLUSTER=1`.
