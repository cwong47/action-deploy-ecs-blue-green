#!/usr/bin/env bash

set -euo pipefail

fn_usage() {
    local exit_status="${1:-1}"

    echo "Usage: ${0##*/} -z HostedZoneID -n ZoneName -b ServiceBlue -g ServiceGreen -c ECSCluster [ -m RegEx ]" 1>&2
    echo "       -z HostedZoneID        Hosted zone ID." 1>&2
    echo "       -n ZoneName            Zone name or domain name with trailing dot(.)." 1>&2
    echo "       -b ServiceBlue         ECS service name of the 'blue' cluster." 1>&2
    echo "       -g ServiceGreen        ECS service name of the 'green' cluster." 1>&2
    echo "       -g ECSCluster          ECS cluster name." 1>&2
    echo "       -m RegEx               (Optional) SetIdentifier pattern." 1>&2
    exit "$exit_status"
}

[[ "$#" -lt 1 ]] && fn_usage 1
while getopts ":z:n:b:g:c:m:" opt; do
    case "$opt" in
        z)
            hosted_zone_id=$OPTARG
            ;;
        n)
            zone_name=$OPTARG
            ;;
        b)
            service_blue=$OPTARG
            ;;
        g)
            service_green=$OPTARG
            ;;
        c)
            ecs_cluster=$OPTARG
            ;;
        m)
            regex=$OPTARG
            ;;
        \?)
            echo "Invalid option: -$OPTARG" 1>&2
            fn_usage 1
            ;;
        :)
            echo "Option -$OPTARG requires an argument ..." 1>&2
            fn_usage 1
            ;;
    esac
done

[[ -z "${hosted_zone_id:-}" ]] && fn_usage 1
[[ -z "${zone_name:-}" ]] && fn_usage 1
[[ -z "${service_blue:-}" ]] && fn_usage 1
[[ -z "${service_green:-}" ]] && fn_usage 1
[[ -z "${ecs_cluster:-}" ]] && fn_usage 1

regex=${regex:-"blue|green"}
weight_primary=${WEIGHT_PRIMARY:-255}
weight_secondary=${WEIGHT_SECONDARY:-0}
route53_output=$(aws route53 list-resource-record-sets --hosted-zone-id "$hosted_zone_id" | \
    jq \
        --arg zone_name "$zone_name" \
        '.ResourceRecordSets[] | select (.Name == $zone_name)' | \
            jq --slurp -c)
pending_primary_json=$(echo "$route53_output" | \
    jq \
        -c \
        -r \
        --arg zone_name "$zone_name" \
        --arg weight "$weight_primary" \
        --arg regex "$regex" \
        '[.[] | select(.SetIdentifier? | match($regex))] | sort_by(.Weight) | .[0] | .Weight=($weight | fromjson)')
original_secondary_zone_id=$(echo "$pending_primary_json" | jq -r '.SetIdentifier')
cluster_secondary_suffix=${original_secondary_zone_id##*-}
pending_secondary_json=$(echo "$route53_output" | \
    jq \
        -c \
        -r \
        --arg zone_name "$zone_name" \
        --arg weight "$weight_secondary" \
        --arg regex "$regex" \
        '[.[] | select(.SetIdentifier? | match($regex))] | sort_by(-.Weight) | .[0] | .Weight=($weight | fromjson)')
original_primary_zone_id=$(echo "$pending_secondary_json" | jq -r '.SetIdentifier')
cluster_primary_suffix=${original_primary_zone_id##*-}

case $service_blue in
    *$cluster_primary_suffix)
        original_primary_service="$service_blue"
        original_secondary_service="$service_green"
        ;;
    *$cluster_secondary_suffix)
        original_primary_service="$service_green"
        original_secondary_service="$service_blue"
        ;;
esac

pending_primary_json_base64=$(echo '{"Comment":"Updating DNS weight via '"${0##*/}"'","Changes":[{"Action":"UPSERT","ResourceRecordSet":'"${pending_primary_json}"'}]}' | base64 -w 0)
pending_secondary_json_base64=$(echo '{"Comment":"Updating DNS weight via '"${0##*/}"'","Changes":[{"Action":"UPSERT","ResourceRecordSet":'"${pending_secondary_json}"'}]}' | base64 -w 0)

echo "::set-output name=original_primary_zone_id::$original_primary_zone_id"
echo "::set-output name=original_secondary_zone_id::$original_secondary_zone_id"
echo "::set-output name=original_primary_service::$original_primary_service"
echo "::set-output name=original_secondary_service::$original_secondary_service"
echo "::set-output name=pending_primary_json::$pending_primary_json_base64"
echo "::set-output name=pending_secondary_json::$pending_secondary_json_base64"

original_primary_autoscale_output=$(aws application-autoscaling describe-scalable-targets \
    --service-namespace ecs | \
    jq --arg resource_id \
        "service/$ecs_cluster/$original_primary_service" \
        '.ScalableTargets[] | select(.ResourceId == $resource_id)')

echo "::set-output name=original_primary_min_capacity::$(echo $original_primary_autoscale_output| jq -r '.MinCapacity')"
echo "::set-output name=original_primary_max_capacity::$(echo $original_primary_autoscale_output| jq -r '.MaxCapacity')"

original_secondary_autoscale_output=$(aws application-autoscaling describe-scalable-targets \
    --service-namespace ecs | \
    jq --arg resource_id \
        "service/$ecs_cluster/$original_secondary_service" \
        '.ScalableTargets[] | select(.ResourceId == $resource_id)')

echo "::set-output name=original_secondary_min_capacity::$(echo $original_secondary_autoscale_output| jq -r '.MinCapacity')"
echo "::set-output name=original_secondary_max_capacity::$(echo $original_secondary_autoscale_output| jq -r '.MaxCapacity')"
