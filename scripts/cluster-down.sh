#!/usr/bin/env bash
# make cluster-down: delete the k3d cluster. Only this cluster's containers are
# touched (k3d cluster delete), never a global prune (R5). The image cache is
# kept on purpose so the next cluster-up does not pull from Docker Hub again
# (R2); remove it with `make cache-down`.
source "$(dirname "$0")/lib.sh"
require_tool k3d

if ! k3d cluster get "$CLUSTER_NAME" >/dev/null 2>&1; then
  info "cluster $CLUSTER_NAME does not exist; nothing to do"
  exit 0
fi

k3d cluster delete "$CLUSTER_NAME"
ok "cluster $CLUSTER_NAME deleted (image cache $CACHE_CONTAINER kept)"
