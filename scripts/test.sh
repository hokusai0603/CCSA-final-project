#!/usr/bin/env bash
# make test: unit tests for every service project, identical locally and in CI.
#   - Node projects (services/*/package.json): `npm test`
#   - Python projects (services/**/pyproject.toml, uv): `uv run pytest`
# Projects are discovered (scripts/projects.sh), so a new service is tested as soon
# as it exists. With no projects yet this passes and says so.
source "$(dirname "$0")/lib.sh"
source "$REPO_ROOT/scripts/projects.sh"
cd "$REPO_ROOT"

count=0
mapfile -t nodes < <(node_projects)
for dir in "${nodes[@]}"; do
  info "== $dir (node)"
  npm_install "$dir"
  require_npm_script "$dir" test
  (cd "$dir" && npm test --silent)
  ok "$dir: npm test"
  count=$((count + 1))
done

mapfile -t pythons < <(python_projects)
for dir in "${pythons[@]}"; do
  info "== $dir (python)"
  (cd "$dir" && uv_run pytest)
  ok "$dir: pytest"
  count=$((count + 1))
done

if ((count == 0)); then
  info "test: no service projects yet (added by P1 tasks); nothing to run"
else
  info "test: $count project(s) passed"
fi
