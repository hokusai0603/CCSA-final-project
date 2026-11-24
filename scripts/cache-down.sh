#!/usr/bin/env bash
# make cache-down: remove the Docker Hub pull-through cache registry and its volume (R2).
# Refuses while the cluster exists, because its nodes pull docker.io images through it.
source "$(dirname "$0")/lib.sh"
require_tool k3d docker

if k3d cluster get "$CLUSTER_NAME" >/dev/null 2>&1; then
  die "cluster $CLUSTER_NAME still uses the cache; run make cluster-down first"
fi

if docker container inspect "$CACHE_CONTAINER" >/dev/null 2>&1; then
  k3d registry delete "$CACHE_CONTAINER"
  ok "registry $CACHE_CONTAINER deleted"
else
  info "registry $CACHE_CONTAINER does not exist"
fi

if docker volume inspect "$CACHE_VOLUME" >/dev/null 2>&1; then
  docker volume rm "$CACHE_VOLUME" >/dev/null
  ok "volume $CACHE_VOLUME removed"
fi
