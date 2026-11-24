#!/usr/bin/env bash
# Host pre-flight checks. Risks R1–R6 are explained in docs/host-environment.md.
#
#   scripts/preflight.sh            # before cluster-up / development
#   scripts/preflight.sh --measure  # before recording numbers: other heavy workloads become FAIL (R4)
#
# Env: PREFLIGHT_OFFLINE=1 skips the Docker Hub quota query.
# Exit: 0 = no FAIL (WARNs allowed), 1 = at least one FAIL.
source "$(dirname "$0")/lib.sh"

MEASURE=0
[[ "${1:-}" == "--measure" ]] && MEASURE=1

# Thresholds
INOTIFY_INSTANCES_MIN=512
INOTIFY_WATCHES_MIN=262144
DISK_FREE_MIN_GB=20
DOCKERHUB_REMAINING_MIN=30
INGRESS_PORT=8080
API_PORT=6550

fails=0
f() { fail "$*"; fails=$((fails + 1)); }
# In --measure mode a warning about measurement noise becomes a failure.
measure_warn() { if ((MEASURE)); then f "$*"; else warn "$*"; fi; }

port_in_use() { ss -Hltn "sport = :$1" 2>/dev/null | grep -q .; }

cluster_running() {
  docker ps --filter "label=k3d.cluster=${CLUSTER_NAME}" --format '{{.Names}}' 2>/dev/null | grep -q .
}

info "== tools"
if docker info >/dev/null 2>&1; then
  ok "docker reachable ($(docker version --format '{{.Server.Version}}'))"
else
  f "docker not reachable as $(id -un): join the docker group and re-login (or run via: sg docker -c '...')"
fi

for t in k3d k6 git; do
  if command -v "$t" >/dev/null; then ok "$t found"; else f "$t missing (README prerequisites)"; fi
done

if command -v kubectl >/dev/null; then
  kpath=$(readlink -f "$(command -v kubectl)")
  kminor=$(kubectl version --client -o json 2>/dev/null | sed -n 's/.*"minor": *"\([0-9]*\).*/\1/p' | head -1)
  if [[ "$(basename "$kpath")" == k3s ]]; then
    f "kubectl resolves to the host's k3s binary ($kpath); put a standalone kubectl earlier in PATH (R6)"
  else
    ok "kubectl 1.${kminor:-?} ($kpath)"
  fi
else
  f "kubectl missing"
fi

if command -v helm >/dev/null; then
  hv=$(helm version --short 2>/dev/null)
  if [[ "$hv" == v3.* ]]; then ok "helm $hv"; else f "helm $hv: Helm 3 is required (AGENTS.md §3)"; fi
else
  f "helm missing"
fi

if command -v node >/dev/null; then
  nmajor=$(node -p 'process.versions.node.split(".")[0]')
  if ((nmajor >= 24)); then ok "node $(node -v)"; else warn "node $(node -v): Node 24 is required for services (try: nvm use, reads .nvmrc)"; fi
else
  warn "node missing (needed for game-server/frontend development)"
fi

if command -v python3.12 >/dev/null || { command -v uv >/dev/null && uv python find 3.12 >/dev/null 2>&1; }; then
  ok "python 3.12 available"
else
  warn "python 3.12 not found (needed for ai-inference development; 'uv python install 3.12' works without sudo)"
fi

info "== R1 inotify limits"
inst=$(sysctl -n fs.inotify.max_user_instances)
watches=$(sysctl -n fs.inotify.max_user_watches)
if ((inst >= INOTIFY_INSTANCES_MIN && watches >= INOTIFY_WATCHES_MIN)); then
  ok "inotify instances=$inst watches=$watches"
else
  f "inotify instances=$inst watches=$watches (need >= $INOTIFY_INSTANCES_MIN / $INOTIFY_WATCHES_MIN): run 'sudo scripts/host-sysctl.sh'"
fi

info "== R2 image pulls"
if grep -qs '"https://index.docker.io/v1/"' ~/.docker/config.json; then
  ok "docker login present for Docker Hub (authenticated pull quota)"
elif [[ "${PREFLIGHT_OFFLINE:-0}" == 1 ]]; then
  warn "Docker Hub quota check skipped (PREFLIGHT_OFFLINE=1)"
else
  tok=$(curl -fsS --max-time 10 "https://auth.docker.io/token?service=registry.docker.io&scope=repository:ratelimitpreview/test:pull" 2>/dev/null |
    sed -n 's/.*"token": *"\([^"]*\)".*/\1/p') || tok=""
  rem=""
  if [[ -n "$tok" ]]; then
    # HEAD requests do not consume quota.
    rem=$(curl -fsS --max-time 10 --head -H "Authorization: Bearer $tok" \
      https://registry-1.docker.io/v2/ratelimitpreview/test/manifests/latest 2>/dev/null |
      tr -d '\r' | sed -n 's/^ratelimit-remaining: *\([0-9]*\).*/\1/Ip' | head -1)
  fi
  if [[ -z "$rem" ]]; then
    warn "could not query Docker Hub quota (offline?)"
  elif ((rem < DOCKERHUB_REMAINING_MIN)); then
    warn "Docker Hub anonymous pulls left for this IP: $rem (shared by everyone behind it); a fresh cluster + stack needs ~30"
  else
    ok "Docker Hub anonymous pulls left for this IP: $rem"
  fi
fi

droot=$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || echo /)
free_gb=$(df -BG --output=avail "$droot" 2>/dev/null | tail -1 | tr -dc '0-9')
if [[ -n "$free_gb" ]] && ((free_gb < DISK_FREE_MIN_GB)); then
  warn "only ${free_gb} GB free under $droot (need ~${DISK_FREE_MIN_GB} GB for images)"
else
  ok "disk free under $droot: ${free_gb:-?} GB"
fi

info "== R3 host services on default ports"
for p in 6379:Redis 5432:PostgreSQL 3000:Grafana; do
  port=${p%%:*} name=${p#*:}
  if port_in_use "$port"; then
    warn "port $port ($name) is already used on this host: local dev must use the project ports (16379/15432/3001), never this one"
  else
    ok "port $port ($name) free"
  fi
done

info "== R5/R6 cluster ports"
if cluster_running; then
  ok "cluster ${CLUSTER_NAME} already running (ports $INGRESS_PORT/$API_PORT are ours)"
  if command -v kubectl >/dev/null; then
    sminor=$(kc version -o json 2>/dev/null | sed -n '/serverVersion/,$ s/.*"minor": *"\([0-9]*\).*/\1/p' | head -1)
    if [[ -n "${sminor:-}" && -n "${kminor:-}" ]]; then
      skew=$((kminor - sminor)); skew=${skew#-}
      if ((skew > 1)); then
        warn "kubectl 1.$kminor vs cluster 1.$sminor: version skew > 1"
      else
        ok "kubectl/cluster skew ok (1.$kminor / 1.$sminor)"
      fi
    fi
  fi
else
  for port in $INGRESS_PORT $API_PORT; do
    if port_in_use "$port"; then f "port $port already in use (needed by the k3d cluster)"; else ok "port $port free"; fi
  done
fi
if docker container inspect "$CACHE_CONTAINER" >/dev/null 2>&1; then
  ok "image cache $CACHE_CONTAINER exists (port $CACHE_PORT is ours)"
elif port_in_use "$CACHE_PORT"; then
  f "port $CACHE_PORT already in use (needed by the image cache; override with CACHE_PORT=...)"
else
  ok "port $CACHE_PORT free (image cache)"
fi
for port in 80 443 6443; do
  if port_in_use "$port"; then
    info "     note: host port $port is taken (e.g. a host-level k3s): never map it in deploy/k3d/cluster.yaml"
  fi
done

info "== R4 other heavy workloads (measurement noise)"
if command -v VBoxManage >/dev/null; then
  nvm_running=$(VBoxManage list runningvms 2>/dev/null | grep -c . || true)
  if ((nvm_running > 0)); then
    measure_warn "$nvm_running VirtualBox VM(s) running as $(id -un): CPU/disk contention skews latency and HPA numbers"
  else
    ok "no VirtualBox VMs running"
  fi
fi
ncpu=$(nproc)
load1=$(cut -d' ' -f1 /proc/loadavg)
if awk -v l="$load1" -v n="$ncpu" 'BEGIN { exit !(l > n / 4) }'; then
  measure_warn "load average $load1 on $ncpu CPUs (> $((ncpu / 4))): something else is busy"
else
  ok "load average $load1 on $ncpu CPUs"
fi

info "== R5 shared host"
ndocker=$(getent group docker | cut -d: -f4 | tr ',' '\n' | grep -c . || true)
if ((ndocker > 1)); then
  warn "$ndocker accounts can use docker on this host: they can see/exec/remove k3d containers; never prune globally"
else
  ok "docker group has no other members"
fi

if ((fails > 0)); then
  fail "$fails check(s) failed"
  exit 1
fi
info "preflight: no failures"
