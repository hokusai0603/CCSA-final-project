# Helm chart: drawguess

Contains every app component plus Redis and PostgreSQL. Resource list and key settings: `docs/architecture.md` §7. Values files: `values.yaml` (defaults), `values-dev.yaml`, `values-prod.yaml`. Tasks: P2-1 … P2-7.

```bash
make build deploy ENV=dev     # namespace drawguess-dev,  http://localhost:8080
make build deploy ENV=prod    # namespace drawguess-prod, http://prod.localhost:8080
```

`make deploy` runs `helm upgrade --install` with `values-<env>.yaml` and `--set image.tag=<tag>` (the tag `make build` used; `image.tag` is required).

## App services (P2-2)

`frontend`, `game-server`, `ai-inference`: one Deployment + ClusterIP Service each (`drawguess-<component>`, port 80 → 8080), all on `drawguess/stub` until their owner switches `<component>.image.repository` to `drawguess/<component>`.

| Setting | Value | Why |
|---|---|---|
| Replicas | frontend 2, game-server 3, ai-inference 2 | game-server 3 for D1 (HPA/PDB come in P2-6a/P2-7) |
| Env | ConfigMap `drawguess-config` + `PORT`, `VERSION` (= image tag), `POD_NAME`, `COMPONENT`; `REDIS_URL` (game-server, ai-inference); libpq `PG*` incl. `PGPASSWORD` from the Secret (game-server) | names to be fixed in `contracts/services.md` |
| Security | uid/gid 1000, `runAsNonRoot`, read-only root filesystem (`/tmp` emptyDir), all capabilities dropped, no service-account token | AGENTS.md rules 6, 8 |
| Probes | startup + liveness `/healthz` (liveness 10 s period, 2 s timeout, 3 failures), readiness `/readyz` | load alone must not restart a pod (P0-5 lesson) |
| Rollout | `maxUnavailable: 0`, `maxSurge: 1`, `preStop` sleep 5 s, grace 30 s | 0 failures in a rolling update under load |
| Spread | zone, `maxSkew: 1`, `DoNotSchedule`, `nodeTaintsPolicy: Honor`, `matchLabelKeys: [pod-template-hash]` | D1; without `matchLabelKeys` a rollout left 2 of 3 game-servers on one node |
| Node failure | tolerate `not-ready` / `unreachable` for `app.nodeFailureTolerationSeconds` (15) | D9: replacements in ~60 s instead of ~340 s |

Ingress (Traefik): `drawguess` (`/` → frontend) and `drawguess-ws` (`/ws` → game-server). Both use the `drawguess-retry` middleware and the `drawguess-transport` ServersTransport (`dialTimeout: 1s`), so a dead pod costs a connection about one second instead of hanging (D15). `/ws` also has `drawguess-ws-ratelimit`. Traefik sees one source IP per k3d node (D14), so the limit is shared by everyone behind that node. Dev answers on any host; prod on `prod.localhost`.

## Stateful services (P2-1)

| | Redis | PostgreSQL |
|---|---|---|
| Image | `redis:8.10.3-alpine3.23` (≥ 7 needed for KEDA's lag trigger, ADR-008) | `postgres:18.7-alpine3.24` |
| Kind | StatefulSet, 1 replica, PVC `data` | StatefulSet, 1 replica, PVC `data` |
| Client Service | `drawguess-redis:6379` | `drawguess-postgres:5432`, db/user `drawguess` |
| Headless Service | `drawguess-redis-headless` | `drawguess-postgres-headless` |
| Persistence | AOF (`appendfsync everysec`), `maxmemory-policy noeviction` | data in `/var/lib/postgresql/18/docker` on the PVC |
| Runs as | uid 999, read-only root filesystem | uid 70, read-only root filesystem (emptyDirs for socket, `/tmp`, `/dev/shm`) |
| Shutdown | SIGTERM (AOF flushed) | `preStop`: `pg_ctl -m fast` (clean shutdown, no crash recovery) |

- **Password**: generated once per release into Secret `drawguess-postgres` (key `password`), reused by `helm upgrade` through `lookup`, and kept on `helm uninstall` (`helm.sh/resource-policy: keep`), because PostgreSQL stores it at initdb and the PVC outlives the release. To bring your own: `postgres.auth.existingSecret`.
- **Placement (D13)**: `local-path` volumes are tied to one node, so both pods are pinned to the k3d server node (`stateful.nodeSelector`), which demos 7 and 10 never drain or stop. Set `stateful.nodeSelector: {}` on a cluster with network storage.
- **Keeping data**: PVCs and the Secret survive `helm uninstall`; a reinstall finds the same data and password. To start over, delete them (the commands are in `NOTES.txt`).
- Redis has no password: it is reachable only through ClusterIP Services inside the cluster.
