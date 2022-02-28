# AWS ECS blue-green Deployment for Github Actions

This action collects Route53 and ECS autoscaling information needed for blue-green deployment.

ECS blue-green deploy consist of 5 steps.

1. Get blue-green status from Route53
    - prepare the route53 record JSONs
    - determine the current primary/secondary services
    - determine the current min/max capacity for primary/secondary services
1. Scale up original secondary cluster
1. Download and update task-definition with new ECR image-id, then upload back to AWS
    - ***Note:*** This action does not cover this step!
1. Update Route53 weight for blue-green
1. Scale down original primary cluster

## Contents

- [Usage Examples](#usage-examples)
- [Supported Parameters](#supported-parameters)
    - [Github Action Inputs](#github-action-inputs)
    - [Github Action Outputs](#github-action-outputs)
- [Event Triggers](#event-triggers)
- [Versioning](#versioning)
- [License](#license)

## Usage Examples

### Inject your production Cloudflare API tokens into a build

```yaml
---
name: deploy-blue-green

on:
  workflow_dispatch:
  push:
    branches:
      - main

env:
  AWS_ACCOUNT_ID_QA: 123456789012
  AWS_DEFAULT_REGION: us-west-2
  AWS_DEFAULT_OUTPUT: json

  HOSTED_ZONE_ID: Z123456789ABC1
  ZONE_NAME: rest-service.qa.my-company.com.
  ECS_CLUSTER: qa-default-01
  SERVICE_BLUE: qa-rest-service-blue
  SERVICE_GREEN: qa-rest-service-green
  REPOSITORY_NAME: rest-service

permissions:
  id-token: write
  contents: write
  actions: read

jobs:
  deploy-blue-green:
    runs-on: ubuntu-latest
    steps:
      - name: Get blue-green status [QA]
        uses: "cwong47/action-deploy-ecs-blue-green@latest"
        id: get-blue-green-info
        with:
          action: get-blue-green-info
          hosted_zone_id: ${{ env.HOSTED_ZONE_ID }}
          zone_name: ${{ env.ZONE_NAME }}
          ecs_service_blue: ${{ env.SERVICE_BLUE }}
          ecs_service_green: ${{ env.SERVICE_GREEN }}
          ecs_cluster: ${{ env.ECS_CLUSTER }}

      - name: Scale up original secondary cluster [QA]
        uses: "cwong47/action-deploy-ecs-blue-green@latest"
        id: update-secondary-autoscale-capacity
        with:
          action: update-autoscale-capacity
          ecs_cluster: ${{ env.ECS_CLUSTER }}
          ecs_service: ${{ steps.get-blue-green-info.outputs.original_secondary_service }}
          min_capacity: ${{ steps.get-blue-green-info.outputs.original_primary_min_capacity }}
          max_capacity: ${{ steps.get-blue-green-info.outputs.original_primary_max_capacity }}

... *** deploy task-definition ***

      - name: Update Route53 weight for blue-green [QA]
        uses: "cwong47/action-deploy-ecs-blue-green@latest"
        id: update-primary-dns-weight
        with:
          action: update-dns-weight
          action: update-dns-weight
          hosted_zone_id: ${{ env.HOSTED_ZONE_ID }}
          primary_route53_json: ${{ steps.get-blue-green-info.outputs.pending_primary_json }}
          secondary_route53_json: ${{ steps.get-blue-green-info.outputs.pending_secondary_json }}

      - name: Scale down original primary cluster [QA]
        uses: "cwong47/action-deploy-ecs-blue-green@latest"
        id: update-primary-autoscale-capacity
        with:
          action: update-autoscale-capacity
          ecs_cluster: ${{ env.ECS_CLUSTER }}
          ecs_service: ${{ steps.get-blue-green-info.outputs.original_primary_service }}
          min_capacity: ${{ steps.get-blue-green-info.outputs.original_secondary_min_capacity }}
          max_capacity: ${{ steps.get-blue-green-info.outputs.original_secondary_max_capacity }}
```

## Supported Parameters

These environment variables need to be set in the action yml file in order to work properly.

| Variable           | Description                                        |
| ------------------ | -------------------------------------------------- |
| AWS_ACCOUNT_ID_QA  | AWS account ID                                     |
| AWS_DEFAULT_REGION | us-west-2                                          |
| AWS_DEFAULT_OUTPUT | json                                               |
| HOSTED_ZONE_ID     | DNS zone ID (Z123456789ABC1)                       |
| ZONE_NAME          | DNS domain name (rest-service.qa.my-company.com.)  |
| ECS_CLUSTER        | ECS cluster name                                   |
| SERVICE_BLUE       | First ECS service name                             |
| SERVICE_GREEN      | Second ECS service name                            |

### Github Action Inputs

| Parameter                  | Description                                                  | Default |
| -------------------------- | ------------------------------------------------------------ | ------- |
| `action`\*                 | What step to execute                                         | `null`  |
| `dry_run`\*                | Dry run                                                      | `false` |
| `hosted_zone_id`\*         | Hosted zone ID from Route53                                  | `null`  |
| `zone_name`\*              | Zone name from Route53                                       | `null`  |
| `ecs_service_blue`\*       | The "blue" cluster of your ECS service                       | `null`  |
| `ecs_service_green`\*      | The "green" cluster of your ECS service                      | `null`  |
| `set_identifier_pattern`\* | Default is `"blue\|green"`                                   | `null`  |
| `primary_route53_json`\*   | Primary Route53 record in JSON format in `base64` encoding   | `null`  |
| `secondary_route53_json`\* | Secondary Route53 record in JSON format in `base64` encoding | `null`  |
| `ecs_cluster`\*            | The ECS cluster                                              | `null`  |
| `ecs_service`\*            | The cluster of your ECS service                              | `null`  |
| `min_capacity`\*           | Minimum capacity to autoscale the service                    | `null`  |
| `max_capacity`\*           | Maximum capacity to autoscale the service                    | `null`  |

### Github Action Outputs

| Parameter                         | Description                                       |
| --------------------------------- | ------------------------------------------------- |
| `original_primary_zone_id`        | Original primary zone ID                          |
| `original_secondary_zone_id`      | Original secondary zone ID                        |
| `original_primary_service`        | Original primary service                          |
| `original_secondary_service`      | Original secondary service                        |
| `original_primary_min_capacity`   | Original primary minimum capacity for autoscale   |
| `original_secondary_min_capacity` | Original secondary minimum capacity for autoscale |
| `original_primary_max_capacity`   | Original primary maximum capacity for autoscale   |
| `original_secondary_max_capacity` | Original secondary maximum capacity for autoscale |
| `pending_primary_json`            | Pending primary JSON in base64 encoding           |
| `pending_secondary_json`          | Pending secondary JSON in base64 encoding         |

### Notes:

- Parameters denoted with `*` are required.

## Versioning

Every commit that lands on master for this project triggers an automatic build as well as a tagged release called `latest`. If you don't wish to live on the bleeding edge you may use a stable release instead. See [releases](../../releases/latest) for the available versions.

```yaml
- uses: "cwong47/action-deploy-ecs-blue-green@<VERSION>"
```

## License

The source code for this project is released under the [MIT License](/LICENSE). This project is not associated with GitHub or AWS.
