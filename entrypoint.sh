#!/usr/bin/env bash

set -euo pipefail

if [[ "${INPUT_DRY_RUN:-}" == "true" ]]; then
    env | grep INPUT | sort
else
    case "${INPUT_ACTION:-}" in
        get-blue-green-info)
            /${INPUT_ACTION:-}.sh \
                -z "${INPUT_HOSTED_ZONE_ID:-}" \
                -n "${INPUT_ZONE_NAME:-}" \
                -b "${INPUT_ECS_SERVICE_BLUE:-}" \
                -g "${INPUT_ECS_SERVICE_GREEN:-}" \
                -c "${INPUT_ECS_CLUSTER:-}"
            ;;
        update-autoscale-capacity)
            /${INPUT_ACTION:-}.sh \
                "${INPUT_ECS_CLUSTER:-}" \
                "${INPUT_ECS_SERVICE:-}" \
                "${INPUT_MIN_CAPACITY:-}" \
                "${INPUT_MAX_CAPACITY:-}"
            ;;
        update-dns-weight)
            /${INPUT_ACTION:-}.sh \
                "${INPUT_HOSTED_ZONE_ID:-}" \
                "${INPUT_PRIMARY_ROUTE53_JSON:-}"
            /${INPUT_ACTION:-}.sh \
                "${INPUT_HOSTED_ZONE_ID:-}" \
                "${INPUT_SECONDARY_ROUTE53_JSON:-}"
            ;;
    esac
fi
