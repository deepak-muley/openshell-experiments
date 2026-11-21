# The probe sandbox

`samples/probe-agent` is the working example. It is a normal container. OpenShell is what turns it into a sandbox.

```bash
make sample
```

The script builds `docker.io/library/openshell-sample-agent:0.1.0`, loads it into the kind node, and creates a detached sandbox:

```bash
openshell sandbox create \
  --name sample-agent \
  --from docker.io/library/openshell-sample-agent:0.1.0 \
  --policy policies/sample-agent.yaml \
  --cpu 1 \
  --memory 1Gi \
  --detach \
  --no-auto-providers \
  -- /usr/local/bin/python /opt/sample-agent/agent.py
```

`--detach` matters on Kubernetes. The driver runs the process in a pod; the CLI returns once the workload is ready and you read output with `openshell logs`.

## What the process does

`agent.py` records four checks:

| Check | Expected | Why |
| --- | --- | --- |
| `write_/sandbox` | pass | `/sandbox` is the workspace PVC and it is in `read_write` |
| `deny_write_/etc` | pass | `/etc` is read-only. The runtime does not start at all unless the node kernel has Landlock ABI v3, so this check only runs on a kernel that can enforce it |
| `allow_example.com` | pass | `network_policies.example_com` allows `/usr/bin/curl` to GET `example.com:443` |
| `deny_example.org` | pass | no rule names `example.org`, so the supervisor denies it |

The last line is `SAMPLE_AGENT_RESULT=pass` or `SAMPLE_AGENT_RESULT=fail`. The script stores the log in `.state/sample-agent.log` and exits non-zero on `fail`.

The policy file is `policies/sample-agent.yaml`. The network rule names `/usr/bin/curl` because the probe shells out to that path. A Python HTTP client would be a different binary (`/usr/local/bin/python`) and would be denied until you add it. That is the control you want: the executable, the host, the port, and the HTTP access level are all part of the rule.

`access: read-only` with `protocol: rest` allows GET, HEAD, and OPTIONS. The probe only GETs. `enforcement: enforce` makes the supervisor inspect the request rather than tunneling it blindly.

## What you should see in the cluster

After create, the `openshell` namespace gains a `Sandbox`, a workload pod, a supervisor pod, a Service for the boundary, a workspace PVC, and NetworkPolicies. Useful commands:

```bash
kubectl --context kind-openshell -n openshell get pods,sandboxes,pvc,networkpolicy
openshell sandbox get sample-agent
openshell logs sample-agent
openshell policy get sample-agent
```

The workspace file `/sandbox/report.json` holds the same four checks. It lives on the PVC for the life of that sandbox record.

## Again

`make sample` deletes a previous `sample-agent` sandbox and creates a new one. The image is rebuilt every time so edits to `agent.py` show up. `kind load` is what makes the node see a local tag. A datacenter cluster cannot load from your Docker daemon; push the image and set `SAMPLE_IMAGE`. That path is in [07-any-cluster.md](07-any-cluster.md).
