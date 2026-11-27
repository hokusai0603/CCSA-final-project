#!/usr/bin/env bash
# make lint: static checks, identical locally and in CI (.github/workflows/ci.yml).
#   - shellcheck for scripts/*.sh
#   - Makefile contract: every script a target calls exists and is executable
#   - Node projects (services/*/package.json): `npm run lint`
#   - Python projects (services/**/pyproject.toml, uv): `uv run ruff check .`
#   - Helm chart (deploy/helm/drawguess): `helm lint` + `helm template` per values file
#   - Grafana dashboards: valid JSON
# Projects are discovered, so a new service is linted as soon as it exists.
source "$(dirname "$0")/lib.sh"
source "$REPO_ROOT/scripts/projects.sh"
cd "$REPO_ROOT"

info "== shellcheck"
require_tool shellcheck
shellcheck -x -P scripts scripts/*.sh
ok "shellcheck: $(find scripts -maxdepth 1 -name '*.sh' | wc -l) scripts clean"

info "== Makefile contract"
missing=0
while read -r s; do
  if [[ ! -x $s ]]; then fail "Makefile calls $s, which is missing or not executable"; missing=1; fi
done < <(grep -oE 'scripts/[A-Za-z0-9_-]+\.sh' Makefile | sort -u)
((missing == 0)) || exit 1
make -s help >/dev/null
ok "every script called by the Makefile exists; make help works"

mapfile -t nodes < <(node_projects)
for dir in "${nodes[@]}"; do
  info "== $dir (node)"
  npm_install "$dir"
  require_npm_script "$dir" lint
  (cd "$dir" && npm run --silent lint)
  ok "$dir: npm run lint"
done

mapfile -t pythons < <(python_projects)
for dir in "${pythons[@]}"; do
  info "== $dir (python)"
  (cd "$dir" && uv_run ruff check .)
  ok "$dir: ruff check"
done

chart=deploy/helm/drawguess
if [[ -f $chart/Chart.yaml ]]; then
  info "== helm chart $chart"
  require_tool helm
  shopt -s nullglob
  values=("$chart"/values-*.yaml)
  shopt -u nullglob
  # image.tag is required (make deploy passes the git SHA); any value renders the chart.
  hc lint "$chart" --set image.tag=lint
  for v in "${values[@]}"; do
    hc lint "$chart" -f "$v" --set image.tag=lint
    hc template drawguess "$chart" -f "$v" --set image.tag=lint >/dev/null
    ok "helm lint + template with $v"
  done
else
  info "== helm chart: $chart/Chart.yaml not there yet (P2-1), skipped"
fi

shopt -s nullglob
dashboards=(deploy/monitoring/dashboards/*.json)
shopt -u nullglob
for d in "${dashboards[@]}"; do
  python3 -m json.tool "$d" >/dev/null || die "invalid JSON: $d"
done
((${#dashboards[@]} == 0)) || ok "${#dashboards[@]} dashboard(s) are valid JSON"

info "lint: all checks passed"
