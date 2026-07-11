# Deployment Guide

## Prerequisites

| Tool | Why |
| --- | --- |
| Terraform >= 1.7 | Provisions everything in this repo |
| AWS CLI | Assume candidate role + ECR login during image push |
| Docker (daemon running) | Builds and pushes the mock application image |
| Infracost (optional) | Regenerates cost report for `ap-south-1` |

**Sandbox constraints (candidate-003):**

- Region: **`ap-south-1` only**
- Resource prefix: **`cybered-candidate-003`**
- No NAT Gateway, no ALB/NLB
- IAM roles: path `/cybered-assessment/candidate-003/`, permissions boundary attached
- Remote state: **pre-created S3 bucket — do not recreate**

Credentials are in your **Candidate Environment Sheet** (confidential). Never commit them.

---

## 1. Configure AWS profile (launcher user)

Use values from your environment sheet:

```powershell
aws configure set aws_access_key_id     <ACCESS_KEY> --profile cybered-user
aws configure set aws_secret_access_key <SECRET_KEY> --profile cybered-user
aws configure set region ap-south-1 --profile cybered-user
```

## 2. Assume the candidate role (required before Terraform)

Sessions last **4 hours** — re-run when expired.

**PowerShell:**

```powershell
.\scripts\assume-role.ps1
```

**Or manually:**

```powershell
$session = aws sts assume-role `
  --role-arn arn:aws:iam::150105760360:role/CyberEdAssessmentCandidate-candidate-003 `
  --role-session-name cybered-build `
  --external-id cybered-candidate-003 `
  --profile cybered-user `
  --output json | ConvertFrom-Json

$env:AWS_ACCESS_KEY_ID     = $session.Credentials.AccessKeyId
$env:AWS_SECRET_ACCESS_KEY = $session.Credentials.SecretAccessKey
$env:AWS_SESSION_TOKEN     = $session.Credentials.SessionToken
$env:AWS_DEFAULT_REGION    = "ap-south-1"
```

## 3. Configure Terraform inputs

```powershell
Copy-Item terraform.tfvars.example terraform.tfvars
Copy-Item backend.hcl.example backend.hcl
```

Edit `terraform.tfvars`:

- Set `students` to the roster for this session
- Set `allowed_ingress_cidr` to **your public IP/32** (required by sandbox rules)

Find your IP: `curl -s https://checkip.amazonaws.com`

## 4. Initialize (remote backend)

```powershell
terraform init -backend-config=backend.hcl
```

Do **not** create the state bucket — it already exists.

## 5. Plan

```powershell
terraform plan -out=tfplan
```

## 6. Apply

```powershell
terraform apply tfplan
```

Image build/push runs via `local-exec` in the registry module (Docker + `aws ecr get-login-password`).

## 7. Verify

```powershell
terraform output ecr_repository_urls
terraform output cache_host
terraform output -json ttyd_credentials
```

See [RUNBOOK.md](./RUNBOOK.md) for accessing a student terminal.

## 8. Tear down (required)

Assessment end: **2026-07-13T23:59:59Z**. CyberEd verifies cleanup independently.

```powershell
terraform destroy
```

Re-run once if ECS services need extra time to drain.
