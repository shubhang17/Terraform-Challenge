# CyberEd Multi-Tenant Terraform Challenge

Provisions one isolated, browser-accessible terminal environment per
student on AWS (ECS Fargate), backed by a centralized cache, with
zero-trust network isolation, per-tenant registry/log access control, and
a hard $50 cost cap.

## Deliverables

| Requirement                          | Where                                                        |
| -------------------------------------- | ------------------------------------------------------------- |
| Terraform configuration               | Root + `modules/` (see below)                                 |
| Infracost breakdown report            | [`docs/INFRACOST.md`](./docs/INFRACOST.md), raw output in `infracost/` |
| System documentation                  | [`docs/`](./docs) — architecture, deployment guide, runbook, decision log |
| Sanitized AI prompt log               | [`AI_PROMPT_LOG.md`](./AI_PROMPT_LOG.md)                       |

## Quick links

- **[Architecture](./docs/ARCHITECTURE.md)** — how isolation, the cache,
  and the budget guardrails actually work.
- **[Decisions & Rationale](./docs/DECISIONS.md)** — every discretionary
  call made where the brief left room for judgment, and why.
- **[Deployment Guide](./docs/DEPLOYMENT.md)** — `init` → `plan` → `apply`
  → `destroy`, plus prerequisites.
- **[Troubleshooting Runbook](./docs/RUNBOOK.md)** — accessing a student's
  terminal, reading isolated logs, diagnosing a cache-connection failure.
- **[Cost Projection](./docs/INFRACOST.md)** — real Infracost output
  against this code: **$36.04/month** baseline for a 3-student sample
  roster, against the $50 cap.

## Repository layout

```
.
├── main.tf, variables.tf, locals.tf, outputs.tf, providers.tf, versions.tf
├── terraform.tfvars.example      # copy to terraform.tfvars before running
├── app/                          # mock application: ttyd + cache-aware entrypoint
├── modules/
│   ├── network/                  # VPC, per-student subnet + security group, service discovery
│   ├── registry/                 # per-student ECR repo + build/push workflow
│   ├── cache/                    # centralized Redis-on-Fargate cache
│   ├── tenant_app/                # per-student ECS service, scoped IAM, ttyd credentials
│   ├── observability/              # per-student CloudWatch log groups
│   └── budget/                    # AWS Budgets hard cap
├── docs/                          # architecture, deployment, runbook, decisions, cost report
├── infracost/                      # raw Infracost CLI output
└── AI_PROMPT_LOG.md                # sanitized log of AI-assisted development
```

## TL;DR to run it

```bash
cp terraform.tfvars.example terraform.tfvars   # edit `students` to the real roster
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

Full prerequisites and explanation in [`docs/DEPLOYMENT.md`](./docs/DEPLOYMENT.md).
