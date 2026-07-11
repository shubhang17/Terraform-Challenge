# Decisions & Rationale

The assessment brief was intentionally underspecified in several places.
This document records every discretionary call made, and why, so it can be
defended directly in the live review rather than re-derived on the spot.

## 1. Terminal-based container instead of `kasmweb/desktop`

CyberEd's clarification named `kasmweb/desktop` as the target image but
explicitly allowed "a terminal-based equivalent." `kasmweb/desktop` is a
full browser-streamed Ubuntu XFCE desktop (Chrome, Firefox, Tor Browser
preinstalled) — functional, but heavy: it needs `--shm-size=512m`, a larger
CPU/memory allocation to stay responsive, and a longer cold-start.

Given a **hard $50 cap** shared across every student's environment plus the
cache, a lightweight browser terminal (`tsl0922/ttyd:alpine`, ~15MB image,
comfortable on 0.25 vCPU / 0.5 GB) was chosen instead:

- Meaningfully cheaper per running hour, with more budget headroom left for
  the cache and for running multiple students concurrently during the live
  review.
- Faster cold start, which matters directly for the race-condition /
  health-check requirement — less time spent waiting on the app container
  itself, more margin to prove out the cache-readiness logic.
- A CLI-based lab environment is arguably a better fit for a cybersecurity
  training platform than a full graphical desktop.

Trade-off accepted: no GUI, no browser-in-browser. If CyberEd's actual use
case requires GUI tooling, swapping the base image in `app/Dockerfile` is a
small, contained change — the isolation/cache/budget architecture around it
does not need to change.

## 2. Redis container on Fargate instead of AWS ElastiCache

The brief leaves the cache technology unspecified by design. Two realistic
options: a self-managed Redis (or similar) container, or AWS ElastiCache.

ElastiCache's smallest node (`cache.t3.micro`) plus its required subnet
group is meaningful overhead against a $50 cap once tenant tasks are also
running, and it's a heavier resource to reason about/tear down cleanly in a
short-lived exercise. A single `redis:7-alpine` container on its own Fargate
task gives the same functional contract (`CACHE_HOST`/`CACHE_PORT`, and a
genuine "accepting connections" health check) for a fraction of the cost and
with a `terraform destroy` footprint that's just an ECS service + task
definition, not a managed stateful service with its own lifecycle.

## 3. One ECR repository per student, not a shared repo + tag convention

Both approaches are explicitly allowed by the brief. A per-repository
approach was chosen because IAM policy scoping is simpler and harder to get
wrong: each task execution role names exactly one repository ARN. A shared
repository would require every pull-scoping decision to hinge on
tag-pattern IAM conditions, which are easy to write incorrectly and harder
to verify by inspection during a live review.

## 4. Dedicated subnet *and* dedicated security group per student

The brief allows subnets, security groups, or isolated Docker
networks/namespaces as valid isolation mechanisms — any one alone would
satisfy the letter of the requirement. Combining subnet + security group
was chosen anyway as defense in depth: even if a future change accidentally
loosened one layer (e.g. a broader CIDR route), the other layer (SG rules
with no cross-tenant reference) still enforces the isolation guarantee
independently.

## 5. Public subnets + security groups instead of a NAT Gateway

Fargate tasks need outbound internet access to pull images and reach AWS
APIs. The conventional "private subnet + NAT Gateway" pattern was skipped:
a NAT Gateway costs roughly $0.045/hour plus data processing charges, which
is a disproportionate, always-on cost against a $50 total cap for a
short-lived lab. Tasks instead run in public subnets with `assign_public_ip
= true`, and isolation is enforced entirely by security groups rather than
subnet privacy — which is the actual mechanism the brief asks for
("distinct security groups with explicit ingress/egress rules").

## 6. Remote Terraform state (CyberEd pre-created backend)

The initial submission used local state for simplicity before sandbox
parameters were issued. The **Candidate Environment Sheet** provides a
pre-created S3 backend — we must use it and must **not** recreate the
bucket. Configuration: `backend "s3" {}` in `versions.tf` plus
`backend.hcl` (from `backend.hcl.example`).

## 7. AWS Budget with pre-created SNS topic

Budget is named `cybered-candidate-003-hard-cap` and sends alerts to the
sandbox SNS topic at **50%, 80%, and 100%** (actual + forecasted at 100%).
Budgets alert only — they are **not** a hard stop; tear down with
`terraform destroy` when finished.

## 8. Restricted terminal ingress (authorized user CIDR)

The sandbox requires inbound access to student desktops be locked to the
**authorized user** only. Tenant security groups use `allowed_ingress_cidr`
(from `terraform.tfvars`) instead of `0.0.0.0/0`. Set this to your public
IP/32 before `terraform apply`.

## 9. `local-exec` for image build/push, not the Docker Terraform provider

The `kreuzwerker/docker` Terraform provider can build and push images
natively, which is more "purely Terraform" — but its registry-auth
configuration for ECR has enough sharp edges (provider-level `registry_auth`
blocks, token refresh timing) that getting it right *without* being able to
test against real AWS beforehand felt riskier than a well-understood
`docker build` / `docker tag` / `docker push` sequence via `local-exec`.
This only assumes `docker` and `aws` CLIs are available on the machine
running `terraform apply`, which is a safe assumption for a DevOps
evaluation lab terminal — and it's called out explicitly as a prerequisite
in [DEPLOYMENT.md](./DEPLOYMENT.md).

## 10. Cache purpose: heartbeat registry, not a generic demo key

Per CyberEd's clarification, the goal was "how caching can assist," not a
maximally sophisticated cache integration. A per-student heartbeat key
(`student:<id>:heartbeat`, refreshed every 30s) was chosen because it does
double duty: it exercises the cache meaningfully (write + periodic refresh,
namespaced per tenant) *and* it's a natural seed for a cost-control
mechanism (an idle-timeout watcher could read these keys to identify and
stop inactive student environments) — tying the cache requirement back into
the assessment's other stated goal of cost-awareness, rather than treating
it as an isolated checkbox.

## 11. Known simplifications (not hidden, deliberately out of scope)

- `TTYD_PASSWORD` is passed as a plain environment variable rather than via
  Secrets Manager/SSM Parameter Store. For a short-lived lab exposing a
  generated, per-student password, this was judged acceptable; Secrets
  Manager would be the correct next step for a longer-lived deployment.
- The shared subnet's CIDR allocation reserves index `200` in the /8
  `cidrsubnet` split, which assumes a roster well under 200 students. Fine
  for a class-scale roster; would need a different allocation scheme at a
  much larger scale.
- No ALB/NLB in front of the per-student tasks — students would reach their
  terminal via the task's public IP and `app_port` directly. Adding a load
  balancer per student (or a shared one with path-based routing) was judged
  out of scope for the budget and timeline; the runbook documents how to
  find a task's current public IP instead.
