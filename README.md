# AWS ECS blue-green Deployment for Github Actions

This action deploys weighted DNS blue-green ECS cluster. It collects Route53 and ECS autoscaling information needed for the deployment.

*ECS blue-green deploy consist of 5 steps.*

1. Get blue-green status from Route53
    - prepare the route53 record JSONs
    - determine the current primary/secondary services
    - determine the current min/max capacity for primary/secondary services
1. Scale up original secondary cluster
1. Download and update task-definition with new ECR image-id, then upload back to AWS
    - ***Note:*** This action does not cover this step!
1. Update Route53 weight for blue-green
1. Scale down original primary cluster

## Table of Contents

- [Requirements](#requirements)
- [Usage](#usage)
- [Parameters](#parameters)
    - [Inputs](#inputs)
    - [Outputs](#outputs)
- [License](#license)

## Requirements

Your Github repository will need to access AWS, I recommend going with OpenID Connect instead of AWS credentials.
You can find more details from [Terraform and Github Actions without AWS Credentials](https://cwong47.gitlab.io/technology-terraform-aws-github-actions-no-secrets/).

In your workflow yaml file, you will need the following blocks.

```yaml
env:
  AWS_ACCOUNT_ID_QA: 123456789012
  AWS_DEFAULT_REGION: us-west-2
  AWS_DEFAULT_OUTPUT: json

permissions:
  id-token: write
  contents: write
  actions: read
```

Under the `steps` section, configure AWS credentials via assume-role.

```yaml
      - name: Configure AWS credentials [QA]
        uses: aws-actions/configure-aws-credentials@v1
        with:
          role-to-assume: arn:aws:iam::${{ env.AWS_ACCOUNT_ID_QA }}:role/qa-github-actions
          aws-region: ${{ env.AWS_DEFAULT_REGION }}
```

## Usage

These environment variables need to be set in the action yml file in order to work properly.

| Variable           | Description                                        |
| ------------------ | -------------------------------------------------- |
| HOSTED_ZONE_ID     | DNS zone ID (Z123456789ABC1)                       |
| ZONE_NAME          | DNS domain name (rest-service.qa.my-company.com.)  |
| ECS_CLUSTER        | ECS cluster name                                   |
| SERVICE_BLUE       | First ECS service name                             |
| SERVICE_GREEN      | Second ECS service name                            |

```yaml
env:
  HOSTED_ZONE_ID: Z123456789ABC1
  ZONE_NAME: rest-service.qa.my-company.com.
  ECS_CLUSTER: qa-default-01
  SERVICE_BLUE: qa-rest-service-blue
  SERVICE_GREEN: qa-rest-service-green
```

*Step 1:* We use `get-blue-green-info` to get all the weighted DNS and ECS information.

```yaml
      - name: Get blue-green status
        uses: "cwong47/action-deploy-ecs-blue-green@latest"
        id: get-blue-green-info
        with:
          action: get-blue-green-info
          hosted_zone_id: ${{ env.HOSTED_ZONE_ID }}
          zone_name: ${{ env.ZONE_NAME }}
          ecs_service_blue: ${{ env.SERVICE_BLUE }}
          ecs_service_green: ${{ env.SERVICE_GREEN }}
          ecs_cluster: ${{ env.ECS_CLUSTER }}
```

*Step 2:* Update the autoscale settings of the original secondary cluster to match the original primary cluster.

```yaml
      - name: Scale up original secondary cluster
        uses: "cwong47/action-deploy-ecs-blue-green@latest"
        id: update-secondary-autoscale-capacity
        with:
          action: update-autoscale-capacity
          ecs_cluster: ${{ env.ECS_CLUSTER }}
          ecs_service: ${{ steps.get-blue-green-info.outputs.original_secondary_service }}
          min_capacity: ${{ steps.get-blue-green-info.outputs.original_primary_min_capacity }}
          max_capacity: ${{ steps.get-blue-green-info.outputs.original_primary_max_capacity }}
```

*Step 3:* Render task-definition using [amazon-ecs-render-task-definition](https://github.com/aws-actions/amazon-ecs-render-task-definition) and [amazon-ecs-deploy-task-definition](https://github.com/aws-actions/amazon-ecs-deploy-task-definition).

*Step 4:* Update weighted DNS accordingly.

```yaml
      - name: Update Route53 weight for blue-green [QA]
        uses: "cwong47/action-deploy-ecs-blue-green@latest"
        id: update-primary-dns-weight
        with:
          action: update-dns-weight
          hosted_zone_id: ${{ env.HOSTED_ZONE_ID }}
          primary_route53_json: ${{ steps.get-blue-green-info.outputs.pending_primary_json }}
          secondary_route53_json: ${{ steps.get-blue-green-info.outputs.pending_secondary_json }}
```

*Step 5:* Update the autoscale settings of the original primary cluster to match the original secondary cluster.

```yaml
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

## Parameters

### Inputs

| Name                       | Description                                                  | Default       | Required | Used by                                          |
| -------------------------- | ------------------------------------------------------------ | ------------- | -------- | ------------------------------------------------ |
| `action`                   | What step to execute                                         | `null`        | true     | `all`                                            |
| `dry_run`                  | Dry run                                                      | `false`       | false    | `all`                                            |
| `hosted_zone_id`           | Hosted zone ID from Route53                                  | `null`        | false    | `get-blue-green-info\|update-dns-weight`         |
| `zone_name`                | Zone name from Route53                                       | `null`        | false    | `get-blue-green-info`                            |
| `ecs_service_blue`         | The "blue" cluster of your ECS service                       | `null`        | false    | `get-blue-green-info`                            |
| `ecs_service_green`        | The "green" cluster of your ECS service                      | `null`        | false    | `get-blue-green-info`                            |
| `set_identifier_pattern`   | Default is `"blue\|green"`                                   | `blue\|green` | false    | `get-blue-green-info`                            |
| `primary_route53_json`     | Primary Route53 record in JSON format in `base64` encoding   | `null`        | false    | `update-dns-weight`                              |
| `secondary_route53_json`   | Secondary Route53 record in JSON format in `base64` encoding | `null`        | false    | `update-dns-weight`                              |
| `ecs_cluster`              | The ECS cluster                                              | `null`        | false    | `get-blue-green-info\|update-autoscale-capacity` |
| `ecs_service`              | The cluster of your ECS service                              | `null`        | false    | `update-autoscale-capacity`                      |
| `min_capacity`             | Minimum capacity to autoscale the service                    | `null`        | false    | `update-autoscale-capacity`                      |
| `max_capacity`             | Maximum capacity to autoscale the service                    | `null`        | false    | `update-autoscale-capacity`                      |

### Outputs

| Name                              | Description                                       |
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

## License

The source code for this project is released under the [MIT License](/LICENSE). This project is not associated with GitHub or AWS.
