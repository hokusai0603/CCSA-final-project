# Architecture Decision Records

Short records of decisions and their trade-offs. Add a new entry instead of silently changing a decision.

## ADR-001 Stateless game servers, state in Redis
**Decision:** game-server pods hold no authoritative state; rooms live in Redis, fan-out via Pub/Sub, timer ownership via a Redis lease.
**Why:** any pod can be killed, updated, or scaled without losing a game — the basis of demo scenarios 2, 4, 5 and 7.
**Cost:** every stroke touches Redis; Redis becomes the critical dependency (acceptable at our scale).

## ADR-002 AI as a queue worker (Redis Streams), not a synchronous API
**Decision:** game-servers enqueue snapshots; AI workers consume them.
**Why:** decouples AI latency and failures from gameplay; enables coalescing (one pending request per room) and queue-based autoscaling with KEDA.
**Cost:** guesses are asynchronous (~1 s cadence), which fits the game.

## ADR-003 Small CNN on QuickDraw instead of a vision-language model
**Decision:** a fixed ~50-category classifier exported to ONNX, CPU only.
**Why:** tiny, fast (< 50 ms), cheap, deterministic, and the dataset is exactly human doodles. A VLM would need GPUs and be slower and less predictable.
**Cost:** the word list is limited to the trained categories.

## ADR-004 Redis and PostgreSQL in-cluster as StatefulSets
**Decision:** run them inside Kubernetes with PVCs.
**Why:** the course goal is to demonstrate Kubernetes management, including stateful workloads and persistent storage.
**Cost:** single replica each, so they are a single point of failure. In production we would use managed services or an HA setup (Redis Sentinel, CloudNativePG). We state this explicitly in the presentation.

## ADR-005 AI availability: minimum replicas during play
**Decision:** KEDA `minReplicaCount: 2` in the `play` profile; `0` only in the `idle` profile.
**Why:** scale-to-zero saves cost but adds cold-start delay and contradicts "AI stays available during play". We show both profiles and the measured trade-off.

## ADR-006 k3d for the demo cluster; zones simulated with node labels
**Decision:** 1 server + 3 agents, labelled `zone-a/b/c`.
**Why:** free, reproducible on a laptop, and still demonstrates topology spread, PDBs and node drains.
**Cost:** not real failure domains; noted as future work.

## ADR-007 No CDN in the demo environment
**Decision:** the frontend is served by nginx through the Ingress; a CDN is documented as production design only.
**Why:** with all players on one network a CDN shows no measurable effect. A CDN would only speed up static assets, not WebSocket or AI traffic.

## ADR-008 AI autoscaling: every replica active, N+1 spare, rooms + lag triggers
**Decision:** all ai-inference replicas consume the queue (no standby pods). KEDA scales them on two triggers and takes the higher: **active rooms** (proactive, `ceil(rooms / R) + 1`, i.e. live capacity plus one spare replica) and **stream lag** (reactive safety net, `ceil(lag / 5)`, the redis-streams lag metric, not `pendingEntriesCount`). Bounds: min 2 in `play` (spread across zones), 0 in `idle`, max 6. `R` = rooms one replica serves at one snapshot per second, measured in P2-6b; ONNX Runtime runs one intra-op thread per replica so throughput scales with replicas.
**Why:**
- Workers are stateless queue consumers; a standby pod would idle while a crashed worker's entries are reclaimed by the others anyway (`XAUTOCLAIM`).
- AI load follows **rooms**, not players: coalescing allows one pending snapshot per room.
- Scaling only on lag reacts after players already see late guesses, plus the cold start; the rooms trigger adds capacity as rooms open.
- With one spare, a single crash costs no capacity. Two simultaneous crashes degrade gracefully: coalescing bounds the backlog to the number of rooms, so guesses slow down (e.g. 1 s → ~1.3 s per room) instead of piling up.
**Cost:** one extra replica during play; the rooms trigger needs a room-count source (a game-server endpoint, or Prometheus). Node failure is not covered by the triggers: dead pods still count as replicas, so D9 (`tolerationSeconds` 15 s) is required. Losing a whole zone keeps full capacity only with `ceil(need × 3/2)` replicas (stretch S-7).
