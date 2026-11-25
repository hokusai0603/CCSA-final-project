# DrawGuess — the Makefile contract (AGENTS.md §6). Every target calls a script in scripts/.
# Unimplemented targets exit 2 with "not implemented yet (roadmap task …)".

SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

ENV     ?= dev
PLAYERS ?= 200
EXPOSE  ?= 0

.PHONY: help tools preflight preflight-measure host-sysctl \
        cluster-up cluster-down cache-down build stub-image deploy monitoring keda lint test loadtest \
        demo-1 demo-2 demo-3 demo-4 demo-5 demo-6 demo-7 demo-8 demo-9

help: ## List all targets
	@awk 'BEGIN { FS = ":.*## " } \
	     /^##@ / { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } \
	     /^[a-zA-Z0-9_-]+:.*## / { printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@echo
	@echo "  Variables: ENV=$(ENV) (dev|prod)  PLAYERS=$(PLAYERS)  EXPOSE=$(EXPOSE) (0|1)"

##@ Host
tools: ## Install the pinned CLI toolchain into ~/.local/bin (docs/dev-setup.md)
	@scripts/install-tools.sh

preflight: ## Check tools, host limits, ports and image-pull quota (docs/host-environment.md)
	@scripts/preflight.sh

preflight-measure: ## Same, but other heavy workloads are failures (run before recording numbers)
	@scripts/preflight.sh --measure

host-sysctl: ## Raise inotify limits for k3d (asks for sudo; once per host)
	sudo scripts/host-sysctl.sh

##@ Cluster
cluster-up: ## Create the k3d cluster (EXPOSE=1 binds ingress on 0.0.0.0 for the live demo)
	@EXPOSE=$(EXPOSE) scripts/cluster-up.sh

cluster-down: ## Delete the k3d cluster (keeps the image cache)
	@scripts/cluster-down.sh

cache-down: ## Remove the Docker Hub pull-through cache and its volume
	@scripts/cache-down.sh

build: ## Build all images (tag = short git SHA) and import them into k3d
	@scripts/build.sh

stub-image: ## Build the placeholder service image (services/stub) and import it into k3d
	@scripts/stub-image.sh

deploy: ## helm upgrade --install with values-$(ENV).yaml
	@scripts/deploy.sh $(ENV)

monitoring: ## Install kube-prometheus-stack + Grafana dashboards
	@scripts/monitoring.sh

keda: ## Install KEDA
	@scripts/keda.sh

##@ Verify
lint: ## Static checks: shellcheck, Makefile contract, service linters, helm lint/template (same as CI)
	@scripts/lint.sh

test: ## Unit tests for all services (same as CI)
	@scripts/test.sh

loadtest: ## Run the k6 scenario with $(PLAYERS) simulated players
	@scripts/loadtest.sh $(PLAYERS)

##@ Demo scenarios (docs/demo-scenarios.md)
demo-1: ## One-command deploy on a fresh cluster (G1)
	@scripts/demo.sh 1
demo-2: ## Kill a game-server pod (G2)
	@scripts/demo.sh 2
demo-3: ## AI outage, graceful degradation (G2)
	@scripts/demo.sh 3
demo-4: ## Rolling update during play (G3)
	@scripts/demo.sh 4
demo-5: ## Load test, HPA scale-out/in (G4)
	@scripts/demo.sh 5
demo-6: ## AI scale from zero with KEDA (G4)
	@scripts/demo.sh 6
demo-7: ## Node drain with PDBs (G3)
	@scripts/demo.sh 7
demo-8: ## Bad release + helm rollback (G1)
	@scripts/demo.sh 8
demo-9: ## Alerting: AIUnavailable fires < 60 s (G5)
	@scripts/demo.sh 9
