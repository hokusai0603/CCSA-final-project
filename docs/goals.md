# Project Goals

The project is graded on whether we can **manage Kubernetes and operate a live game service**, not on player count. Every goal below is measurable and maps to at least one demo scenario (`demo-scenarios.md`). Results go in the table at the bottom once measured.

## G1 — Cluster management
- Whole system deploys with one command (`make deploy ENV=dev`) on a fresh cluster.
- Separate `dev` and `prod` namespaces from the same chart with different values.
- Config in ConfigMaps, credentials in Secrets; Redis and PostgreSQL run as StatefulSets with PersistentVolumes and survive pod restarts without data loss.
- **Target:** a bad release is rolled back (`helm rollback`) and healthy in **< 60 s**.

## G2 — Stability & self-healing
- **Target:** a deleted game-server pod is replaced and Ready in **< 30 s**.
- **Target:** affected players reconnect automatically in **< 5 s** with **0 lost strokes**.
- **Target:** with all AI pods down, drawing/chat keep working, the timer pauses, and no points are lost.

## G3 — Zero-downtime operations
- **Target:** a rolling update of game-server during active play causes **0 interrupted rounds** (`drawguess_rounds_interrupted_total` unchanged).
- **Target:** `kubectl drain` of a node keeps at least `minAvailable` pods serving at all times (PDB).

## G4 — Elasticity
The game is small; autoscaling is here to prove the system *adapts*, and to control cost.
- **Target:** a k6 run with **200 simulated players** scales game-server out (HPA) and back in after the load stops, while stroke fan-out p99 stays **< 150 ms**.
- **Target:** KEDA scales ai-inference on queue backlog; in the `idle` profile it scales to 0 and we measure the **cold-start time** of the first guess.

## G5 — Observability
- Grafana dashboard showing: connections, active rooms, stroke fan-out p99, AI queue pending, AI inference p99, pod counts per deployment, AI circuit state.
- Alerts (PrometheusRule):
  - `AIUnavailable`: `drawguess_ai_circuit_open == 1` for 30 s
  - `AIQueueBacklog`: `drawguess_ai_queue_pending > 20` for 1 m
  - `HighFanoutLatency`: stroke fan-out p99 > 150 ms for 2 m
  - `PodCrashLooping`: restarts increasing
- **Target:** an alert fires **< 1 min** after the corresponding failure is injected.

## Out of scope (documented as future work)
- Real multi-region / multi-AZ cloud deployment (we simulate zones with node labels).
- CDN in front of the frontend.
- Managed / HA Redis and PostgreSQL.
- Accounts and authentication beyond a nickname.

## Measured results (fill in after Phase 3)

| Goal | Metric | Target | Measured | Evidence (screenshot / log) |
|---|---|---|---|---|
| G1 | rollback to healthy | < 60 s | | |
| G2 | pod replaced & Ready | < 30 s | | |
| G2 | player reconnect | < 5 s, 0 lost strokes | | |
| G3 | rounds interrupted during rolling update | 0 | | |
| G3 | min available pods during drain | ≥ PDB | | |
| G4 | game-server replicas at 200 players | > 2 | | |
| G4 | stroke fan-out p99 at 200 players | < 150 ms | | |
| G4 | AI cold start from 0 | measure | | |
| G5 | alert latency | < 60 s | | |
