#!/usr/bin/env bash

set -euo pipefail

_cluster="${1:-}"
_service="${2:-}"
_min_capacity="${3:-1}"
_max_capacity="${4:-2}"

aws application-autoscaling register-scalable-target \
    --service-namespace ecs \
    --scalable-dimension ecs:service:DesiredCount \
    --resource-id service/$_cluster/$_service \
    --min-capacity $_min_capacity \
    --max-capacity $_max_capacity
