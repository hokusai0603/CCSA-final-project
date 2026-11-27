# AGENTS.md — Instructions for coding agents

This file is the entry point for any AI coding agent (Claude Code, Codex, Cursor, etc.) working on this repository. Read it fully before making changes.

## 1. What we are building

**DrawGuess** — a multiplayer collaborative drawing game. Players in a room draw together on a shared canvas; a small AI model (a CNN trained on Google's QuickDraw dataset) guesses the drawing. When the AI guesses the secret word, everyone in the room scores.

This is a **term project for "Cloud Computing and System Architecture" (CCSA)**. The game itself is intentionally small. The point of the project is to **demonstrate Kubernetes management and game operations**: self-healing, zero-downtime updates, autoscaling, observability, and graceful degradation — each one *demonstrable live* and *backed by measured numbers*.

When a trade-off appears between "more game features" and "better operability / demonstrability", choose operability.

## 2. Read these docs first

| Doc | What it contains |
|---|---|
| `docs/architecture.md` | Components, data flow, WebSocket protocol, Redis key layout, K8s resources |
| `docs/goals.md` | The five measurable project goals and their target numbers |
| `docs/demo-scenarios.md` | The live demo script; every feature must support at least one scenario |
| `docs/roadmap.md` | **The task list.** Pick tasks from here, in order |
| `docs/decisions.md` | Architecture decisions and why. Do not contradict these silently |
| `docs/runbook.md` | Operational procedures; keep it updated as features land |
| `docs/host-environment.md` | Risks R1–R6 of running on a shared host, and which task mitigates each |
| `docs/team-plan.md` | Lanes A/B/C, directory ownership, contracts and fakes for parallel work, team rules |

## 3. Fixed technology choices

Do not swap these without adding an entry to `docs/decisions.md` and getting a human's approval.

| Area | Choice |
|---|---|
| Local cluster | **k3d** (k3s in Docker), 1 server + 3 agent nodes, zone labels simulate availability zones. Config: `deploy/k3d/cluster.yaml` |
| Ingress | Traefik (bundled with k3s); WebSocket works without extra config |
| Packaging | One Helm chart: `deploy/helm/drawguess`, with `values-dev.yaml` / `values-prod.yaml` |
| Frontend | TypeScript + Vite, HTML5 Canvas, no heavy framework required; built into static files served by **nginx** (non-root) |
| Game server | **Node.js 24 LTS + TypeScript**, `ws` library for WebSocket, `ioredis` for Redis, `pg` for PostgreSQL, `prom-client` for metrics |
| AI inference | **Python 3.12**, small CNN trained on a QuickDraw subset, exported to **ONNX**, served with **ONNX Runtime (CPU)**. Runs as a queue worker, not an HTTP API |
| Queue | **Redis Streams** (`ai:snapshots`) with a consumer group — no extra broker |
| State | Redis (StatefulSet + PVC) for live room state and Pub/Sub; PostgreSQL (StatefulSet + PVC) for players and scores |
| Autoscaling | HPA for game-server; **KEDA** `ScaledObject` (redis-streams trigger) for ai-inference |
| Monitoring | kube-prometheus-stack (Prometheus + Grafana); Loki is a stretch goal |
| Load testing | **k6** with WebSocket support (`loadtest/`) |

## 4. Repository layout

```
services/frontend/        static web client (canvas, WebSocket client, reconnect logic)
services/game-server/     WebSocket server, room logic, scoring, snapshot enqueueing
services/ai-inference/    queue worker: rasterize strokes -> ONNX model -> publish guesses
services/ai-inference/training/   offline training + ONNX export (not deployed)
services/stub/            placeholder image (probes, metrics, WebSocket, failure knobs) used until real images exist; demo 8's bad release
deploy/k3d/               local multi-node cluster definition
deploy/helm/drawguess/    the Helm chart for all app components + Redis + PostgreSQL
deploy/monitoring/        values for kube-prometheus-stack, Grafana dashboards (JSON)
loadtest/                 k6 scripts simulating players
scripts/                  helper scripts used by the Makefile
docs/                     design docs, roadmap, runbook
```

## 5. Non-negotiable engineering rules

These rules exist because the demo scenarios depend on them.

1. **Game servers are stateless.** All room state lives in Redis. A game-server pod may be killed at any moment; a player reconnecting to another pod must resume with no lost strokes.
2. **Every service exposes**:
   - `GET /healthz` — liveness: process is alive. Must **not** check dependencies.
   - `GET /readyz` — readiness: dependencies reachable (Redis, and model loaded for AI).
   - `GET /metrics` — Prometheus metrics.
3. **Graceful shutdown on SIGTERM**: stop accepting new connections, tell connected clients to reconnect (`{"type":"reconnect"}`), finish in-flight work, exit before `terminationGracePeriodSeconds` (30s).
4. **The game must keep working when the AI is completely down.** Drawing and chat continue; the round timer pauses; the UI shows "AI is busy — timer paused". See `docs/architecture.md` §6.
5. **AI requests are coalesced**: at most one pending snapshot per room; stale snapshots are dropped.
6. **Containers**: multi-stage Dockerfiles, run as non-root, no secrets baked in, image tag = short git SHA (never `latest` in the chart). The chart runs every app pod as **uid/gid 1000** with a **read-only root filesystem** (only `/tmp` is writable) and expects the service on port **8080**; `make build` builds every `services/<name>/Dockerfile` as `drawguess/<name>:<tag>`.
7. **Configuration** via environment variables sourced from ConfigMap/Secret. Never commit real secrets; commit only `*.example` files.
8. **Every Deployment** sets resource `requests` and `limits`, liveness/readiness probes, and `topologySpreadConstraints` on `topology.kubernetes.io/zone`.
9. **Structured JSON logs** to stdout (one object per line, include `room` and `pod` fields where relevant).
10. **Never use the default host ports for local development** (`docs/host-environment.md` R3): Redis `16379`, PostgreSQL `15432`, Grafana `3001`, Compose game `8081`. Tests never flush or drop data they did not create; they use a unique key prefix or database and refuse to run against a non-empty target.
11. **Scripts source `scripts/lib.sh`** and call `kc` / `hc` (kubectl / helm pinned to `k3d-drawguess`), never bare `kubectl` / `helm`. Nothing runs as root (R6). Never map host ports 80, 443 or 6443.
12. **Clean up only what is ours** (R5): `k3d cluster delete`, or Docker filters on `label=k3d.cluster=drawguess`. Never `docker system prune`, `docker rm -f $(docker ps -aq)` or similar global commands; other users share this Docker daemon.

## 6. Standard commands (the Makefile contract)

Agents should create and keep these Makefile targets working. Their implementations live in `scripts/`. A target not implemented yet exits non-zero with `not implemented yet (roadmap task …)`; the task that implements it replaces the stub script.

`make lint` / `make test` discover service projects (`scripts/projects.sh`), and CI (`.github/workflows/ci.yml`) runs exactly these two targets. A new service is covered as soon as it follows the convention; do not edit the workflow per service:

- **Node** (`services/<name>/package.json`): npm scripts `lint` and `test`; commit `package-lock.json` (CI uses `npm ci`).
- **Python** (a `pyproject.toml` under `services/`, at most 3 levels deep): managed by **uv**, `ruff` and `pytest` in the `dev` dependency group; commit `uv.lock` (CI runs with `--locked`).
- **Helm**: `deploy/helm/drawguess/Chart.yaml` is linted and rendered with every `values-*.yaml`.

| Command | Does |
|---|---|
| `make help` | List all targets |
| `make preflight` / `make preflight-measure` | Host checks R1–R6; the `-measure` variant fails on other heavy workloads (run before recording numbers) |
| `make host-sysctl` | Raise inotify limits (sudo, once per host) |
| `make cluster-up` / `make cluster-down` | Create / delete the k3d cluster from `deploy/k3d/cluster.yaml`; `EXPOSE=1` binds the ingress on `0.0.0.0` (live demo only) |
| `make cache-down` | Remove the Docker Hub pull-through cache (kept across `cluster-down` on purpose) |
| `make build` | Build all images tagged with the short git SHA and import them into k3d |
| `make deploy ENV=dev` | `helm upgrade --install` the chart with `values-$(ENV).yaml` |
| `make monitoring` | Install kube-prometheus-stack + dashboards |
| `make keda` | Install KEDA |
| `make lint` | shellcheck, Makefile contract, every service's linter, `helm lint` + `helm template` (CI runs this) |
| `make test` | Unit tests for all services (CI runs this) |
| `make loadtest PLAYERS=200` | Run the k6 scenario against the cluster |
| `make demo-<n>` | Run demo scenario *n* from `docs/demo-scenarios.md` |

## 7. How to work on a task

1. Pick the first unchecked task in `docs/roadmap.md` **in your lane** (`Owner: A/B/C`) whose **Needs** are done. Work against `contracts/` and the fakes (mock WebSocket server, fake AI, dummy model, stub image) instead of waiting for another lane (`docs/team-plan.md`).
2. Read its **Acceptance criteria**. Do only what the task asks.
3. Implement, then verify every acceptance criterion yourself (run the commands; do not assume).
4. Update docs touched by the change (`architecture.md`, `runbook.md`, `decisions.md`).
5. Tick the task's checkbox in `docs/roadmap.md` and note anything a human must know.
6. Commit with a message of the form `phase-N: <task id> <summary>`.

If an acceptance criterion cannot be met (e.g. missing tool, network), stop and report it; do not mark the task done.

## 8. Definition of done (for any task)

- Code builds and unit tests pass (`make test`).
- If the task touches deployment: `make deploy ENV=dev` succeeds on a fresh k3d cluster and all pods become Ready.
- Docs updated; roadmap checkbox ticked.
- No secrets, no `latest` tags, no root containers.
