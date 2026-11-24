# Runbook

Operational procedures. Agents and team members: keep each entry accurate as features land. Format per entry: **Symptom → Check → Fix → Verify**.

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

## Redis / PostgreSQL pod restarted
- Data is on PVCs; confirm with `kubectl get pvc -n <ns>`. Game-servers reconnect automatically; rooms in progress resume from Redis.
