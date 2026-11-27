# shellcheck shell=bash
# Common helpers for every script behind the Makefile. Source it, do not run it:
#   source "$(dirname "$0")/lib.sh"
#
# Safety guarantees every script gets by sourcing this file (see docs/host-environment.md):
#   - refuses to run as root (R6: `sudo kubectl` on a host that also runs k3s would
#     talk to the host cluster, not ours);
#   - all kubectl / helm calls go through kc / hc, pinned to the k3d context (R6).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO_ROOT

CLUSTER_NAME="${CLUSTER_NAME:-drawguess}"
KUBE_CONTEXT="k3d-${CLUSTER_NAME}"
export CLUSTER_NAME KUBE_CONTEXT

# Docker Hub pull-through cache shared by every recreated cluster (R2).
# k3d prefixes registry names with "k3d-"; cluster.yaml refers to the container name.
CACHE_NAME="${CLUSTER_NAME}-cache"
CACHE_CONTAINER="k3d-${CACHE_NAME}"
CACHE_PORT="${CACHE_PORT:-5005}"
CACHE_VOLUME="${CLUSTER_NAME}-registry-cache"
CACHE_IMAGE="registry:2.8.3"
export CACHE_NAME CACHE_CONTAINER CACHE_PORT CACHE_VOLUME CACHE_IMAGE

if [[ -t 2 ]]; then
  _c_red=$'\e[31m' _c_yel=$'\e[33m' _c_grn=$'\e[32m' _c_off=$'\e[0m'
else
  _c_red='' _c_yel='' _c_grn='' _c_off=''
fi

info() { printf '%s\n' "$*" >&2; }
ok()   { printf '%sPASS%s %s\n' "$_c_grn" "$_c_off" "$*" >&2; }
warn() { printf '%sWARN%s %s\n' "$_c_yel" "$_c_off" "$*" >&2; }
fail() { printf '%sFAIL%s %s\n' "$_c_red" "$_c_off" "$*" >&2; }
die()  { fail "$*"; exit 1; }

# Exit code 2 = "not implemented yet", distinct from real failures (1).
not_implemented() {
  local target=$1 task=$2
  printf '%s: not implemented yet (roadmap task %s, see docs/roadmap.md)\n' "$target" "$task" >&2
  exit 2
}

require_non_root() {
  if [[ $EUID -eq 0 ]]; then
    die "do not run as root: under sudo, kubectl/helm may reach the host's own cluster instead of ${KUBE_CONTEXT} (docs/host-environment.md R6)"
  fi
}

require_tool() {
  local t
  for t in "$@"; do
    command -v "$t" >/dev/null 2>&1 || die "missing tool: $t (see README prerequisites)"
  done
}

# kubectl / helm pinned to our cluster. Never call bare kubectl/helm in scripts.
kc() { command kubectl --context "$KUBE_CONTEXT" "$@"; }
hc() { command helm --kube-context "$KUBE_CONTEXT" "$@"; }

# Short git SHA used as the image tag (never `latest`, AGENTS.md rule 6).
git_sha() { git -C "$REPO_ROOT" rev-parse --short HEAD; }

# Image tag for the given repo paths (default: the whole repo): the short SHA, or
# "<sha>-dirty-<content hash>" if those paths have uncommitted changes. The hash makes
# every edit produce a new tag; reusing one "-dirty" tag would leave k3d nodes on the
# image imported first (same tag, so IfNotPresent never replaces it).
image_tag() {
  local paths=("$@") sha content
  ((${#paths[@]})) || paths=(.)
  sha=$(git_sha)
  if [[ -z $(git -C "$REPO_ROOT" status --porcelain -- "${paths[@]}") ]]; then
    echo "$sha"
    return
  fi
  content=$(cd "$REPO_ROOT" && find "${paths[@]}" -type f -not -path '*/node_modules/*' -not -path '*/.git/*' \
    -not -path '*/.venv/*' -not -path '*/__pycache__/*' -print0 | sort -z | xargs -0 sha256sum | sha256sum | cut -c1-8)
  echo "${sha}-dirty-${content}"
}

require_non_root
