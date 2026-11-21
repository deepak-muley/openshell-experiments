# Any Kubernetes cluster

The kind cluster is a stand-in. The gateway chart, the Agent Sandbox controller, the CLI, the policy files, and the provider profiles are the same objects you install elsewhere. What changes is the cluster around them.

## Checklist

| Requirement | Kind lab | Datacenter cluster |
| --- | --- | --- |
| Kubernetes | 1.29+ from kind | 1.29+ with RBAC |
| CNI | Cilium, checked by `scripts/11-verify-netpol.sh` | A CNI that enforces ingress and egress NetworkPolicy. Run the same script with `CONFIRM_CLUSTER=1` |
| Storage | local-path as default | A block StorageClass. Set `server.dataStorageClass` and `server.workspaceStorageClass` if there is no default |
| Agent Sandbox | applied before Helm | same manifest, or your internal mirror of it |
| OpenShell chart | `values-kind.yaml` | `values-cluster.yaml`, then OIDC |
| Auth | unauthenticated, port-forward only | `allowUnauthenticatedUsers: false`, OIDC or your access proxy |
| Workload image | `kind load` of a local tag | A registry the nodes can pull. Image pull secrets go in `server.sandboxImagePullSecrets` |
| GPU | none | `--gpu` on `sandbox create` requests `nvidia.com/gpu` when the device plugin is installed |

## Install

Point kubectl at the cluster and confirm you mean it. The scripts will not install into a random context.

```bash
export CONFIRM_CLUSTER=1
export OPENSHELL_VALUES=deploy/openshell/values-cluster.yaml
./scripts/11-verify-netpol.sh
./scripts/20-install-openshell.sh
./scripts/30-connect.sh
```

Then build the probe for the node's architecture and push it:

```bash
export SAMPLE_IMAGE=registry.example.com/team/openshell-sample-agent:0.1.0
export PUSH_IMAGE=1
docker build --platform linux/amd64 -t "${SAMPLE_IMAGE}" samples/probe-agent
./scripts/40-run-sample.sh
```

Drop `--platform linux/amd64` when the nodes are arm64. kind on Apple Silicon is arm64, so `make sample` with no platform flag matches that node. A typical datacenter node does not.

## Authentication

`values-cluster.yaml` does not open the gateway. Follow OpenShell's access-control docs to set an OIDC issuer and client id, then register the CLI with those flags instead of relying on the kind values:

```bash
openshell gateway add https://openshell.example.com --name prod \
  --oidc-issuer https://idp.example.com/realms/openshell \
  --oidc-client-id openshell-cli
```

Put the issuer in the Helm values you already use for that environment. Keep provider credentials in the gateway database or, if you want them as Kubernetes Secrets, enable `server.credentialDrivers.kubernetesSecrets` in a dedicated namespace. The chart's Role for that driver can read and write every Secret in the namespace you give it, so do not point it at the release namespace on a shared cluster.

## Egress

Sandbox egress is still the supervisor's job. The pod NetworkPolicy denies direct egress. On a network that can only leave through a corporate proxy, set `upstreamProxy` in the Helm values. The proxy URL is operator config. A process inside the sandbox cannot replace it. The kind lab has direct egress, which is why the probe can reach `example.com` once policy allows it.

## What you do not redo

You do not rewrite the probe, the policy, or the provider profiles when you change clusters. You do not run a second OpenShell controller. You create sandboxes against the gateway in that cluster, with `openshell gateway select` choosing which gateway the CLI talks to.

If several teams share one gateway, install the gateway chart with `workspaceResources.enabled=false` and the `openshell-workspace` chart in each sandbox namespace. The kind lab keeps the default shared namespace because there is one user.
