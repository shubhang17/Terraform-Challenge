# CyberEd Multi-Tenant Terraform Challenge

Provisions one isolated, browser-accessible terminal environment per
student on AWS (ECS Fargate) in the **CyberEd candidate-003 sandbox**
(`ap-south-1`), backed by a centralized cache, with zero-trust network
isolation, per-tenant registry/log access control, and a $50 cost cap.

## Deliverables

| Requirement | Where |
| --- | --- |
| Terraform configuration | Root + `modules/` |
| Infracost breakdown report | [`docs/INFRACOST.md`](./docs/INFRACOST.md), `infracost/` |
| System documentation | [`docs/`](./docs) |
| Sanitized AI prompt log | [`AI_PROMPT_LOG.md`](./AI_PROMPT_LOG.md) |

## Sandbox (candidate-003)

- **Region:** `ap-south-1` only
- **Prefix:** `cybered-candidate-003`
- **State:** pre-created S3 backend — see `backend.hcl.example`
- **Auth:** IAM launcher user → assume candidate role (see `scripts/assume-role.ps1`)

Full steps: [`docs/DEPLOYMENT.md`](./docs/DEPLOYMENT.md)

## Quick start

```powershell
Copy-Item terraform.tfvars.example terraform.tfvars   # set allowed_ingress_cidr to your IP/32
Copy-Item backend.hcl.example backend.hcl
.\scripts\assume-role.ps1
terraform init -backend-config=backend.hcl
terraform plan -out=tfplan
terraform apply tfplan
```

## Repository layout

```
.
├── backend.hcl.example           # remote state config (copy to backend.hcl)
├── scripts/assume-role.ps1       # STS assume-role helper
├── app/                          # ttyd mock app + cache-aware entrypoint
├── modules/                      # network, registry, cache, tenant_app, observability, budget
├── docs/                         # architecture, deployment, runbook, decisions, infracost
├── infracost/                    # cost report (regenerate for ap-south-1 if needed)
└── AI_PROMPT_LOG.md
```
