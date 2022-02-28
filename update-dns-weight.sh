#!/usr/bin/env bash

set -euo pipefail

_hosted_zone_id="${1:-}"
_route53_record_json="${2:-}"

aws route53 change-resource-record-sets \
    --hosted-zone-id $_hosted_zone_id \
    --change-batch "$(echo $_route53_record_json | base64 -d)"
