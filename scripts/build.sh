#!/usr/bin/env bash
# make build: build every image and import it into the k3d cluster.
#   - services/<name>/Dockerfile  -> drawguess/<name>:<tag>   (stub included)
# One tag for all images: the short git SHA, or "<sha>-dirty-<hash>" when services/ has
# uncommitted changes (image_tag in lib.sh; chart-only edits keep the tag). `make deploy` computes the same tag.
# Each image must run as a non-root user (AGENTS.md rule 6); the build fails otherwise.
source "$(dirname "$0")/lib.sh"
require_tool docker k3d git

k3d cluster get "$CLUSTER_NAME" >/dev/null 2>&1 || die "cluster $CLUSTER_NAME is not running: make cluster-up first"

tag=$(image_tag services)
[[ $tag == *-dirty-* ]] && warn "uncommitted changes: tagging ${tag} (commit for a clean SHA tag)"

images=()
shopt -s nullglob
for dockerfile in "$REPO_ROOT"/services/*/Dockerfile; do
  dir=$(dirname "$dockerfile")
  image="drawguess/$(basename "$dir"):${tag}"
  info "== building $image"
  docker build -q -t "$image" "$dir" >/dev/null
  uid=$(docker run --rm --entrypoint id "$image" -u)
  [[ $uid != 0 ]] || die "$image runs as root (AGENTS.md rule 6)"
  ok "built $image (uid $uid)"
  images+=("$image")
done
shopt -u nullglob
((${#images[@]})) || die "no services/*/Dockerfile found"

k3d image import -c "$CLUSTER_NAME" "${images[@]}" >/dev/null
ok "imported ${#images[@]} image(s) into cluster $CLUSTER_NAME with tag $tag"
