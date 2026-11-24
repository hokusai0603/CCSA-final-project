# Host environment risks (R1–R6)

The demo cluster is k3d on a single Linux host (ADR-006). On a **shared lab machine** that also runs other services, six things can break the project or skew its numbers. Each risk has a check in `make preflight` and a mitigation owned by a roadmap task.

Run `make preflight` before `make cluster-up`, and `make preflight-measure` before recording any number for `goals.md`.

| # | Risk | Likelihood | Worst case | Check | Mitigation owned by |
|---|---|---|---|---|---|
| R1 | inotify limit | Certain on hosts with other root workloads | Monitoring pods crash-loop with "too many open files" | `preflight` FAIL | `scripts/host-sysctl.sh` (P0-1) |
| R2 | Docker Hub pull limit | Medium–high, highest before the demo | Demo 1 stuck in `ImagePullBackOff` | `preflight` WARN | P0-2 (registry mirror), P3-4 (preload) |
| R3 | Host services on default ports | Medium during Phase 1 | Tests flush **someone else's** Redis/PostgreSQL | `preflight` WARN | P1-2, P1-3, P1-5 |
| R4 | Other heavy workloads | Medium (long unattended jobs are easy to forget) | Latency/HPA numbers not reproducible | `preflight-measure` FAIL | P3-4 |
| R5 | Shared host, public ingress port | Low–medium | Cluster removed by another user's cleanup; Grafana exposed | `preflight` WARN | P0-2, P3-1, AGENTS.md rule 12 |
| R6 | Host-level Kubernetes | Low | Commands hit the host's cluster instead of ours | `lib.sh` guard, `preflight` | P0-1 (`lib.sh`), P0-2 |

## R1 — inotify instance limit

**Mechanism.** `fs.inotify.max_user_instances` is counted per real user ID. k3d nodes are containers running as root, so their kubelet and containerd share root's quota with every other root process on the host (a host-level k3s, system services). The Ubuntu default is 128.

**Observed.** On the development host, a single `kubectl logs -f` failed with `failed to create fsnotify watcher: too many open files` before the fix; 48 parallel streams worked after it.

**Impact.** Beyond logs: Prometheus Operator's config-reloader and Grafana's dashboard sidecar use inotify and crash-loop. The error looks like an application bug.

**Mitigation.** `make host-sysctl` (once per host, needs sudo) writes `/etc/sysctl.d/99-k3d-inotify.conf` with 1024 instances / 524288 watches. It never lowers an existing higher value.

## R2 — Docker Hub anonymous pull limit

**Mechanism.** Anonymous pulls are limited per source IP (100 per hour when checked). Everyone and every VM behind the same IP shares the quota. Each k3d node has its **own** containerd image store, so per-node images (pause, svclb) are pulled once per node, and every `cluster-down`/`cluster-up` starts empty. A fresh cluster plus the full stack is roughly 25–30 pulls. Our own images are imported with `k3d image import` and cost nothing.

**Impact.** `ImagePullBackOff` during "fresh cluster" verification, and in the worst case during live demo 1.

**Mitigation.**
- P0-2: `cluster-up` configures a registry mirror (pull-through cache) so recreated clusters do not hit Docker Hub again.
- P3-4: before the demo, preload all images into the nodes; optionally `docker login` for a higher quota.
- `preflight` prints the remaining quota (HEAD requests do not consume it).

## R3 — host services on the default ports

**Mechanism.** The host may already run Redis (6379), PostgreSQL (5432) and Grafana (3000) bound to localhost, possibly without a password. Publishing those ports from Compose fails loudly. That case is harmless. The dangerous case is silent: a service or test run on the host with a default like `redis://localhost:6379` connects to the **host's** Redis and succeeds.

**Impact.** A test teardown with `FLUSHDB`, or a migration with `DROP TABLE`, destroys another user's data; or tests pass or fail because of foreign data.

**Mitigation (rule 10 in AGENTS.md).**
- Local development uses Redis **16379**, PostgreSQL **15432**, Grafana **3001**, and Compose serves the game on **8081**, so Compose and k3d (8080) can run side by side.
- Tests never flush or drop anything they did not create. They use a unique key prefix or database, and refuse to run against a non-empty target.

## R4 — other heavy workloads during measurements

**Mechanism.** k3d, Prometheus, up to 8 game-servers **and the k6 load generator** all run on the same host. Another VM or long batch job competes for CPU and disk; tail latency (p99) is the first number to move. The effect goes both ways: our load test also slows the other job down.

**Observed.** The same WebSocket smoke test gave p95 = 46 ms in one run and 6 ms in the next.

**Mitigation.** `make preflight-measure` fails while VMs are running or load average > CPUs/4. Every `demo-<n>.sh` (P3-4) starts with it and prints the host load next to its result. Each number in `goals.md` is the median of ≥ 3 runs.

## R5 — shared host and the public ingress port

**Mechanism.** Membership of the `docker` group is root-equivalent. Other members can `docker exec` into a k3d node (cluster-admin, Secrets) or remove our containers with a global cleanup (`docker system prune -a`, `docker rm -f $(docker ps -aq)`). Conversely, our scripts could delete their containers. Port 8080 bound to `0.0.0.0` makes the game reachable from the whole network segment. That is handy for phones during the demo, but it lets strangers in during measurements. kube-prometheus-stack's default Grafana login is public knowledge.

**Mitigation.**
- P0-2: ingress binds `127.0.0.1:8080` by default; `make cluster-up EXPOSE=1` opts in to `0.0.0.0` for the live demo.
- P3-1: Grafana admin password comes from a Secret (never the chart default) and Grafana is reached only via `kubectl port-forward` on 3001.
- Rule 12 in AGENTS.md: scripts only remove resources labelled for our cluster (`k3d cluster delete`, `--filter label=k3d.cluster=drawguess`), never global prunes.

## R6 — a host-level Kubernetes

**Mechanism.** The host may run its own k3s on 80/443/6443 with a root-only kubeconfig, and `/usr/local/bin/kubectl` may be a symlink to that k3s. Under `sudo`, `PATH` drops `~/.local/bin`, so `sudo kubectl …` acts on the **host's** cluster. If someone maps host port 80/443 in `cluster.yaml` for TLS, cluster creation fails at best; at worst, the host's iptables rules intercept the traffic silently.

**Mitigation.**
- `scripts/lib.sh` refuses to run as root and pins every call to `--context k3d-drawguess` (`kc`, `hc`). Scripts never call bare `kubectl` or `helm`.
- P0-2: API server on `127.0.0.1:6550` (not exposed to the network, stable port); ingress on 8080 and TLS on 8443, never 80/443/6443.
- `preflight` fails if `kubectl` resolves to the k3s binary and warns on client/server version skew > 1.
