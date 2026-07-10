# Pre-Deployment Cost Projection

Generated with the Infracost CLI against this repository's actual Terraform
code (not hand-estimated) using the sample roster in
`terraform.tfvars.example` (`student-01`, `student-02`, `"Alice Smith!"`).

Raw output: [`infracost/infracost-report.txt`](../infracost/infracost-report.txt)
(human-readable) and [`infracost/infracost.json`](../infracost/infracost.json)
(machine-readable, e.g. for CI cost-diffing on future PRs).

Regenerate at any time with:

```bash
infracost breakdown --path . --format json --out-file infracost/infracost.json
infracost output --path infracost/infracost.json --format table --out-file infracost/infracost-report.txt
```

## Result

| Metric                                   | Value                       |
| ----------------------------------------- | ---------------------------- |
| **Baseline monthly cost (3 students)**    | **$36.04**                   |
| Hard budget cap (`aws_budgets_budget`)    | $50.00                       |
| Headroom at 3 students                    | ~$14 (~28%)                  |
| Cloud resources scanned                   | 62 (11 priced, 50 free, 1 unsupported pricing lookup*) |

\* `aws_service_discovery_service` has no published Infracost pricing model
at time of writing; AWS Cloud Map itself has no hourly/monthly charge for
this configuration (namespace + service registration are free; you only
pay for the DNS queries, which are negligible at lab scale).

## Where the cost actually comes from

Fargate compute dominates, as expected for a container-per-tenant design:

- **Per student app task**: 0.25 vCPU + 0.5 GB → **$9.01/month** each
  ($7.39 vCPU + $1.62 memory)
- **Cache task**: same shape → **$9.01/month**
- **CloudWatch Logs, ECR storage**: usage-based (ingestion, storage,
  scanned data) — Infracost correctly reports these as "depends on usage"
  rather than a fixed figure, since they scale with how much a student
  actually types/logs. At the retention window this configuration uses
  (3–7 days) and lab-scale usage, these are expected to be low
  single-digit dollars in practice, not a material fraction of the $50 cap.
- **$0 for**: VPC, subnets, route tables, internet gateway, security
  groups, IAM roles/policies, ECS cluster, service discovery namespace —
  all free AWS constructs, which is exactly why the isolation design
  (subnet + SG per student) doesn't itself add to the budget pressure.

## What this validates

- 3 students fits comfortably inside $50 with real margin.
- Cost scales at ~**$9/student/month** in compute terms. At that rate, the
  $50 cap supports roughly **4–5 concurrent student environments** plus the
  shared cache before hitting the ceiling — a concrete, checkable number to
  bring into the architecture defense conversation.
- This is also the quantitative case for the decisions in
  [DECISIONS.md](./DECISIONS.md): swapping in `kasmweb/desktop` (larger
  CPU/memory footprint) or AWS ElastiCache (fixed node cost regardless of
  idle time) would consume meaningfully more of this budget for the same
  number of students.
