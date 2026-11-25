#!/usr/bin/env bash
# make demo-<n>: run demo scenario n from docs/demo-scenarios.md via scripts/demo-<n>.sh.
# Task P3-4 adds demo-1.sh … demo-10.sh; each must start with `scripts/preflight.sh --measure` (R4).
source "$(dirname "$0")/lib.sh"
n=${1:?usage: demo.sh <1-10>}
[[ $n =~ ^([1-9]|10)$ ]] || die "demo number must be 1-10, got: $n"
script="$(dirname "$0")/demo-$n.sh"
[[ -x $script ]] && exec "$script"
not_implemented "demo-$n" P3-4
