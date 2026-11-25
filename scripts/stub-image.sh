#!/usr/bin/env bash
# make stub-image: build the placeholder service image (services/stub) and, if the
# cluster exists, import it into k3d. Tag = short git SHA (AGENTS.md rule 6); a
# working tree with uncommitted changes in services/stub gets "<sha>-dirty".
source "$(dirname "$0")/lib.sh"
require_tool docker k3d git

ctx="$REPO_ROOT/services/stub"
tag=$(git_sha)
if [[ -n $(git -C "$REPO_ROOT" status --porcelain -- services/stub) ]]; then
  # Content hash in the tag: reusing one "-dirty" tag would leave k3d nodes on the
  # previously imported image (same tag, so IfNotPresent never replaces it).
  content=$(cd "$REPO_ROOT" && find services/stub -type f -not -path '*/node_modules/*' -print0 |
    sort -z | xargs -0 sha256sum | sha256sum | cut -c1-8)
  tag="${tag}-dirty-${content}"
  warn "services/stub has uncommitted changes: tagging ${tag}"
fi
image="drawguess/stub:${tag}"

docker build -t "$image" "$ctx"
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
