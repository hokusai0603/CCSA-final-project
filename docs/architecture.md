# Architecture

## 1. Components

| Component | Kind | Replicas | Responsibility |
|---|---|---|---|
| `frontend` | Deployment | 2 | nginx serving the built static client |
| `game-server` | Deployment + HPA | 2–8 | WebSocket connections, room logic, scoring, enqueue snapshots |
| `ai-inference` | Deployment + KEDA ScaledObject | 2–6 during play (0 allowed in `idle` profile); all active, one spare (ADR-008) | Consume snapshots, run the CNN, publish guesses |
| `redis` | StatefulSet + PVC | 1 | Live room state, stroke log, Pub/Sub, the `ai:snapshots` stream |
| `postgres` | StatefulSet + PVC | 1 | Players, rounds, scores, leaderboard |
| Ingress | Traefik (k3s built-in) | — | Single entry point, TLS, WebSocket upgrade, rate limiting middleware |

Production note: in a real deployment Redis and PostgreSQL would be managed cloud services (or HA via Sentinel / an operator). We run them in-cluster on purpose to demonstrate StatefulSet and PersistentVolume management. See `decisions.md` ADR-004.

## 2. Request flow

1. Browser loads static files from `frontend` through the Ingress.
2. Browser opens `wss://<host>/ws?room=<id>&name=<nick>` → Ingress → any `game-server` pod.
3. A stroke from a player is appended to Redis (`room:{id}:strokes`) and published on channel `room:{id}`. Every game-server pod subscribed to that channel forwards it to its own connected players in that room.
4. Every snapshot interval (default 1000 ms, configurable `SNAPSHOT_INTERVAL_MS`) the pod that owns the room's timer tries `SET ai:pending:{room} 1 NX EX 5`. Only if it succeeds does it `XADD ai:snapshots` with `{room, round, seq}`. This guarantees **at most one pending AI request per room**.
5. An `ai-inference` worker reads from consumer group `ai-workers`, loads the room's strokes from Redis, rasterizes them to 28×28, runs the ONNX model, then publishes `{"type":"ai_guess",...}` on `room:{id}`, `XACK`s the entry and deletes `ai:pending:{room}`.
6. If the request's `seq` is older than the room's current stroke seq by more than `STALE_SEQ_THRESHOLD`, the worker still runs the latest strokes (it always reads fresh strokes), so stale requests never produce stale guesses.
7. When a guess's top-1 label equals the secret word, the game-server owning the room ends the round, writes scores to PostgreSQL, and publishes `round_end`.

### Room ownership (timer)
Exactly one pod drives each room's timer and snapshot loop. Ownership is a Redis lease: `SET room:{id}:owner <pod> NX PX 3000`, renewed every second. If the owner pod dies, another pod with players in that room acquires the lease within ~3 s. This is what makes game-server pods safely killable.

## 3. WebSocket protocol (JSON messages)

Client → server

| type | fields | notes |
|---|---|---|
| `join` | `room`, `name`, `lastSeq?` | `lastSeq` present on reconnect → server replays strokes after it |
| `stroke` | `points: [[x,y],...]`, `color`, `width` | coordinates normalized 0–1 |
| `clear` | — | clears canvas for everyone |
| `chat` | `text` | |

Server → client

| type | fields |
|---|---|
| `state` | `round`, `wordHint`, `timeLeft`, `paused`, `players`, `strokes[]`, `seq` |
| `stroke` | `seq`, `points`, `color`, `width`, `by` |
| `ai_guess` | `guesses: [{label, confidence}]` (top 3) |
| `ai_status` | `available: bool` — drives the "AI busy, timer paused" banner |
| `round_start` / `round_end` | `round`, `word` (only at end), `scores` |
| `reconnect` | `reason` — sent before graceful shutdown |

Every stroke gets a monotonically increasing `seq` per room (`INCR room:{id}:seq`). Clients store the last seq they saw.

## 4. Redis key layout

| Key | Type | Purpose |
|---|---|---|
| `room:{id}:state` | hash | round, word, timeLeftMs, paused, startedAt |
| `room:{id}:strokes` | list | stroke JSON objects for the current round |
| `room:{id}:seq` | string (counter) | last stroke seq |
| `room:{id}:players` | hash | playerId → name, score |
| `room:{id}:owner` | string (lease) | pod that drives the timer |
| `room:{id}` | Pub/Sub channel | fan-out of strokes, guesses, round events |
| `ai:snapshots` | stream | AI work queue, consumer group `ai-workers` |
| `ai:pending:{id}` | string, TTL 5 s | coalescing flag, one pending request per room |
| `ai:last_ok` | string, TTL | heartbeat refreshed by workers; used by the AI circuit breaker |
| `ai:dead` | stream | dead-letter: snapshots that failed 2 deliveries, kept for inspection |

All room keys get a TTL (e.g. 2 h) refreshed on activity so abandoned rooms disappear.

## 5. AI model

- Training data: QuickDraw simplified drawings, a subset of **~50 categories** (keeps the model small and accuracy high). The category list **is** the game's word list (`services/ai-inference/categories.txt`).
- Model: small CNN (2–3 conv layers) on 28×28 grayscale input, trained offline in `services/ai-inference/training/`, exported to ONNX (target size < 5 MB).
- Inference: ONNX Runtime on CPU, target < 50 ms per snapshot.
- Startup: model loaded before `/readyz` returns 200; a `startupProbe` covers load time.

## 6. Degradation and defence in depth (AI)

1. **Prevent** — ≥ 2 AI replicas spread across zones, one spare replica above the load (N+1, ADR-008), resource limits, PDB `minAvailable: 1` (voluntary disruptions only). Snapshot size is capped (strokes per round, points per stroke). An entry delivered more than twice goes to `ai:dead` and is acknowledged, so a poison snapshot cannot crash every worker in turn.
2. **Recover fast** — unacknowledged stream entries are reclaimed by other workers (`XAUTOCLAIM` after 3 s), so one pod crashing costs players ~1 s.
3. **Degrade gracefully** — if `ai:last_ok` is older than 5 s (circuit open), game-servers broadcast `ai_status {available:false}`, **pause the round timer**, and keep drawing/chat working. When the circuit closes, the timer resumes and the AI guesses the latest canvas. Players never lose points because of an AI outage.

## 7. Kubernetes resources (Helm chart)

| Resource | For | Key settings |
|---|---|---|
| Namespace | `drawguess-dev`, `drawguess-prod` | one per environment |
| Deployment | frontend, game-server, ai-inference | probes, requests/limits, topology spread on zone (`nodeTaintsPolicy: Honor`), non-root securityContext; game-server and ai-inference tolerate `not-ready` / `unreachable` for 15 s, not 300 s |
| StatefulSet + PVC | redis, postgres | `local-path` StorageClass (k3s default) |
| Service | all components | ClusterIP; headless for StatefulSets |
| Ingress + Traefik Middleware | frontend `/`, game-server `/ws` | rate limit on `/ws` |
| ConfigMap / Secret | app config / DB password | Secret values come from `values-*.yaml` overrides, never committed |
| HPA | game-server | CPU 60 % baseline; stretch: custom metric `ws_connections` via prometheus-adapter |
| KEDA ScaledObject | ai-inference | two triggers, highest wins (ADR-008): active rooms → `ceil(rooms / R) + 1`; `redis-streams` lag on `ai:snapshots` / group `ai-workers` → `ceil(lag / 5)` (not `pendingEntriesCount`); `pollingInterval` 5 s; `minReplicaCount` 2 (`play`) or 0 (`idle`); `maxReplicaCount` 6 |
| PodDisruptionBudget | game-server (`minAvailable: 2`), ai-inference (`minAvailable: 1`), frontend (`minAvailable: 1`) | |
| ServiceMonitor | game-server, ai-inference | scraped by Prometheus |
| PrometheusRule | alerts | see `goals.md` G5 |

## 8. Metrics (Prometheus names)

| Metric | Type | Service |
|---|---|---|
| `drawguess_ws_connections` | gauge | game-server |
| `drawguess_rooms_active` | gauge | game-server |
| `drawguess_stroke_fanout_seconds` | histogram | game-server (receive → forwarded) |
| `drawguess_reconnects_total` | counter | game-server |
| `drawguess_rounds_interrupted_total` | counter | game-server (used to prove "0 dropped games") |
| `drawguess_ai_circuit_open` | gauge 0/1 | game-server |
| `drawguess_ai_inference_seconds` | histogram | ai-inference |
| `drawguess_ai_snapshots_processed_total` | counter | ai-inference |
| `drawguess_ai_queue_pending` | gauge | ai-inference (also what KEDA scales on) |
