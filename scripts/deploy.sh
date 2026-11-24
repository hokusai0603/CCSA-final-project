#!/usr/bin/env bash
# make deploy: helm upgrade --install the chart with values-$ENV.yaml (usage: deploy.sh dev|prod).
# Task P2-2 replaces this stub.
source "$(dirname "$0")/lib.sh"
env=${1:-dev}
[[ $env == dev || $env == prod ]] || die "ENV must be dev or prod, got: $env"
not_implemented deploy P2-2
