#!/usr/bin/env bash
# make stub-image: build only the placeholder service image (services/stub) and, if the
# cluster exists, import it into k3d. `make build` builds it together with every other image.
# Tag: see image_tag in lib.sh (short SHA, or "<sha>-dirty-<hash>" with uncommitted changes).
source "$(dirname "$0")/lib.sh"
require_tool docker k3d git

tag=$(image_tag services/stub)
[[ $tag == *-dirty-* ]] && warn "services/stub has uncommitted changes: tagging ${tag}"
image="drawguess/stub:${tag}"

docker build -t "$image" "$REPO_ROOT/services/stub"
uid=$(docker run --rm --entrypoint id "$image" -u)
[[ $uid != 0 ]] || die "$image runs as root"
ok "built $image (runs as uid $uid)"

if k3d cluster get "$CLUSTER_NAME" >/dev/null 2>&1; then
  k3d image import -c "$CLUSTER_NAME" "$image"
  ok "imported $image into cluster $CLUSTER_NAME"
else
  info "cluster $CLUSTER_NAME not running; import later with: k3d image import -c $CLUSTER_NAME $image"
fi
echo "$image"
