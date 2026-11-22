# Look around a running cluster

`kind get clusters` lists every kind cluster on the machine. This lab is the one named `openshell`. Its kubectl context is `kind-openshell`. Other clusters (`global-chat`, `gpu-sharing`, `kc-demo`, and anything else kind created) are untouched.

Your shell's current context may be one of those other clusters. `make connect` and the other lab targets pass `--context kind-openshell` themselves. Switch the current context when you want `kubectl get pods -A` to list this lab:

```bash
kind get clusters
kubectl config current-context
kubectl config use-context kind-openshell
kubectl get pods -A
```

`kubectl get pods -A` shows Cilium, CoreDNS, the Agent Sandbox controller, local-path, and `openshell-0`. The probe has no model. `make model` adds an `ollama-` pod in the `models` namespace. [05-models.md](05-models.md) is that command.

Then point the CLI at the gateway and read the probe:

```bash
make connect
./scripts/openshell status
./scripts/openshell sandbox get sample-agent
./scripts/openshell logs sample-agent
./scripts/openshell policy get sample-agent
```

`make status` is the short form of the namespace listing below.

## The node and the CNI

```bash
kubectl --context kind-openshell get nodes -o wide
kubectl --context kind-openshell -n kube-system get pods -l k8s-app=cilium
```

The node name is `openshell-control-plane`. `KERNEL-VERSION` is Docker's Linux VM, which is the kernel the sandbox runtime probes for Landlock. OpenShell 0.1.9 wants 6.2 or newer. Cilium is the CNI that enforces the NetworkPolicies the gateway creates. One Ready `cilium-*` pod on this one-node cluster is the healthy picture.

## The controller that turns a Sandbox into a pod

```bash
kubectl --context kind-openshell get crd sandboxes.agents.x-k8s.io
kubectl --context kind-openshell -n agent-sandbox-system get deploy,pods
```

`sandboxes.agents.x-k8s.io` is the Agent Sandbox API. The deployment `agent-sandbox-controller` in `agent-sandbox-system` is what creates the workload pod from that object. OpenShell does not ship this controller. `make install` applies it before the Helm chart.

## The gateway

```bash
kubectl --context kind-openshell -n openshell get statefulset,pods,svc,pvc
kubectl --context kind-openshell -n openshell get secret openshell-client-tls
```

| Object | What it is |
| --- | --- |
| StatefulSet `openshell`, pod `openshell-0` | The gateway, image `ghcr.io/nvidia/openshell/gateway:0.1.9` |
| Service `openshell` | ClusterIP, port 8080. `make connect` port-forwards this to `127.0.0.1:18080` |
| Service `openshell-peer` | Headless service for the gateway |
| PVC `openshell-data-openshell-0` | SQLite database, 1Gi, StorageClass `standard` |
| Secret `openshell-client-tls` | CA and client certificate the CLI uses |

## The probe sandbox

The CLI name is `sample-agent`. Kubernetes names the object `default--sample-agent` because the workspace is `default`.

```bash
kubectl --context kind-openshell -n openshell get sandboxes
kubectl --context kind-openshell -n openshell get sandbox default--sample-agent \
  -o custom-columns='NAME:.metadata.name,MODE:.spec.operatingMode,REASON:.status.conditions[0].reason,MSG:.status.conditions[0].message'
kubectl --context kind-openshell -n openshell get pvc,svc,networkpolicy
```

After the probe process exits, the Sandbox stays and its mode becomes `Suspended` with reason `PodTerminated`. The workload pod and the supervisor pod are gone. These objects remain:

| Object | What it is |
| --- | --- |
| Sandbox `default--sample-agent` | The record. Annotations `openshell.ai/sandbox-name=sample-agent` and `openshell.ai/sandbox-id` tie it to the CLI name |
| PVC `workspace-default--sample-agent` | The `/sandbox` volume, including `report.json` |
| Services `os-boundary-<id>` and `os-supervisor-<id>` | The channel between the workload and the supervisor. Selector label `openshell.ai/boundary-pair=<id>` |
| NetworkPolicies `openshell-sandbox-workloads`, `openshell-sandbox-supervisors`, `os-control-<id>` | Cilium enforces these. The workload pod cannot open its own egress |

To see the two pods while they exist, start the probe again and list pods from another terminal before it exits:

```bash
make sample
```

```bash
kubectl --context kind-openshell -n openshell get pods --show-labels
kubectl --context kind-openshell -n openshell get pods -l openshell.ai/boundary-role=workload
kubectl --context kind-openshell -n openshell get pods -l openshell.ai/boundary-role=supervisor
```

The workload pod runs `openshell-sample-agent:0.1.0` and is labeled `openshell.ai/boundary-role=workload`. The supervisor pod is the trusted side of the same pair. Its logs are where a Landlock or policy denial shows up:

```bash
kubectl --context kind-openshell -n openshell logs -l openshell.ai/component=supervisor --tail=100
```

## The same objects through the CLI

`make connect` has to be running so the CLI can reach the gateway. The installer also starts a gateway on your laptop (port 17670). Select `kind` so the commands below hit this cluster.

```bash
kubectl config use-context kind-openshell
make connect
./scripts/openshell gateway list
./scripts/openshell gateway select kind
./scripts/openshell status
./scripts/openshell sandbox get sample-agent
./scripts/openshell logs sample-agent
./scripts/openshell policy get sample-agent
```

`./scripts/openshell` is the native CLI on Apple Silicon and Linux. On Intel macOS it is the Linux binary from `make cli`, run in Docker. [03-install-openshell.md](03-install-openshell.md) has that setup.

`sandbox get` is the CLI view of Sandbox `default--sample-agent`. `policy get` prints the filesystem and network rules from `policies/sample-agent.yaml`. `logs` is the probe output. A finished run ends with `SAMPLE_AGENT_RESULT=pass` or `SAMPLE_AGENT_RESULT=fail`. The script also saves that log at `.state/sample-agent.log`.
