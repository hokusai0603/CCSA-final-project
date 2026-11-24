#!/usr/bin/env bash
# Raise inotify limits for a multi-node k3d cluster (run once with sudo).
# k3d nodes run as root and share root's inotify quota with anything else on the
# host (e.g. a host k3s); the Ubuntu default of 128 instances causes
# "too many open files" in pods / `kubectl logs -f`.
# Usage: sudo scripts/host-sysctl.sh
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "run with sudo: sudo $0" >&2
  exit 1
fi

conf=/etc/sysctl.d/99-k3d-inotify.conf
declare -A want=(
  [fs.inotify.max_user_instances]=1024
  [fs.inotify.max_user_watches]=524288
)

: > "$conf.tmp"
for key in "${!want[@]}"; do
  cur=$(sysctl -n "$key")
  val=${want[$key]}
  (( cur > val )) && val=$cur   # never lower an existing higher value
  echo "$key = $val" >> "$conf.tmp"
done
mv "$conf.tmp" "$conf"

sysctl -p "$conf"
echo "written $conf (persists across reboots)"
