.PHONY: help prereqs cli kind install connect sample ollama model demo down status

help:
	@printf '%s\n' \
	  'make demo     create kind, install OpenShell, run the probe sandbox' \
	  'make cli      install the pinned OpenShell CLI' \
	  'make kind     create the Cilium kind cluster' \
	  'make install  install Agent Sandbox and the OpenShell chart' \
	  'make connect  port-forward the gateway and select it in the CLI' \
	  'make sample   build the probe image and create the sandbox' \
	  'make ollama   start in-cluster Ollama and pull the pinned model' \
	  'make model    call a model from a sandbox (default MODEL=ollama)' \
	  'make status   show gateway and sandbox objects' \
	  'make down     delete the kind cluster'

demo: prereqs cli kind install connect sample

prereqs:
	./scripts/00-prereqs.sh

cli:
	./scripts/05-install-cli.sh

kind:
	./scripts/10-kind-up.sh

install:
	./scripts/20-install-openshell.sh

connect:
	./scripts/30-connect.sh

sample:
	./scripts/40-run-sample.sh

ollama:
	./scripts/55-ollama-up.sh

model:
	./scripts/50-model-check.sh

status:
	kubectl --context kind-openshell -n openshell get pods,sandboxes,svc,pvc,networkpolicy

down:
	./scripts/90-down.sh
