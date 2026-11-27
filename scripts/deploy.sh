#!/usr/bin/env bash
# make deploy ENV=dev|prod: helm upgrade --install the chart into namespace drawguess-<env>
# with values-<env>.yaml and image.tag = the tag `make build` used (image_tag in lib.sh).
# drawguess/* images exist only locally (no registry), so before installing, every one
# the chart references must exist in local Docker; images missing from the cluster nodes
# (e.g. after a cluster-down/up) are imported again.
source "$(dirname "$0")/lib.sh"
require_tool helm kubectl docker k3d

env=${1:-dev}
[[ $env == dev || $env == prod ]] || die "ENV must be dev or prod, got: $env"
ns="drawguess-$env"
chart="$REPO_ROOT/deploy/helm/drawguess"
values="$chart/values-$env.yaml"

k3d cluster get "$CLUSTER_NAME" >/dev/null 2>&1 || die "cluster $CLUSTER_NAME is not running: make cluster-up first"
tag=$(image_tag services)

mapfile -t refs < <(hc template drawguess "$chart" -n "$ns" -f "$values" --set image.tag="$tag" |
  sed -nE 's/^ *image: *"?(drawguess\/[^" ]+)"? *$/\1/p' | sort -u)
node="k3d-${CLUSTER_NAME}-agent-0"
missing=()
for ref in "${refs[@]}"; do
  docker image inspect "$ref" >/dev/null 2>&1 || die "image $ref not built for this tree: run make build"
  docker exec "$node" crictl inspecti "docker.io/$ref" >/dev/null 2>&1 || missing+=("$ref")
done
if ((${#missing[@]})); then
  info "importing ${#missing[@]} image(s) missing from the cluster nodes"
  k3d image import -c "$CLUSTER_NAME" "${missing[@]}" >/dev/null
fi
ok "images present: ${refs[*]}"

hc upgrade --install drawguess "$chart" -n "$ns" --create-namespace \
  -f "$values" --set image.tag="$tag" --wait --timeout 5m
kc -n "$ns" get pods -o wide

host=$(hc get values drawguess -n "$ns" --all -o json | sed -nE 's/.*"host":"([^"]*)".*/\1/p' | head -1)
ok "deployed $ns with image tag $tag: http://${host:-localhost}:8080/"
