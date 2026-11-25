# Roadmap & Task List

Three people work in parallel **lanes**: **A** game-server, **B** AI + frontend, **C** platform. Roles, directory ownership and team rules: `docs/team-plan.md`.

How to pick work (people and agents): take the first unchecked task **in your lane** whose **Needs** are done. A dependency on another lane is satisfied by the fakes from Phase 0.5 (contracts, mock WebSocket server, fake AI, dummy model, stub image), not by waiting for the real component. Each task lists **acceptance criteria** that must be verified by actually running commands. Tick the box only when all criteria pass.

Cross-cutting items are tagged inside the tasks that own them:

- **R1–R6** host-environment risks, see `docs/host-environment.md`.
- **D1–D12** demo pitfalls: designs or defaults that would make a demo scenario fail or mismeasure.

| # | Pitfall | Demo | Owner tasks |
|---|---|---|---|
| D1 | PDB `minAvailable` = min replicas blocks drain; cordoned zone keeps pods `Pending` | 7 | P2-2, P2-7 |
| D2 | Per-IP `/ws` rate limit throttles k6 (one source IP) | 5 | P2-2, P3-3 |
| D3 | HPA scale-in waits 300 s by default | 5 | P2-6a |
| D4 | KEDA `pollingInterval` 30 s dominates cold start | 6 | P2-6b |
| D5 | Strokes drawn while disconnected are lost or duplicated | 2 | P1-4, P2-3 |
| D6 | A killed pod cannot count its own interrupted round | 4 | P2-4 |
| D7 | Default scrape/eval intervals make a < 60 s alert impossible | 9 | P3-1 |
| D8 | KEDA `pendingEntriesCount` counts only delivered-but-unacked entries (≤ number of workers), so it never sees a backlog; use the stream **lag** | 6, 5 | P2-6b |
| D9 | Pods on a dead node are evicted only after `tolerationSeconds` 300 s (default), so replacements start 5+ min late | 10 | P2-2 |
| D10 | A snapshot that crashes workers is reclaimed by the next worker and crashes it too (poison message cascade) | 3 | P1-2, P2-5b |
| D11 | All clients of dead pods reconnect at once and overload the survivors (thundering herd) | 2, 10 | P1-4 |
| D12 | ONNX Runtime uses every CPU core by default, so extra AI replicas add no throughput | 5, 6 | P1-3, P2-6b |

---

## Phase 0 — Repository foundation

- [x] **P0-1 Makefile & scripts skeleton** · Owner: C
  - Create `Makefile` with the targets listed in `AGENTS.md` §6; each calls a script in `scripts/`.
  - Acceptance: `make help` lists all targets; unimplemented targets exit non-zero with a clear "not implemented yet" message.
  - Done: stubs exit 2 and name the task that implements them. Also added `scripts/lib.sh` (root guard, `kc`/`hc` pinned to `k3d-drawguess`), `make preflight` / `preflight-measure` (checks for R1–R6, `docs/host-environment.md`), `make host-sysctl`, `.nvmrc` (Node 24).
  - Human note: on a new host run `make preflight` first; if inotify FAILs, run `make host-sysctl` (sudo).

- [x] **P0-2 Local cluster** · Owner: C
  - `scripts/cluster-up.sh` creates the cluster from `deploy/k3d/cluster.yaml`.
  - Host safeguards (`docs/host-environment.md`):
    - R6: API server on `127.0.0.1:6550`; TLS on 8443, never host 80/443/6443.
    - R6: pin the k3s image in `cluster.yaml` to a version within ±1 minor of the documented kubectl (k3d's default k3s 1.35 vs kubectl 1.37 is out of skew policy).
    - R5: ingress on `127.0.0.1:8080` by default; `make cluster-up EXPOSE=1` binds `0.0.0.0` for the live demo.
    - R2: configure a registry mirror (pull-through cache) via k3d `registries`, so recreated clusters do not pull from Docker Hub again.
    - `cluster-up` runs `scripts/preflight.sh` first and aborts on FAIL.
  - Acceptance: `kubectl get nodes -L topology.kubernetes.io/zone` shows 1 server + 3 agents with zones `zone-a/b/c`; `make cluster-down` removes it; `ss -ltn` shows 6550 and 8080 bound to 127.0.0.1 only; a second `cluster-down` / `cluster-up` cycle pulls system images from the mirror, not from Docker Hub.
  - Done: k3s pinned to `v1.37.2-k3s1`; cache registry `k3d-drawguess-cache` (`registry:2.8.3`, `127.0.0.1:5005`, volume `drawguess-registry-cache`) is created by `cluster-up`, kept by `cluster-down`, removed by `make cache-down`. Measured: cycle 1 the cache received 407 MB from upstream; cycle 2 it received 241 KB while serving 132 blob requests (cache size unchanged at 190 MB). Cluster ready in ~45 s.
  - Human note: the Docker Hub quota shown by `preflight` did not drop in cycle 1 because `rancher/*` images are exempt from the anonymous limit; application base images (node, nginx, python, redis, postgres) do count, and the cache absorbs them too. `EXPOSE=1` was verified reachable from the LAN address and unreachable again after recreating without it.

- [x] **P0-3 CI** · Owner: C
  - GitHub Actions workflow: lint + unit tests for each service, and `helm lint` + `helm template` for the chart.
  - Acceptance: workflow passes on the default branch.
  - Done: `.github/workflows/ci.yml` runs `make lint` + `make test`, which discover service projects and the chart (`scripts/projects.sh`, convention in `AGENTS.md` §6). First green run: commit `d5edfc8` on `main`. With no services yet, CI covers shellcheck, the Makefile contract and `make help`; the service, Helm and dashboard branches were verified locally on a fixture copy (all pass; 10 injected faults each fail the run).
  - Human note: the setup-uv warning "No file matched … uv.lock" is expected until the first Python service commits `uv.lock`. `astral-sh/setup-uv` has no floating major tag, so it is pinned by commit SHA; bump it by hand.

- [x] **P0-4 Developer setup (Linux + Windows/WSL2)** · Owner: C
  - `make tools` installs the pinned toolchain; `.gitattributes` forces LF; preflight checks CRLF, RAM and WSL pitfalls; `docs/dev-setup.md`.
  - Acceptance: `make tools` on a fresh `$HOME` installs all 7 tools with checksums; a re-run skips them; preflight FAILs on an injected CRLF script.
  - Done: verified on Linux. Human note: the WSL2 steps are untested; the Windows teammate runs `make preflight` on first setup and reports anything it flags.

- [x] **P0-5 Stub service image** (`services/stub`) · Owner: C
  - Placeholder image with probes, §8 metric names, WebSocket echo, graceful shutdown and failure knobs (`READY_DELAY_MS`, `FAIL_READY`, `CRASH_AFTER_MS`, `/burn`), so chart, autoscaling, monitoring and demo work can start before the real services (see `services/stub/README.md`).
  - Acceptance: `make test` runs its unit tests; the image runs as non-root; on k3d it spreads across zones, drains WebSocket clients on pod delete, blocks a `FAIL_READY=1` rollout, crash-loops with `CRASH_AFTER_MS`, and scales an HPA with `/burn`.
  - Done: all verified on k3d (numbers in the stub README).

## Phase 0.5 — Contracts and fakes (all three, first 1–2 days)

After this phase nobody waits for another lane: every lane develops against the contracts and the fakes, then swaps in the real component. Tools under `tools/` follow the same lint/test convention as services; P0.5-2 adds `tools/*` to `scripts/projects.sh` discovery.

- [ ] **P0.5-1 Contracts** (`contracts/`) · Owner: A (leads), with B and C
  - Machine-checkable versions of `architecture.md` §3–§4 and §8:
    - `ws-protocol.schema.json`: every client→server and server→client message, including the stroke `cid` (D5);
    - `ai-stream.schema.json`: the `ai:snapshots` entry `{room, round, seq}` and the `ai_guess` payload;
    - `model.md`: the ONNX input/output contract (input name, shape `[1,1,28,28]` float32, normalization, output = 50 scores in `categories.txt` order);
    - `services.md`: per service, the env vars, port, `/healthz` `/readyz` `/metrics` behaviour and metric names;
    - `fixtures/*.jsonl`: example sessions (join, strokes, reconnect with `lastSeq`, `ai_guess`, `ai_status`, `round_end`).
  - Rule: changing anything in `contracts/` needs the other two lanes' approval (`docs/team-plan.md`).
  - Acceptance: `make lint` validates every fixture against its schema and fails on an invalid one.

- [ ] **P0.5-2 Mock WebSocket server** (`tools/mock-ws/`) · Owner: B · Needs: P0.5-1
  - Small Node server that speaks the contract protocol: rooms, stroke broadcast with `seq`, `lastSeq` replay, a round timer, a fake `ai_guess` every few seconds, and an admin endpoint that sends `reconnect` to all clients (simulates a pod shutdown).
  - Used by: the frontend (P1-4) and k6 (P3-3) until the real game-server is ready.
  - Acceptance: two `wscat` clients in one room see each other's strokes; every message it sends validates against `ws-protocol.schema.json` in its unit tests.

- [ ] **P0.5-3 Fake AI worker** (`tools/fake-ai/`) · Owner: A · Needs: P0.5-1
  - Reads `ai:snapshots` in group `ai-workers`, publishes a random `ai_guess` (the secret word with probability `P_CORRECT`), `XACK`s, clears `ai:pending:{room}`, refreshes `ai:last_ok`. Modes via env: `ok`, `slow` (delay), `down` (stops refreshing `ai:last_ok`).
  - Used by: game-server development (P1-2, P2-5a) until the real worker is ready.
  - Acceptance: an enqueued snapshot produces a valid `ai_guess` within 1 s; in `down` mode `ai:last_ok` expires.

- [ ] **P0.5-4 Dummy ONNX model** · Owner: B · Needs: P0.5-1
  - Script that writes a random-weight `model.onnx` satisfying `contracts/model.md`.
  - Used by: the AI worker (P1-3) until training (P1-1) produces the real model. The real model must pass the same contract test.
  - Acceptance: ONNX Runtime loads it and returns 50 scores for a 28×28 input.

- Cancelled: per-user cluster names/ports. Everyone develops on their own machine, so there is no shared Docker daemon (`docs/team-plan.md`).

## Phase 1 — MVP gameplay (Docker Compose)

Every service project follows the lint/test convention in `AGENTS.md` §6 (npm `lint` + `test` scripts, or uv + ruff + pytest), so `make lint`, `make test` and CI pick it up automatically. Each service's tests include **contract tests**: its inputs and outputs validate against `contracts/`.

- [ ] **P1-1 AI model training** (`services/ai-inference/training/`) · Owner: B · Needs: P0.5-1
  - Download QuickDraw simplified data for the categories in `categories.txt` (~50), train a small CNN on 28×28 rasters, export `model.onnx`.
  - Acceptance: top-1 validation accuracy ≥ 80 %; ONNX file < 5 MB; passes the `contracts/model.md` test; a script prints predictions for 5 sample drawings. The model file is published as a release asset or stored via Git LFS — not as a plain git blob.

- [ ] **P1-2 Game server core** · Owner: A · Needs: P0.5-1, P0.5-3
  - WebSocket server implementing the protocol in `architecture.md` §3; rooms, strokes with `seq`, round timer, scoring; Redis keys per §4.
  - R3: default local config uses Redis `16379` / PostgreSQL `15432` (never 6379/5432); test helpers use a unique key prefix and refuse to run against a non-empty Redis/database they did not create.
  - Demo pitfall (D10): cap strokes per round and points per stroke (reject beyond the cap), so no snapshot can grow without bound and crash the AI.
  - Lesson from the stub (P0-5): keep CPU-heavy work off the event loop, or probes fail under load.
  - Acceptance: unit tests for room logic and protocol validation; contract tests pass; two `wscat` clients in one room see each other's strokes.

- [ ] **P1-3 AI worker** · Owner: B · Needs: P0.5-1, P0.5-4
  - Consumer group on `ai:snapshots`, rasterize strokes, ONNX inference, publish `ai_guess`, `XACK`, clear `ai:pending:{room}`, refresh `ai:last_ok`.
  - R3: same port and test-isolation rules as P1-2.
  - Demo pitfall (D12): create the ONNX Runtime session with `intra_op_num_threads=1` (configurable), so each replica uses one core and throughput grows with replicas.
  - Acceptance: with a fake stroke list for "cat" in Redis and an enqueued snapshot, an `ai_guess` containing `cat` in the top 3 is published within 1 s (with the real model; with the dummy model: a valid `ai_guess` within 1 s).

- [ ] **P1-4 Frontend** · Owner: B · Needs: P0.5-1, P0.5-2
  - Canvas drawing (mouse + touch), join by URL `?room=`, live strokes, AI guesses panel, timer, scores, banner for `ai_status`. Develop against the mock WebSocket server; switch to the real game-server at IC1.
  - Demo pitfall (D5, "0 lost strokes"): `lastSeq` replay only restores strokes the server already has. Strokes the player draws **while disconnected** must be queued in the client and resent after reconnect, each with a client stroke id `cid` so the server can drop duplicates (P2-3).
  - Demo pitfall (D11): reconnect with exponential backoff plus random jitter (e.g. 250 ms base, ×2, cap 5 s, ±50 %), so the clients of a dead pod do not all hit the survivors in the same instant.
  - Acceptance: two browsers draw together; AI guesses appear; correct guess ends the round; after the mock's `reconnect`, strokes drawn while disconnected appear once.

- [ ] **P1-5 Docker images & Compose** · Owner: C (compose, review) · each service owner writes their Dockerfile · Needs: P0-5
  - Multi-stage, non-root Dockerfiles for all three services; `docker-compose.yml` with Redis + PostgreSQL. Start the compose file with stub images; swap in each real image as it lands.
  - R3: Compose serves the game on **8081** (so it can run next to k3d on 8080) and does not publish Redis/PostgreSQL, or publishes them only as `127.0.0.1:16379` / `127.0.0.1:15432`.
  - Acceptance: `docker compose up` gives a fully playable game at `http://localhost:8081`; `docker run --rm <image> id -u` is not 0 for every image.

**IC1 — integration checkpoint:** Compose runs the real game-server, AI worker and frontend; a full round can be played. Not blocking: lanes keep using fakes for parts that are not real yet.

## Phase 2 — Kubernetes

- [ ] **P2-1 Helm chart: stateful services** · Owner: C · Needs: —
  - Redis and PostgreSQL StatefulSets with PVCs, headless Services, Secret for the DB password.
  - Acceptance: delete the postgres pod; after it restarts, previously written scores are still there.

- [ ] **P2-2 Helm chart: app services** · Owner: C · Needs: P0-5 (stub image), P2-1
  - Deployments, Services, Ingress (`/` → frontend, `/ws` → game-server), ConfigMap, probes, requests/limits, topology spread, non-root securityContext, `values-dev.yaml` / `values-prod.yaml`. Start with the stub image for every component; switch per component as real images land.
  - Demo pitfall (D1, demo 7): topology spread constraints set `nodeTaintsPolicy: Honor`. Otherwise a cordoned node's zone still counts as a domain with 0 pods, and with `DoNotSchedule` the evicted pod stays `Pending`.
  - Demo pitfall (D2, demo 5): the `/ws` rate limit is a values setting (`ingress.rateLimit`), so the load test can raise it (P3-3).
  - Demo pitfall (D9, demo 10): game-server and ai-inference tolerate `node.kubernetes.io/not-ready` and `node.kubernetes.io/unreachable` for **15 s** (values setting), not the default 300 s, so pods on a dead node are replaced in about a minute.
  - Lessons from the stub on k3d (P0-5):
    - A Node service that blocks its event loop under load (synchronous CPU work) fails its probes: pods turn unready (503 at the Ingress) and liveness restarts them. Keep CPU work off the main thread. Give liveness `timeoutSeconds` ≥ 2 and `failureThreshold` ≥ 3, so load alone does not restart pods.
    - Traefik starts routing to a newly Ready pod a few seconds after `rollout status` returns. Count that lag in G2's "pod Ready" vs "players back" numbers.
  - Acceptance: `make build deploy ENV=dev` on a fresh cluster → all pods Ready, game playable through the Ingress; pods of each Deployment are spread across ≥ 2 zones.

- [ ] **P2-3 Multi-replica correctness** · Owner: A · Needs: P1-2
  - Redis Pub/Sub fan-out between pods; room owner lease (§2); reconnect with `lastSeq` replay.
  - Demo pitfall (D5): the server drops strokes whose `cid` it has already seen in the room (e.g. a Redis set with the room TTL); `cid` is already in `contracts/ws-protocol.schema.json`.
  - Acceptance: with 3 game-server replicas, players forced onto different pods see each other's strokes; deleting the room-owner pod hands the timer to another pod within 3 s; strokes drawn during a forced disconnect appear **exactly once** for every player.

- [ ] **P2-4 Graceful shutdown** · Owner: A · Needs: P1-2
  - SIGTERM handling per `AGENTS.md` rule 3; `preStop` hook if needed; `terminationGracePeriodSeconds: 30`; `maxUnavailable: 0`.
  - Demo pitfall (D6): a pod cannot count its own death, and its counter disappears with it. `drawguess_rounds_interrupted_total` must be incremented by a **surviving** pod: e.g. the pod that takes over a room's owner lease and finds the timer stalled longer than lease timeout + 2 s, or the round state lost. Demo 4 also checks it from the client side: every `round_start` seen by the probe client has a matching `round_end`.
  - Acceptance: demo scenario 4 passes — rolling update during play leaves `drawguess_rounds_interrupted_total` unchanged; **negative test**: scaling game-server to 0 for 10 s mid-round increases it (proves the metric can see an interruption).

- [ ] **P2-5a AI degradation: game-server side** · Owner: A · Needs: P1-2, P0.5-3
  - Circuit breaker on `ai:last_ok`, timer pause, `ai_status` messages. Develop against the fake AI's `down` mode.
  - Acceptance: with the fake AI in `down` mode, `ai_status {available:false}` is broadcast within 6 s, the timer pauses, drawing and chat keep working; when it recovers, the timer resumes.

- [ ] **P2-5b AI degradation: worker side** · Owner: B · Needs: P1-3
  - `XAUTOCLAIM` of entries idle > 3 s.
  - Demo pitfall (D10): before processing a claimed entry, check its delivery count (`XPENDING`). Past 2 deliveries, move it to the `ai:dead` stream and `XACK` it, so one bad snapshot cannot take down every worker in turn. Set a memory limit so a bad input kills one pod, not the node.
  - Acceptance: demo scenario 3 passes (with P2-5a); killing one of two AI pods mid-round delays guesses by ≤ 3 s; an injected snapshot that crashes the worker ends up in `ai:dead` after 2 attempts while other rooms keep getting guesses.

- [ ] **P2-6a game-server HPA** · Owner: C · Needs: P2-2
  - HPA on CPU for game-server (stub `/burn` drives it before the real server exists).
  - Demo pitfall (D3, demo 5): HPA waits 300 s by default before scaling in. Make `behavior.scaleDown.stabilizationWindowSeconds` a values setting (demo: 60 s).
  - Acceptance: `kubectl get hpa` healthy; load scales out and, after it stops, back in within the configured window.

- [ ] **P2-6b AI autoscaling with KEDA** · Owner: B · Needs: P2-1, P1-3 · Design: ADR-008
  - Install KEDA (`make keda`); ScaledObject for ai-inference with `play` (min 2) and `idle` (min 0) profiles, max 6.
  - Two triggers, KEDA takes the higher (ADR-008):
    - **active rooms** (proactive): `ceil(rooms / R) + 1` replicas, i.e. the live capacity plus one spare (N+1). Source: a game-server endpoint with the global room count (`metrics-api` scaler), or Prometheus once P3-1 is in.
    - **stream lag** (reactive safety net): `ceil(lag / 5)`.
  - Demo pitfall (D8): use the redis-streams scaler's lag metric (`lagCount`, needs Redis ≥ 7), **not** `pendingEntriesCount`. Verify: enqueue 50 snapshots with no workers running and check the replica count rises.
  - Demo pitfall (D4, demo 6): KEDA checks the queue every `pollingInterval` (default 30 s), which dominates the measured cold start. Set it to 5 s and keep `cooldownPeriod` explicit. Demo 6 reports the cold start broken down: queue seen by KEDA → pod scheduled → model loaded (`/readyz`) → first `ai_guess`; and compares "warm-up on room creation" (rooms trigger) with "warm-up on first snapshot" (lag trigger).
  - Measure **R** (rooms one replica serves at 1 snapshot/s per room) with one worker: add rooms until queue wait rises (needs D12). Record it in ADR-008.
  - `cooldownPeriod` and scale-down stabilization longer than the gap between rounds, so replicas do not flap at every round end.
  - Overload: at `maxReplicaCount` with lag still rising, game-servers raise `SNAPSHOT_INTERVAL_MS` (1 s → 2 s), halving AI load (same idea as pausing the timer).
  - Record the HPA / KEDA timing values next to the demo 5 / 6 numbers in `goals.md`.
  - Acceptance: `kubectl get scaledobject` healthy; more rooms scale AI pods up before a backlog forms; enqueuing 50 snapshots scales them up; they scale down after the load stops.

- [ ] **P2-7 PodDisruptionBudgets** · Owner: C · Needs: P2-2
  - PDBs per `architecture.md` §7.
  - Demo pitfall (D1, demo 7): as designed, game-server PDB `minAvailable: 2` with HPA `minReplicas: 2` lets **no** pod be evicted, so `kubectl drain` waits forever. Fix: game-server `minReplicas: 3` (recommended), or PDB `maxUnavailable: 1`; update `architecture.md` §7 and add an ADR. Same check for every PDB against its minimum replicas.
  - PDBs protect only against voluntary disruptions (drain, rollout); crashes and node failures are covered by N+1 capacity and D9.
  - Acceptance: demo scenario 7 passes; draining any agent node completes in < 2 min while available pods never drop below the PDB.

**IC2 — integration checkpoint:** the real images run in k3d; all pods Ready; a round is playable through the Ingress.

## Phase 3 — Operations & evidence

- [ ] **P3-1 Monitoring stack** · Owner: C (A and B provide their metrics) · Needs: P2-2
  - `make monitoring` installs kube-prometheus-stack; ServiceMonitors; Grafana dashboard JSON committed in `deploy/monitoring/dashboards/`. Build the dashboard against the stub's placeholder metrics first.
  - R5: Grafana admin password from a Secret (never the chart default `prom-operator`); Grafana not routed through the Ingress, reached via `kubectl port-forward` on `localhost:3001`.
  - Demo pitfall (D7, demo 9): the alert delay adds up as circuit-breaker 5 s + scrape interval (default 30 s) + rule evaluation interval + `for: 30s`. Set scrape and evaluation intervals ≤ 15 s, or the < 60 s target is not reachable.
  - Acceptance: dashboard shows all metrics from `architecture.md` §8 with live data.

- [ ] **P3-2 Alerts** · Owner: C (rule thresholds with B) · Needs: P3-1
  - PrometheusRules from `goals.md` G5.
  - Acceptance: demo scenario 9 passes; `PodCrashLooping` fires for the stub with `CRASH_AFTER_MS`.

- [ ] **P3-3 Load test** · Owner: C · Needs: P0.5-2 (mock), later P2-2 with the real game-server
  - k6 script in `loadtest/` that joins rooms of 4–6 virtual players who send strokes at a realistic rate. Develop against the mock WebSocket server.
  - Demo pitfall (D2): all virtual players come from one source IP, so the per-IP `/ws` rate limit throttles the load test instead of the app being measured. Run with a load-test values override that raises the limit (and say so in the results).
  - k6 runs on the same host as the cluster (R4): record its CPU use and run `make preflight-measure` first.
  - Acceptance: demo scenario 5 passes; k6 summary saved to `loadtest/results/` shows 0 failed WebSocket connects and 0 HTTP 429.

- [ ] **P3-4 Demo scripts** · Owner: C (framework, demos 1, 5, 7, 10); A (demos 2, 4, 8); B (demos 3, 6, 9)
  - `scripts/demo-1.sh` … `demo-10.sh` + `make demo-<n>`; each prints the measured numbers. Write each script against the stub first; it must pass with the real services.
  - R4: each script starts with `scripts/preflight.sh --measure` (aborts if other VMs or heavy jobs are running) and prints host load average next to its result; numbers in `goals.md` are the median of ≥ 3 runs, all on the one measurement machine (`docs/team-plan.md`).
  - R2: `make preload` (or equivalent) pulls every image into the nodes ahead of the demo, so live demo 1 works without Docker Hub.
  - Acceptance: all 10 scenarios run end-to-end on a fresh cluster.

**IC3 — integration checkpoint:** all 10 demos pass on a fresh cluster on the measurement machine; recording numbers starts.

- [ ] **P3-5 Results & runbook** · Owner: all (each fills the rows of their demos)
  - Fill the results table in `goals.md`; complete `runbook.md`.
  - Acceptance: every row in the results table has a number and evidence.

## Stretch goals

- [ ] **S-1** HPA on custom metric `drawguess_ws_connections` via prometheus-adapter.
- [ ] **S-2** GitOps with ArgoCD watching this repo.
- [ ] **S-3** Canary releases with Argo Rollouts.
- [ ] **S-4** Loki for centralized logs; OpenTelemetry traces for stroke → guess latency.
- [ ] **S-5** Chaos Mesh experiments (pod kill, network delay) automated.
- [ ] **S-6** Deploy to a small managed cloud cluster with Cloudflare in front (CDN).
- [ ] **S-7** Zone-level redundancy for AI: size replicas as `ceil(need × 3/2)` so losing one of three zones keeps full capacity; measure the cost.
