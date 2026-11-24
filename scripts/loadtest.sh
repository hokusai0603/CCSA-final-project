#!/usr/bin/env bash
# make loadtest: run the k6 scenario against the cluster (usage: loadtest.sh <players>).
# Task P3-3 replaces this stub.
source "$(dirname "$0")/lib.sh"
players=${1:-200}
[[ $players =~ ^[0-9]+$ ]] || die "PLAYERS must be a number, got: $players"
not_implemented loadtest P3-3
