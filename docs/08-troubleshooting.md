# Troubleshooting

## Nodes stay NotReady

Cilium is not running yet, or it never became Ready. `kubectl -n kube-system get pods -l k8s-app=cilium` and `kubectl -n kube-system logs ds/cilium`. A kind cluster created without `disableDefaultCNI` will fight Cilium. Delete it with `make down` and create it again with this repo's `cluster/kind.yaml`.

## The NetworkPolicy check says policy is not enforced

The deny pod reached `example.com`. Stop. OpenShell's sandbox NetworkPolicies will not fence anything on this CNI. On kind, that means Cilium is not the CNI. On another cluster, ask the platform team which CNI is installed before you install the chart.

## The open pod also fails

Both curls failed, so the check cannot tell enforcement from a broken route. Confirm the node can pull `curlimages/curl` and that the cluster has a working default route. Corporate networks that block `example.com` need a different URL in `scripts/11-verify-netpol.sh` and in `policies/sample-agent.yaml`.

## Gateway pod Pending

The PVC is waiting for a StorageClass. `kubectl get sc` should show `local-path` with `(default)` on kind. On another cluster set `server.dataStorageClass` before the first install. Changing it later does not resize or move the existing claim.

## Helm preflight fails on Agent Sandbox

The CRD or the controller is missing. Re-run `make install`. The chart does not install that controller. If you are rendering templates offline, the upstream flag is `agentSandbox.preflight.enabled=false`. Leave preflight on for a real install.

## `openshell gateway add` cannot verify TLS

`make connect` writes `~/.config/openshell/gateways/kind/mtls/{ca.crt,tls.crt,tls.key}` from Secret `openshell-client-tls`. Re-run `make connect` after a reinstall. The port-forward has to be alive, and the URL has to be `https://127.0.0.1:18080`.

## CLI talks to the laptop gateway

The installer starts a local gateway and may select it. `openshell gateway list` then `openshell gateway select kind`. `openshell status` should show the port-forward address, not port 17670.

## Sandbox stays Pending

`kubectl -n openshell describe pod` on the new pod. Common causes:

- Image pull. On kind, `make sample` must `kind load` the tag before create. `docker exec openshell-control-plane crictl images | grep sample-agent` shows whether the node has it.
- Workspace PVC Pending. Same StorageClass issue as the gateway.
- Landlock or seccomp rejected by the node kernel. The supervisor log has the reason: `kubectl -n openshell logs -l openshell.ai/component=supervisor --tail=100`.

## The workload pod logs `Landlock ABI probe`

OpenShell 0.1.9 stops the sandbox runtime unless the node kernel provides Landlock ABI v3. That is Linux 6.2 or newer, built with `CONFIG_SECURITY_LANDLOCK=y`. `landlock.compatibility: best_effort` in the policy file does not skip this probe.

```text
Error: Landlock ABI probe
Landlock ABI v3 or newer (Linux 6.2+) is required, but Landlock is not
implemented (kernel lacks CONFIG_SECURITY_LANDLOCK)
```

On kind, that kernel is the Docker VM, not a kernel packed in the node image:

```bash
docker exec openshell-control-plane uname -r
docker exec openshell-control-plane sh -c 'zcat /proc/config.gz | grep LANDLOCK'
```

`make sample` runs the same check first. A linuxkit 5.15 kernel without Landlock, which is what older Docker Desktop builds ship, cannot run the probe. Upgrade Docker Desktop so its Linux VM is 6.2 or newer, or use a datacenter node that already is. Ubuntu 24.04 kernels qualify. The gateway, Cilium, and the NetworkPolicy check do not need Landlock and can still be installed.

## `allow_example.com` fails and `deny_example.org` passes

The deny side is doing its job. The allow side is a policy or trust problem. `openshell policy get sample-agent` should list `example.com` for `/usr/bin/curl`. Certificate errors in the curl stderr mean the workload does not trust the supervisor's intercept CA. Check the supervisor log for the proxy error before you widen the policy.

## `allow_example.com` and `deny_example.org` both succeed

The process reached a host that policy does not name. The pod NetworkPolicy is not enforced, or the traffic is not going through the supervisor. Re-run `make kind`'s check. Do not treat this cluster as a sandbox.

## Provider create says the profile is missing

Import is explicit. `make model MODEL=anthropic` lints and imports `providers/lab-anthropic.yaml`. A fresh gateway has no built-in profiles. `openshell provider profile` is the v0.1.9 command. Newer CLIs moved it to `openshell profile`. The scripts accept either.

## Model curl returns 401

The sandbox reached the host, which means policy allowed it. The credential placeholder was not replaced, or the key itself is wrong. `openshell sandbox provider list <name>` should show the provider. Create it with `--from-existing` while the matching environment variable is set in that shell. An Anthropic subscription token will not pass as `ANTHROPIC_API_KEY`.

## Chart version and CLI version drift

Keep `OPENSHELL_CHART_VERSION` and `OPENSHELL_CLI_VERSION` on the same release. A CLI that is a development build ahead of the chart will offer subcommands the gateway does not implement yet.
