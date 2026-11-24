# shellcheck shell=bash
# Service project discovery shared by lint.sh and test.sh. Source after lib.sh.
#
# Conventions (AGENTS.md §6):
#   Node project   = services/<name>/package.json with `lint` and `test` npm scripts,
#                    package-lock.json committed (CI uses `npm ci`).
#   Python project = a pyproject.toml under services/ (max depth 3) managed by uv,
#                    uv.lock committed, ruff + pytest as dev dependencies.

# Both print paths relative to REPO_ROOT; callers run from REPO_ROOT.
node_projects() {
  local pj
  for pj in "$REPO_ROOT"/services/*/package.json; do
    [[ -e $pj ]] && dirname "${pj#"$REPO_ROOT"/}"
  done
  return 0
}

python_projects() {
  (cd "$REPO_ROOT" && find services -maxdepth 3 -name pyproject.toml -not -path '*/node_modules/*' \
    -printf '%h\n' 2>/dev/null | sort)
}

# Install Node dependencies: always clean in CI, only when missing locally.
npm_install() {
  local dir=$1 major
  require_tool node npm
  major=$(node -p 'process.versions.node.split(".")[0]')
  ((major >= 24)) || die "node $(node -v) found, Node 24 required (run: nvm use)"
  if [[ -n ${CI:-} || ! -d $dir/node_modules ]]; then
    [[ -f $dir/package-lock.json ]] || die "$dir: package-lock.json missing (commit it; CI uses npm ci)"
    (cd "$dir" && npm ci --no-audit --no-fund)
  fi
}

require_npm_script() {
  local dir=$1 name=$2
  (cd "$dir" && node -e "process.exit(require('./package.json').scripts?.['$name'] ? 0 : 1)") ||
    die "$dir: package.json has no \"$name\" script (required by AGENTS.md §6)"
}

# `uv run` that, in CI, requires uv.lock to already match pyproject.toml.
uv_run() {
  require_tool uv
  local flags=()
  if [[ -n ${CI:-} ]]; then flags=(--locked); fi
  uv run "${flags[@]}" "$@"
}
