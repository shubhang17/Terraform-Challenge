# Architecture

## Summary

This configuration provisions one isolated, browser-accessible terminal
environment per student on AWS, backed by a centralized cache, inside a
single shared VPC. Isolation is enforced at three independent layers so that
no single misconfiguration collapses tenant separation: **network**
(subnet + security group per student), **registry** (ECR repository + IAM
per student), and **logging** (CloudWatch log group + IAM per student).

```
                              ┌─────────────────────────────────────────────┐
                              │                  AWS Account                │
                              │  ┌────────────────────────────────────────┐ │
                              │  │              VPC (10.42.0.0/16)         │ │
                              │  │                                        │ │
                              │  │  ┌──────────────┐   ┌──────────────┐    │ │
                              │  │  │ student-01   │   │ student-02   │    │ │
                              │  │  │ subnet /24   │   │ subnet /24   │ .. │ │
                              │  │  │ ┌──────────┐ │   │ ┌──────────┐ │    │ │
                              │  │  │ │  SG:     │ │   │ │  SG:     │ │    │ │
                              │  │  │ │  student │ │   │ │  student │ │    │ │
                              │  │  │ │  -01     │ │   │ │  -02     │ │    │ │
                              │  │  │ │          │ │   │ │          │ │    │ │
                              │  │  │ │ ECS task │ │   │ │ ECS task │ │    │ │
                              │  │  │ │ (ttyd)   │ │   │ │ (ttyd)   │ │    │ │
                              │  │  │ └────┬─────┘ │   │ └────┬─────┘ │    │ │
                              │  │  └──────┼───────┘   └──────┼───────┘    │ │
                              │  │         │  cache_port only  │            │ │
                              │  │         └─────────┬─────────┘            │ │
                              │  │                    ▼                     │ │
                              │  │        ┌───────────────────────┐         │ │
                              │  │        │ shared-services subnet│         │ │
                              │  │        │  SG: cache             │         │ │
                              │  │        │  ECS task (redis)      │         │ │
                              │  │        └───────────────────────┘         │ │
                              │  └────────────────────────────────────────┘ │
                              │                                             │
                              │  ECR: <project>/student-01  <project>/student-02 ...
                              │  CloudWatch: /ecs/<project>/student-01, .../student-02, .../cache
                              │  AWS Budgets: <project>-hard-cap ($50)     │
                              └─────────────────────────────────────────────┘
```

There is deliberately **no arrow between `student-01` and `student-02`** in
this diagram. No resource in this configuration -- security group rule, IAM
policy, or otherwise -- ever references another student's security group,
repository, or log group. The only cross-cutting resource every student
talks to is the cache, and even that path is one-directional and
port-scoped (see "Network isolation" below).

## Layer 1 — Network isolation (Zero-Trust)

- One VPC, one subnet per student (`cidrsubnet(vpc_cidr, 8, index)`), plus a
  shared-services subnet for the cache.
- One security group per student. Security groups are stateful and
  default-deny: unless a rule explicitly allows traffic, it's blocked.
- Every tenant security group has exactly one east-west egress rule: to the
  cache security group, on the cache port. There is no rule, anywhere in
  this configuration, where one tenant security group references another.
- The cache security group's ingress is built from a `for_each` over
  students, but each resulting rule still only names *one* tenant SG as its
  source -- students cannot see each other through the cache's rules either.
- Egress for HTTPS (443, to pull images / call AWS APIs) and DNS (53) is
  allowed to `0.0.0.0/0` because those destinations are inherently shared
  infrastructure (ECR, DNS resolvers), not another tenant.
- Implication for the live security test: a shell inside `student-01`'s
  container has network line-of-sight to exactly two things — the internet
  (for HTTPS/DNS) and the cache on its cache port. Nothing routes it to
  `student-02`'s subnet, container, or task.

## Layer 2 — Registry isolation

- One ECR repository per student (`<project>/<sanitized-id>`), not a shared
  repository with tag-based conventions.
- Each student's ECS task execution role has an inline policy scoped to
  exactly one repository ARN (`ecr:BatchGetImage`,
  `ecr:GetDownloadUrlForLayer`, `ecr:BatchCheckLayerAvailability`).
  `ecr:GetAuthorizationToken` is unavoidably `Resource: "*"` — that's an AWS
  API constraint, not a scoping gap — but the pull actions that actually
  matter are locked to one ARN per role.
- `IMMUTABLE` tag mutability + a short-lived lifecycle policy on untagged
  images, so nothing can silently overwrite or accumulate cost in a
  student's repository.

## Layer 3 — Log isolation

- One CloudWatch log group per student, and a separate one for the cache.
- Each student's task role can only `CreateLogStream`/`PutLogEvents` into
  its own log group ARN. A compromised task cannot read (or write into)
  another student's log stream.
- All log groups carry an explicit `retention_in_days` (3–7, validated in
  `variables.tf`) so nothing accumulates indefinitely.

## The agnostic cache layer

- Technology: a single Redis container running as its own ECS Fargate
  service (`redis:7-alpine`), not AWS ElastiCache. See
  [DECISIONS.md](./DECISIONS.md) for the cost/complexity trade-off.
- Discovery: AWS Cloud Map private DNS namespace (`<project>.internal`)
  gives the cache a stable hostname (`cache.<project>.internal`) instead of
  a task IP that changes on every redeploy. That hostname is what's injected
  into every app container as `CACHE_HOST`.
- Purpose: each student container's `entrypoint.sh` writes a namespaced
  heartbeat key (`student:<id>:heartbeat`) into the cache on startup and on
  an interval. This is intentionally minimal — it is not meant to be a
  production session store — but it gives `CACHE_HOST`/`CACHE_PORT` a real
  job (a building block for idle-timeout cost control) rather than an
  unused pair of env vars.
- Race-condition protection: `entrypoint.sh` blocks in a `nc -z` retry loop
  until the cache is actually accepting TCP connections before it ever
  execs the application (`ttyd`). Combined with the cache's own ECS
  `healthCheck` (which requires a real `redis-cli PING` → `PONG` before the
  task is marked healthy) and a generous `startPeriod` on the app's own
  health check, a cold-started cache cannot cause a false "unhealthy
  application" result.

## Compute & image choice

- **ECS Fargate** — no servers to patch/manage, natural fit for a
  short-lived, per-tenant workload, and scales cleanly with the dynamic
  student list via `for_each`.
- **`ttyd` (terminal-in-browser) instead of the literally-named
  `kasmweb/desktop`** — CyberEd confirmed either is acceptable
  ("...or a terminal-based equivalent"). See
  [DECISIONS.md](./DECISIONS.md) for why this was chosen.

## Financial guardrails

- `aws_budgets_budget` hard cap at `$50`/month, account-wide (see
  [DECISIONS.md](./DECISIONS.md) for why it isn't tag-scoped).
- Every resource this configuration creates carries an `Owner` tag equal to
  the student's sanitized identifier (via `default_tags` + explicit
  per-resource tags where `default_tags` can't reach, e.g. inside
  `container_definitions` JSON).
- No NAT Gateway — tenant/cache subnets are public with tightly-scoped
  security groups instead, which is materially cheaper for a short-lived
  lab and doesn't weaken tenant isolation (isolation comes from security
  groups, not from subnet privacy).
