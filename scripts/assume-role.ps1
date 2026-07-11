# Assumes the CyberEd assessment candidate role and exports session credentials
# into the current PowerShell session. Re-run every ~4 hours when the session expires.
#
# Prerequisites: launcher IAM user configured as profile "cybered-user"
# (see docs/DEPLOYMENT.md).

param(
  [string]$Profile      = "cybered-user",
  [string]$RoleArn       = "arn:aws:iam::150105760360:role/CyberEdAssessmentCandidate-candidate-003",
  [string]$ExternalId    = "cybered-candidate-003",
  [string]$SessionName   = "cybered-build",
  [string]$Region        = "ap-south-1"
)

$ErrorActionPreference = "Stop"

$raw = aws sts assume-role `
  --role-arn $RoleArn `
  --role-session-name $SessionName `
  --external-id $ExternalId `
  --profile $Profile `
  --output json

if ($LASTEXITCODE -ne 0) {
  Write-Error "sts assume-role failed. Check launcher credentials and profile '$Profile'."
}

$session = $raw | ConvertFrom-Json

$env:AWS_ACCESS_KEY_ID     = $session.Credentials.AccessKeyId
$env:AWS_SECRET_ACCESS_KEY = $session.Credentials.SecretAccessKey
$env:AWS_SESSION_TOKEN     = $session.Credentials.SessionToken
$env:AWS_DEFAULT_REGION    = $Region

Write-Host "Assumed $RoleArn"
Write-Host "Session expires: $($session.Credentials.Expiration)"
Write-Host "Region: $Region — you can now run terraform init/plan/apply in this shell."
