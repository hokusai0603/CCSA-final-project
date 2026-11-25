# Helm chart: drawguess

Contains every app component plus Redis and PostgreSQL. Resource list and key settings: `docs/architecture.md` §7. Values files: `values.yaml` (defaults), `values-dev.yaml`, `values-prod.yaml`. Tasks: P2-1 … P2-7.

```bash
helm --kube-context k3d-drawguess upgrade --install drawguess deploy/helm/drawguess \
  -n drawguess-dev --create-namespace -f deploy/helm/drawguess/values-dev.yaml --wait
```

(`make deploy ENV=dev` wraps this from P2-2 on.)

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
