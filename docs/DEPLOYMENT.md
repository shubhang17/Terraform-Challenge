# Deployment Guide

## Prerequisites

Available on the machine that runs `terraform apply` (not in AWS itself):

| Tool                  | Why                                                     |
| --------------------- | -------------------------------------------------------- |
| Terraform >= 1.7       | Provisions everything in this repo                       |
| AWS CLI, configured    | `aws ecr get-login-password` during the image push step  |
| Docker, daemon running | Builds and pushes the mock application image             |
| Infracost (optional)   | Regenerates the cost report in `infracost/`               |

AWS credentials need permissions across: VPC/EC2 networking, ECS, ECR, IAM,
CloudWatch Logs, Service Discovery (Cloud Map), and Budgets.

## 1. Configure inputs

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` — at minimum, set `students` to the actual roster
for this session. Everything else has a working default.

## 2. Initialize

```bash
terraform init
```

Downloads the `aws`, `random`, and `null` providers. No AWS credentials are
required for this step.

## 3. Plan

```bash
terraform plan -out=tfplan
```

Review the plan. Expect to see, per student: one subnet, one security
group (+ several security group rule resources), one ECR repository, one
IAM role + policy, one CloudWatch log group, one ECS task definition, and
one ECS service — plus the shared VPC/cluster/cache/budget resources once.

## 4. Apply

```bash
terraform apply tfplan
```

This is also the step that builds and pushes the application image (via
`local-exec` inside the `registry` module) — expect real Docker build/push
output interleaved with Terraform's own resource-creation output. The first
apply will take longer than subsequent ones because the base image layers
have to be pulled before the build can run.

## 5. Verify

```bash
terraform output ecr_repository_urls
terraform output cache_host
terraform output -json ttyd_credentials   # sensitive; see below
```

To find a specific student's terminal, see
[RUNBOOK.md — Accessing a student terminal](./RUNBOOK.md#accessing-a-student-terminal).

## 6. Tear down

```bash
terraform destroy
```

There is nothing in this configuration with `prevent_destroy`, no retained
ECR images beyond the lifecycle policy's short window, and no stateful
managed service (deliberately avoided ElastiCache for this reason — see
[DECISIONS.md](./DECISIONS.md)). A single `terraform destroy` should remove
everything created by `apply`.

If it doesn't (e.g. an ECS service still has running tasks and refuses to
delete promptly), re-run `terraform destroy` once — ECS occasionally needs a
second pass to fully drain a service before its underlying resources can be
removed. This is standard ECS behavior, not an orphaned-resource bug in this
configuration.
