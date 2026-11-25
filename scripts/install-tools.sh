#!/usr/bin/env bash
# make tools: install the pinned CLI toolchain into ~/.local/bin (no sudo).
# Same versions on every developer machine (Linux, or Windows via WSL2) and in CI.
# Every download is checked against its published SHA-256 where one exists.
# Already-installed tools at the right version are skipped.
#
# Node 24 (nvm) and Python 3.12 (uv) are installed separately; see docs/dev-setup.md.
source "$(dirname "$0")/lib.sh"
require_tool curl tar sha256sum

K3D_VERSION=v5.9.0
KUBECTL_VERSION=v1.37.2
HELM_VERSION=v3.22.1
K6_VERSION=v2.4.0
UV_VERSION=0.13.9
SHELLCHECK_VERSION=v0.11.0
ACTIONLINT_VERSION=1.7.12

[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] ||
  die "only linux/x86_64 is supported (on Windows, run inside WSL2)"

BIN="${HOME}/.local/bin"
mkdir -p "$BIN"
case ":$PATH:" in
  *":$BIN:"*) ;;
  *) warn "$BIN is not in PATH; add it in ~/.bashrc: export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

fetch() { curl -fsSL --retry 3 -o "$2" "$1"; }

# have <tool> <version-substring> <version command...>
have() {
  local tool=$1 want=$2
  shift 2
  [[ -x "$BIN/$tool" ]] && "$@" 2>/dev/null | grep -q -- "$want"
}

# check <file> <expected-sha256>
check() {
  echo "$2  $1" | sha256sum -c --quiet - || die "checksum mismatch for $1"
}

install_k3d() {
  have k3d "$K3D_VERSION" "$BIN/k3d" version && return
  fetch "https://github.com/k3d-io/k3d/releases/download/$K3D_VERSION/k3d-linux-amd64" "$work/k3d"
  fetch "https://github.com/k3d-io/k3d/releases/download/$K3D_VERSION/checksums.txt" "$work/k3d.sums"
  check "$work/k3d" "$(awk '/k3d-linux-amd64$/ {print $1}' "$work/k3d.sums")"
  install -m 0755 "$work/k3d" "$BIN/k3d"
}

install_kubectl() {
  have kubectl "$KUBECTL_VERSION" "$BIN/kubectl" version --client && return
  fetch "https://dl.k8s.io/release/$KUBECTL_VERSION/bin/linux/amd64/kubectl" "$work/kubectl"
  check "$work/kubectl" "$(curl -fsSL "https://dl.k8s.io/release/$KUBECTL_VERSION/bin/linux/amd64/kubectl.sha256")"
  install -m 0755 "$work/kubectl" "$BIN/kubectl"
}

install_helm() {
  have helm "$HELM_VERSION" "$BIN/helm" version --short && return
  local t="helm-$HELM_VERSION-linux-amd64.tar.gz"
  fetch "https://get.helm.sh/$t" "$work/$t"
  check "$work/$t" "$(curl -fsSL "https://get.helm.sh/$t.sha256sum" | awk '{print $1}')"
  tar -xzf "$work/$t" -C "$work" linux-amd64/helm
  install -m 0755 "$work/linux-amd64/helm" "$BIN/helm"
}

install_k6() {
  have k6 "$K6_VERSION" "$BIN/k6" version && return
  local t="k6-$K6_VERSION-linux-amd64.tar.gz"
  fetch "https://github.com/grafana/k6/releases/download/$K6_VERSION/$t" "$work/$t"
  check "$work/$t" "$(curl -fsSL "https://github.com/grafana/k6/releases/download/$K6_VERSION/k6-$K6_VERSION-checksums.txt" | awk -v f="$t" '$2 == f {print $1}')"
  tar -xzf "$work/$t" -C "$work"
  install -m 0755 "$work/k6-$K6_VERSION-linux-amd64/k6" "$BIN/k6"
}

install_uv() {
  have uv "$UV_VERSION" "$BIN/uv" --version && return
  local t="uv-x86_64-unknown-linux-gnu.tar.gz"
  fetch "https://github.com/astral-sh/uv/releases/download/$UV_VERSION/$t" "$work/$t"
  check "$work/$t" "$(curl -fsSL "https://github.com/astral-sh/uv/releases/download/$UV_VERSION/$t.sha256" | awk '{print $1}')"
  tar -xzf "$work/$t" -C "$work"
  install -m 0755 "$work/uv-x86_64-unknown-linux-gnu/uv" "$work/uv-x86_64-unknown-linux-gnu/uvx" "$BIN/"
}

install_shellcheck() {
  have shellcheck "${SHELLCHECK_VERSION#v}" "$BIN/shellcheck" --version && return
  # No checksum file is published for this tool; the download is pinned by version over HTTPS.
  local t="shellcheck-$SHELLCHECK_VERSION.linux.x86_64.tar.xz"
  fetch "https://github.com/koalaman/shellcheck/releases/download/$SHELLCHECK_VERSION/$t" "$work/$t"
  tar -xJf "$work/$t" -C "$work"
  install -m 0755 "$work/shellcheck-$SHELLCHECK_VERSION/shellcheck" "$BIN/shellcheck"
}

install_actionlint() {
  have actionlint "$ACTIONLINT_VERSION" "$BIN/actionlint" -version && return
  local t="actionlint_${ACTIONLINT_VERSION}_linux_amd64.tar.gz"
  fetch "https://github.com/rhysd/actionlint/releases/download/v$ACTIONLINT_VERSION/$t" "$work/$t"
  check "$work/$t" "$(curl -fsSL "https://github.com/rhysd/actionlint/releases/download/v$ACTIONLINT_VERSION/actionlint_${ACTIONLINT_VERSION}_checksums.txt" | awk -v f="$t" '$2 == f {print $1}')"
  tar -xzf "$work/$t" -C "$work" actionlint
  install -m 0755 "$work/actionlint" "$BIN/actionlint"
}

version_of() {
  case $1 in
    kubectl) "$BIN/kubectl" version --client | head -1 ;;
    helm) "$BIN/helm" version --short ;;
    k3d | k6) "$BIN/$1" version | head -1 ;;
    shellcheck) "$BIN/shellcheck" --version | sed -n 2p ;;
    actionlint) "$BIN/actionlint" -version | head -1 ;;
    *) "$BIN/$1" --version | head -1 ;;
  esac
}

for t in k3d kubectl helm k6 uv shellcheck actionlint; do
  "install_$t"
  ok "$t: $(version_of "$t")"
done
info "tools installed in $BIN; next: nvm install (Node 24, reads .nvmrc), uv python install 3.12"
