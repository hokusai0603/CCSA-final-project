# Roadmap & Task List

Agents: take the first unchecked task whose dependencies are done. Each task lists **acceptance criteria** that must be verified by actually running commands. Tick the box only when all criteria pass.

---

## Phase 0 — Repository foundation

- [ ] **P0-1 Makefile & scripts skeleton**
  - Create `Makefile` with the targets listed in `AGENTS.md` §6; each calls a script in `scripts/`.
  - Acceptance: `make help` lists all targets; unimplemented targets exit non-zero with a clear "not implemented yet" message.

- [ ] **P0-2 Local cluster**
  - `scripts/cluster-up.sh` creates the cluster from `deploy/k3d/cluster.yaml`.
  - Acceptance: `kubectl get nodes -L topology.kubernetes.io/zone` shows 1 server + 3 agents with zones `zone-a/b/c`; `make cluster-down` removes it.

- [ ] **P0-3 CI**
  - GitHub Actions workflow: lint + unit tests for each service, and `helm lint` + `helm template` for the chart.
  - Acceptance: workflow passes on the default branch.

## Phase 1 — MVP gameplay (Docker Compose)

- [ ] **P1-1 AI model training** (`services/ai-inference/training/`)
  - Download QuickDraw simplified data for the categories in `categories.txt` (~50), train a small CNN on 28×28 rasters, export `model.onnx`.
  - Acceptance: top-1 validation accuracy ≥ 80 %; ONNX file < 5 MB; a script prints predictions for 5 sample drawings. The model file is published as a release asset or stored via Git LFS — not as a plain git blob.

- [ ] **P1-2 Game server core**
  - WebSocket server implementing the protocol in `architecture.md` §3; rooms, strokes with `seq`, round timer, scoring; Redis keys per §4.
  - Acceptance: unit tests for room logic and protocol validation; two `wscat` clients in one room see each other's strokes.

- [ ] **P1-3 AI worker**
  - Consumer group on `ai:snapshots`, rasterize strokes, ONNX inference, publish `ai_guess`, `XACK`, clear `ai:pending:{room}`, refresh `ai:last_ok`.
  - Acceptance: with a fake stroke list for "cat" in Redis and an enqueued snapshot, an `ai_guess` containing `cat` in the top 3 is published within 1 s.

- [ ] **P1-4 Frontend**
  - Canvas drawing (mouse + touch), join by URL `?room=`, live strokes, AI guesses panel, timer, scores, banner for `ai_status`.
  - Acceptance: two browsers draw together; AI guesses appear; correct guess ends the round.

- [ ] **P1-5 Docker images & Compose**
  - Multi-stage, non-root Dockerfiles for all three services; `docker-compose.yml` with Redis + PostgreSQL.
  - Acceptance: `docker compose up` gives a fully playable game at `http://localhost:8080`; `docker run --rm <image> id -u` is not 0 for every image.

## Phase 2 — Kubernetes

- [ ] **P2-1 Helm chart: stateful services**
  - Redis and PostgreSQL StatefulSets with PVCs, headless Services, Secret for the DB password.
  - Acceptance: delete the postgres pod; after it restarts, previously written scores are still there.

- [ ] **P2-2 Helm chart: app services**
  - Deployments, Services, Ingress (`/` → frontend, `/ws` → game-server), ConfigMap, probes, requests/limits, topology spread, non-root securityContext, `values-dev.yaml` / `values-prod.yaml`.
  - Acceptance: `make build deploy ENV=dev` on a fresh cluster → all pods Ready, game playable through the Ingress; pods of each Deployment are spread across ≥ 2 zones.

- [ ] **P2-3 Multi-replica correctness**
  - Redis Pub/Sub fan-out between pods; room owner lease (§2); reconnect with `lastSeq` replay.
  - Acceptance: with 3 game-server replicas, players forced onto different pods see each other's strokes; deleting the room-owner pod hands the timer to another pod within 3 s.

- [ ] **P2-4 Graceful shutdown**
  - SIGTERM handling per `AGENTS.md` rule 3; `preStop` hook if needed; `terminationGracePeriodSeconds: 30`; `maxUnavailable: 0`.
  - Acceptance: demo scenario 4 passes — rolling update during play leaves `drawguess_rounds_interrupted_total` unchanged.

- [ ] **P2-5 AI degradation**
  - Circuit breaker on `ai:last_ok`, timer pause, `ai_status` messages, `XAUTOCLAIM` of stuck entries.
  - Acceptance: demo scenario 3 passes; killing one of two AI pods mid-round delays guesses by ≤ 3 s.

- [ ] **P2-6 Autoscaling**
  - Install KEDA (`make keda`); HPA for game-server; ScaledObject for ai-inference with `play` and `idle` profiles.
  - Acceptance: `kubectl get hpa,scaledobject` shows both healthy; enqueuing 50 snapshots scales AI pods up, and they scale down after the queue drains.

- [ ] **P2-7 PodDisruptionBudgets**
  - PDBs per `architecture.md` §7.
  - Acceptance: demo scenario 7 passes.

## Phase 3 — Operations & evidence

- [ ] **P3-1 Monitoring stack**
  - `make monitoring` installs kube-prometheus-stack; ServiceMonitors; Grafana dashboard JSON committed in `deploy/monitoring/dashboards/`.
  - Acceptance: dashboard shows all metrics from `architecture.md` §8 with live data.

- [ ] **P3-2 Alerts**
  - PrometheusRules from `goals.md` G5.
  - Acceptance: demo scenario 9 passes.

- [ ] **P3-3 Load test**
  - k6 script in `loadtest/` that joins rooms of 4–6 virtual players who send strokes at a realistic rate.
  - Acceptance: demo scenario 5 passes; k6 summary saved to `loadtest/results/`.

- [ ] **P3-4 Demo scripts**
  - `scripts/demo-1.sh` … `demo-9.sh` + `make demo-<n>`; each prints the measured numbers.
  - Acceptance: all 9 scenarios run end-to-end on a fresh cluster.

- [ ] **P3-5 Results & runbook**
  - Fill the results table in `goals.md`; complete `runbook.md`.
  - Acceptance: every row in the results table has a number and evidence.

## Stretch goals

- [ ] **S-1** HPA on custom metric `drawguess_ws_connections` via prometheus-adapter.
- [ ] **S-2** GitOps with ArgoCD watching this repo.
- [ ] **S-3** Canary releases with Argo Rollouts.
- [ ] **S-4** Loki for centralized logs; OpenTelemetry traces for stroke → guess latency.
- [ ] **S-5** Chaos Mesh experiments (pod kill, network delay) automated.
- [ ] **S-6** Deploy to a small managed cloud cluster with Cloudflare in front (CDN).
