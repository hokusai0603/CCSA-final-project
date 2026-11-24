# scripts

Implementations behind the Makefile targets in `AGENTS.md` §6 (cluster-up, build, deploy, demo-1 … demo-9, …). Tasks: P0-1, P3-4.

Conventions:

- Every script starts with `source "$(dirname "$0")/lib.sh"`. That gives `set -euo pipefail`, a root guard, `kc` / `hc` (kubectl / helm pinned to `k3d-drawguess`), `info` / `ok` / `warn` / `fail` / `die`, `git_sha`, and `not_implemented <target> <task>` (exit 2).
- A stub script ends with `not_implemented`; the roadmap task named in its header replaces it.
- `demo.sh <n>` dispatches to `demo-<n>.sh`; each demo script starts with `"$(dirname "$0")/preflight.sh" --measure`.
- `host-sysctl.sh` is the only script run as root (`make host-sysctl`); it does not source `lib.sh`.
- Lint: `shellcheck -x -P scripts scripts/*.sh` must be clean.
