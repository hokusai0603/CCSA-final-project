#!/usr/bin/env bash
# make cluster-up [EXPOSE=1]: create the k3d cluster from deploy/k3d/cluster.yaml.
#   1. preflight (abort on FAIL)
#   2. ensure the Docker Hub pull-through cache registry is running (R2)
#   3. create the cluster (loopback-only ports unless EXPOSE=1, R5)
#   4. wait until nodes and the bundled k3s add-ons are ready
# Env: EXPOSE=1                       bind ingress 8080/8443 on 0.0.0.0 (live demo with phones)
#      DOCKERHUB_USERNAME / DOCKERHUB_TOKEN   optional: authenticated pulls for the cache
source "$(dirname "$0")/lib.sh"
require_tool k3d docker kubectl

EXPOSE="${EXPOSE:-0}"
[[ $EXPOSE == 0 || $EXPOSE == 1 ]] || die "EXPOSE must be 0 or 1, got: $EXPOSE"

CONFIG="$REPO_ROOT/deploy/k3d/cluster.yaml"

"$REPO_ROOT/scripts/preflight.sh" || die "preflight failed: fix the FAIL lines above (docs/host-environment.md)"

if k3d cluster get "$CLUSTER_NAME" >/dev/null 2>&1; then
  info "cluster $CLUSTER_NAME already exists; nothing to do (make cluster-down first to recreate)"
  kc get nodes -L topology.kubernetes.io/zone
  exit 0
fi

# --- R2: pull-through cache for Docker Hub (kept across cluster-down) ---
ensure_cache() {
  if docker container inspect "$CACHE_CONTAINER" >/dev/null 2>&1; then
    if [[ $(docker container inspect -f '{{.State.Running}}' "$CACHE_CONTAINER") != true ]]; then
      docker start "$CACHE_CONTAINER" >/dev/null
    fi
    ok "image cache $CACHE_CONTAINER running (127.0.0.1:$CACHE_PORT)"
    return
  fi
  local args=(registry create "$CACHE_NAME"
    --image "$CACHE_IMAGE"
    --port "127.0.0.1:$CACHE_PORT"
    --proxy-remote-url https://registry-1.docker.io
    --volume "$CACHE_VOLUME:/var/lib/registry")
  if [[ -n ${DOCKERHUB_USERNAME:-} && -n ${DOCKERHUB_TOKEN:-} ]]; then
    args+=(--proxy-username "$DOCKERHUB_USERNAME" --proxy-password "$DOCKERHUB_TOKEN")
  fi
  k3d "${args[@]}" >/dev/null
  ok "image cache $CACHE_CONTAINER created (127.0.0.1:$CACHE_PORT, volume $CACHE_VOLUME)"
}
ensure_cache

# --- R5: loopback-only unless EXPOSE=1 ---
cfg=$(mktemp --suffix=.yaml)
trap 'rm -f "$cfg"' EXIT
if [[ $EXPOSE == 1 ]]; then
  sed -E 's/port: 127\.0\.0\.1:(8080|8443):/port: 0.0.0.0:\1:/' "$CONFIG" > "$cfg"
  warn "EXPOSE=1: ingress 8080/8443 reachable from the network (R5); recreate without EXPOSE after the demo"
else
  cp "$CONFIG" "$cfg"
fi

info "creating cluster $CLUSTER_NAME ..."
k3d cluster create --config "$cfg" --wait --timeout 300s

kc wait --for=condition=Ready node --all --timeout=120s >/dev/null

# Traefik is installed by a Helm job after the server starts; wait for it to exist.
for _ in $(seq 60); do
  kc -n kube-system get deploy traefik >/dev/null 2>&1 && break
  sleep 2
done
kc -n kube-system wait --for=condition=Available deploy --all --timeout=300s >/dev/null

ok "cluster $CLUSTER_NAME ready (context $KUBE_CONTEXT)"
kc get nodes -L topology.kubernetes.io/zone
if [[ $EXPOSE == 1 ]]; then
  info "ingress: http://<this-host>:8080  https://<this-host>:8443"
else
  info "ingress: http://localhost:8080  https://localhost:8443   API: https://127.0.0.1:6550"
fi
