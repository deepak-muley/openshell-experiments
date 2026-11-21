# Kind cluster

OpenShell on Kubernetes requires a CNI that enforces `NetworkPolicy` for ingress and egress. The gateway creates those policies. Kubernetes will store them even when the CNI ignores them, and a sandbox pod can then open connections on its own.

kind's built-in CNI is kindnet. It does not enforce NetworkPolicy. `scripts/10-kind-up.sh` creates the cluster with `networking.disableDefaultCNI: true` and installs Cilium from `cluster/cilium-values.yaml`. kube-proxy stays. Cilium's policy enforcement is what the lab needs.

The cluster is one control-plane node, named `openshell`. The kubectl context is `kind-openshell`.

## Storage

The gateway StatefulSet stores its SQLite database on a PVC. Each sandbox gets a PVC at `/sandbox`. That volume has to be block storage on the node. Do not point the gateway database at NFS.

kind 0.27 and newer already installs a local-path StorageClass (named `standard` on current kind) and marks it default. `scripts/10-kind-up.sh` uses that class. It installs Rancher's local-path-provisioner only when the cluster has no default StorageClass. Two default classes at once make PVCs sit Pending.

## The enforcement check

Before OpenShell is installed, `scripts/11-verify-netpol.sh` starts two curl pods:

- `openshell-netpol-check` has a default-deny egress policy. The pod must fail.
- `default` has no policy. The pod must reach `https://example.com`.

If the deny pod succeeds, the script stops. Installing OpenShell on that cluster would look healthy and would not actually fence the sandbox.

The check deletes both pods when it finishes.

## Create it yourself

```bash
make prereqs
make kind
kubectl --context kind-openshell get nodes
kubectl --context kind-openshell -n kube-system get pods -l k8s-app=cilium
```

Nodes stay `NotReady` until Cilium is up. That is expected.

To pin the Kubernetes version, set `KIND_NODE_IMAGE` in `scripts/versions.env` to a `kindest/node` image. OpenShell wants Kubernetes 1.29 or newer. An empty value uses whatever your kind binary defaults to.

## Kernel

OpenShell 0.1.9's sandbox runtime probes Landlock and exits unless it finds ABI v3. That is Linux 6.2 or newer with `CONFIG_SECURITY_LANDLOCK=y`. kind shares the Docker VM kernel, so a new Kubernetes node image does not change it. `scripts/12-check-kernel.sh` reads `/proc/config.gz` inside the kind node and reports the gap. The gateway still installs. Sandbox pods do not stay up until the VM kernel qualifies.

## Tear it down

```bash
make down
```

This deletes the kind cluster named `openshell` and the local port-forward. It does not touch any other kubeconfig context's cluster.
