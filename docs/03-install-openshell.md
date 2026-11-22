# Install OpenShell

The chart deploys the gateway. It does not install the Agent Sandbox controller. Install that first, or the chart's API preflight fails.

```bash
make install
```

`scripts/20-install-openshell.sh` does three things:

1. Apply the Agent Sandbox manifest pinned by `AGENT_SANDBOX_MANIFEST` in `scripts/versions.env`. Upstream's current install is the latest release manifest, which creates the `agent-sandbox-system` namespace, the `sandboxes.agents.x-k8s.io` CRD, and the controller.
2. Create the `openshell` namespace.
3. Install `oci://ghcr.io/nvidia/openshell/helm-chart` at `OPENSHELL_CHART_VERSION` (`0.1.9`).

On the kind context the values file is `deploy/openshell/values-kind.yaml`:

- one replica, StatefulSet, SQLite on a 1Gi volume
- anonymous telemetry off
- `server.auth.allowUnauthenticatedUsers: true`

That auth flag is what lets the CLI talk to a port-forward without an OIDC issuer. Supervisors still use gateway-minted sandbox tokens. Leave the flag false on any cluster another person can reach. `deploy/openshell/values-cluster.yaml` is the starting point for that.

## What comes up

| Object | Role |
| --- | --- |
| StatefulSet `openshell` | Gateway API, policy, credentials, sandbox records |
| Service `openshell` | ClusterIP on port 8080 |
| Secret `openshell-client-tls` | CA and client certificate the CLI uses to verify the gateway |
| ServiceAccount `openshell-sandbox` | Identity used by sandbox pods |

Sandbox pods are created later, in this same namespace, when you run `openshell sandbox create`. The gateway's Kubernetes driver is selected automatically when the gateway runs in a cluster.

## CLI

```bash
make cli
make connect
```

`make cli` runs upstream's installer at `OPENSHELL_CLI_VERSION`. The installer also starts a user-level gateway on your machine (port 17670 on macOS via Homebrew). The lab does not use that gateway for sandboxes.

Apple Silicon and Linux get a native `openshell` binary on `PATH`. Intel macOS does not: NVIDIA publishes no `x86_64-apple-darwin` build, so the installer exits with `Intel macOS is not supported`. `make cli` then downloads `openshell-x86_64-unknown-linux-musl` into `.state/cli/openshell` and the lab runs that binary in a Docker container. Typing `openshell` in your shell still fails. Use the wrapper, which picks the native binary or the container.

`make connect` does not require the current context to be `kind-openshell`. Switch anyway when you want plain `kubectl` and `k get pods -A` to read this lab:

```bash
kubectl config use-context kind-openshell
make connect
./scripts/openshell status
./scripts/openshell sandbox get sample-agent
./scripts/openshell logs sample-agent
./scripts/openshell policy get sample-agent
```

`make connect` copies the in-cluster client bundle to `~/.config/openshell/gateways/kind/mtls`, port-forwards `svc/openshell` to port 18080, and selects that gateway. On Intel macOS the forward listens on `0.0.0.0` and the wrapper registers `https://host.docker.internal:18080`, because `127.0.0.1` inside the container is the container itself. The gateway certificate already includes `host.docker.internal`. Apple Silicon and Linux keep a `127.0.0.1` forward and register `https://127.0.0.1:18080`. The wrapper mounts `~/.config/openshell` and this repo into the container, so gateway config and policy files are the same ones the scripts use.

Keep that port-forward running while you use the CLI. `make connect` records its pid in `.state/port-forward.pid`. `make down` stops it. Docker Desktop has to be running for every `./scripts/openshell` call on Intel macOS.

## Upgrade

Re-run `make install` after you bump `OPENSHELL_CHART_VERSION`. Running sandboxes keep their current supervisor and runtime images until they stop. Restart the gateway after you upgrade the Agent Sandbox controller so it re-reads the served API version.
