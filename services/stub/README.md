# stub

Placeholder service image. To Kubernetes it looks like a DrawGuess service: probes, Prometheus metrics, WebSocket, graceful shutdown. It has no game logic. Uses:

- Build and verify the Helm chart, probes, HPA, PDBs, ServiceMonitors, alerts and demo scripts **before** the real services exist. Swap in the real image per component in `values.yaml` later.
- The **bad release** of demo 8 (`FAIL_READY=1`), kept after the real services land.

Build: `make stub-image` → `drawguess/stub:<short sha>` (or `<sha>-dirty-<content hash>` with uncommitted changes), imported into k3d when the cluster is up.

## Endpoints (port `PORT`, default 8080)

| Path | Behaviour |
|---|---|
| `GET /healthz` | 200 while the process lives (liveness) |
| `GET /readyz` | 200 when ready; 503 while starting, with `FAIL_READY=1`, or while shutting down |
| `GET /metrics` | `drawguess_stub_info`, request counts, and the `docs/architecture.md` §8 metric names for `COMPONENT` (placeholder values; `drawguess_ws_connections` is the real count) |
| `GET /` | `{component, version, pod, ready}`, handy to watch a rolling update |
| `GET /burn?ms=N` | burns CPU for N ms (≤ 5000) in a worker thread, at most 4 at once (else 429); drives HPA without a load test |
| `WS /ws` | sends `{"type":"hello","pod","version"}`, then echoes every message |

## Configuration (env)

| Variable | Default | Effect |
|---|---|---|
| `COMPONENT` | `generic` | `game-server` or `ai-inference` selects which placeholder metrics are exposed |
| `VERSION` | `dev` | reported by `/` and `/metrics` |
| `READY_DELAY_MS` | `0` | readiness becomes 200 only after this delay (slow start) |
| `FAIL_READY` | unset | `1` = never ready (bad release) |
| `CRASH_AFTER_MS` | `0` | > 0: exit 1 after this delay (crash loop, `PodCrashLooping` alert) |
| `SHUTDOWN_DELAY_MS` | `2000` | after SIGTERM: readiness 503, WebSocket clients get `{"type":"reconnect"}`, then exit after this delay |

Logs are one JSON object per line (AGENTS.md rule 9). The image runs as uid 1000.

## Verified on k3d (2026-11-25)

3 replicas spread over zone-a/b/c, non-root with a read-only root filesystem. Deleting a pod sent `reconnect` to exactly its 10 of 30 WebSocket clients and exited in 3.8 s. A `FAIL_READY=1` rollout stalled at 0/1 while all requests kept hitting v1, and `rollout undo` recovered it. `CRASH_AFTER_MS` produced a crash loop. `/burn` load scaled the HPA from 3 to 6 within about 30 s with no 503s and no restarts.
