# Runbook

Operational procedures. Agents and team members: keep each entry accurate as features land. Format per entry: **Symptom → Check → Fix → Verify**.

## Before anything on a new host
- **Check:** `make preflight` (details for each R-number in `docs/host-environment.md`).
- **Fix:** follow the hint printed on each FAIL line.
- **Verify:** `preflight: no failures`. Before recording any number, `make preflight-measure` must also pass.

## "too many open files" / `failed to create fsnotify watcher` (R1)
- **Symptom:** `kubectl logs -f` fails, or config-reloader / Grafana sidecar pods crash-loop.
- **Check:** `sysctl fs.inotify.max_user_instances fs.inotify.max_user_watches`.
- **Fix:** `make host-sysctl` (sudo, persists across reboots).
- **Verify:** `kubectl logs -f` on several pods at once works; affected pods become Ready after a restart.

## `ImagePullBackOff` with `429 Too Many Requests` (R2)
- **Check:** `kubectl describe pod` events; `make preflight` prints the remaining Docker Hub quota for this IP.
- **Fix:** check the cache is running (`docker ps --filter name=k3d-drawguess-cache`, `curl http://127.0.0.1:5005/v2/_catalog`); start it with `make cluster-up` (it re-creates a missing cache); wait for the hourly window or export `DOCKERHUB_USERNAME` / `DOCKERHUB_TOKEN`, then `make cluster-down cache-down cluster-up`.
- **Verify:** pods pull and become Ready; the image shows up in the cache catalog.

## Recreate the cluster / reclaim disk
- `make cluster-down cluster-up`: fresh cluster in about 45 s; images come from the cache.
- `make cluster-down cache-down`: also deletes the image cache (next `cluster-up` pulls everything from Docker Hub again).
- Never use `docker system prune` or other global cleanup on the shared host (AGENTS.md rule 12).

## AI unavailable (`AIUnavailable` alert / banner shown to players)
- **Check:** `kubectl -n <ns> get pods -l app=ai-inference`; `kubectl -n <ns> logs -l app=ai-inference --tail=100`; Grafana panel "AI circuit".
- **Fix:** if pods are crash-looping after a release → `helm rollback`; if OOMKilled → raise memory limit in values; if KEDA shows 0 replicas in `play` profile → check the ScaledObject and Redis connectivity.
- **Verify:** `drawguess_ai_circuit_open` returns to 0; players see guesses again.

## AI queue backlog (`AIQueueBacklog`)
- **Check:** `kubectl get scaledobject,hpa -n <ns>`; is `maxReplicaCount` reached? Are workers stuck (pending entries not acknowledged)?
- **Fix:** raise `maxReplicaCount`; restart stuck workers; confirm `XAUTOCLAIM` is running.
- **Verify:** pending count trends to 0.

## High stroke latency (`HighFanoutLatency`)
- **Check:** game-server CPU and HPA status; Redis latency (`redis-cli --latency`).
- **Fix:** raise HPA `maxReplicas` or the CPU request; check Redis resource limits.

## Bad release
- **Check:** `helm history drawguess -n <ns>`; readiness failures in `kubectl describe pod`.
- **Fix:** `helm rollback drawguess <previous-revision> -n <ns>`.
- **Verify:** all pods Ready; error rate back to baseline.

## Node maintenance
1. `kubectl cordon <node>`
2. `kubectl drain <node> --ignore-daemonsets --delete-emptydir-data` (PDBs pace evictions)
3. Do the maintenance, then `kubectl uncordon <node>`.

## Reinstall the chart / reset stateful data
- `helm uninstall` keeps the PVCs and the PostgreSQL Secret, so a reinstall finds the same data and password.
- Wait for the old pods to be gone before reinstalling: `kubectl -n <ns> wait --for=delete pod -l app.kubernetes.io/instance=drawguess`. `helm uninstall --wait` returns while they are still `Terminating`.
- To start from empty: after uninstall, `kubectl -n <ns> delete pvc -l app.kubernetes.io/instance=drawguess` and `kubectl -n <ns> delete secret drawguess-postgres`.

## Redis / PostgreSQL pod restarted
- Data is on PVCs; confirm with `kubectl get pvc -n <ns>`. Game-servers reconnect automatically; rooms in progress resume from Redis.
