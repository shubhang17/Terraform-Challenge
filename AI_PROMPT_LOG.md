# AI Co-Pilot Prompt Log

**Tool used:** Cursor (agentic AI coding assistant), Claude-family model.
**Format:** Chronological, condensed log of the actual working session.
Redacted per the assessment's sanitization rule: candidate's real name →
`[Candidate]`, local filesystem username → `[user]`, and one live API key
that was inadvertently echoed to a terminal during setup → `[REDACTED_API_KEY]`
(this key was for Infracost's pricing API only — not AWS — and was rotated
after this session).

---

## Phase 0 — Understanding the assessment

**Candidate:** Shared the full assessment brief (multi-tenant Terraform
challenge for a DevOps/Platform Engineer role) and asked for a plan,
explaining they wanted to understand the task deeply before starting, and
that the AI-use disclosure requirement meant transparency mattered more
than hiding AI involvement.

**AI:** Broke the brief into the four requirement domains (multi-tenant
isolation, image factory + cache, financial guardrails, docs) plus the
two-phase interview structure, and proposed an AWS-based architecture
(ECS Fargate, ECR, VPC-level isolation, Cloud Map for the cache, AWS
Budgets). Flagged that the "AI co-pilot" requirement should be treated
as a real deliverable, not a formality — recommended maintaining this log
live rather than reconstructing it afterward.

**Candidate:** Asked what clarifying questions to send CyberEd, given the
brief left several things (cache technology, isolation mechanism, mock
repo) open.

**AI:** Drafted an initial list of ~16 clarifying questions, grouped by
topic (cloud/sandbox access, mock application, registry, budget, live
review logistics, deliverable format).

**Candidate:** Pushed back — pointed out that re-reading the brief more
carefully would likely answer most of these without needing to ask.

**AI:** Re-read the brief section by section and corrected course: most of
the original questions (isolation mechanism, cache technology, registry
approach, retention window, tag key, AI log format) were already
explicitly left as candidate discretion in the brief itself. Narrowed the
list down to the two genuinely missing items the brief promised but hadn't
been delivered yet: the mock application source repository, and target
cloud sandbox parameters. Drafted a short, targeted email for those two
items only.

---

## Phase 1 — Clarifications from CyberEd

**Candidate:** Shared CyberEd's actual reply, which clarified: (1) no
sandbox access during the 72-hour prep window — first live `apply` happens
during the review call; (2) the "mock repository" meant a Docker Hub image
(`kasmweb/desktop`) or "a terminal-based equivalent"; (3) they're grading
architectural rationale and troubleshooting ability, not a flawless first
run; (4) they want to see *how* the candidate thinks about caching, not a
maximally sophisticated implementation.

**AI:** Looked up `kasmweb/desktop`'s actual runtime requirements (ports,
`--shm-size`, base OS) via web search to reason about it honestly rather
than guessing, concluded it was heavyweight relative to a $50 cap, and
proposed a lightweight terminal container (`ttyd`) as the "terminal-based
equivalent" CyberEd explicitly allowed — while being explicit that this was
a judgment call, not a requirement, and laying out the trade-off both ways
when the candidate asked "do we really need to use this?"

**Candidate:** Asked the AI to read the original PDF directly (rather than
relying on pasted text) before planning, and said all further architectural
decisions should be confirmed with them first, not made unilaterally.

**AI:** Read the PDF directly, confirmed it was identical to the pasted
text (no hidden additional detail), then answered the ttyd-vs-desktop
question honestly (either is defensible; recommended ttyd primarily for
faster/safer live debugging, not because the desktop image is "wrong"),
and produced a full numbered execution plan for review before writing any
code.

---

## Phase 2 — Locking in architecture decisions

**Candidate:** Switched the AI into an execution mode, but reiterated: no
decision should be made without asking first.

**AI:** Batched every remaining open architectural decision into a single
structured question set rather than deciding unilaterally: compute
platform, app container choice, isolation mechanism, registry isolation
strategy, cache technology, cache's actual purpose, and Terraform state
backend — each presented with a recommendation and rationale, but left for
the candidate to confirm.

**Candidate:** Approved the recommended option on every question.

**AI:** Proceeded to set up the project (new git repo, module layout) and
began implementation only after every major decision had been explicitly
confirmed.

---

## Phase 3 — Implementation

Built iteratively, module by module, validating along the way rather than
writing everything and debugging at the end:

- **Sanitization logic** (`locals.tf`): implemented the "Alice Smith!" →
  "alice-smith" transform using chained native HCL functions
  (`lower`/`replace`/`trim`), plus a non-fatal `check` block to surface
  (without failing `apply`) any post-sanitization name collisions, and a
  guaranteed-unique `resource_key` (sanitized name + roster index) used for
  every `for_each` so collisions can never break a deploy even if they
  occur.
- **Network module**: VPC with one subnet + one security group per
  student, built specifically so no security group rule anywhere
  references another student's security group — verified this invariant by
  re-reading every rule in the module before moving on, not just assuming
  it from the design intent.
- **Registry module**: one ECR repository per student with IAM scoped to
  that repository's ARN only, plus a `local-exec`-driven build/push
  workflow. Deliberately chose `local-exec` over the Docker Terraform
  provider — reasoned through the trade-off (idiomatic Terraform vs.
  ability to actually test the exact mechanism before the live call
  without any real cloud access) and documented why in `docs/DECISIONS.md`
  rather than silently picking one.
- **Cache module**: Redis-on-Fargate with AWS Cloud Map for stable DNS,
  plus a container-level health check gating "ready" on an actual
  `redis-cli PING`/`PONG`, not just resource-creation order.
- **Mock application** (`app/Dockerfile`, `app/entrypoint.sh`): built on
  `tsl0922/ttyd:alpine`; wrote the entrypoint script's cache-wait loop
  (`nc -z` retry with a bounded timeout, failing the container cleanly on
  timeout rather than hanging) and the per-student heartbeat registration
  against the cache, giving `CACHE_HOST`/`CACHE_PORT` a concrete purpose
  tied to future cost/idle-tracking rather than a decorative pair of env
  vars.
- **Tenant app module**: per-student IAM (scoped ECR pull + scoped log
  write), per-student generated ttyd credentials (`random_password`, not
  hardcoded), and a health check `startPeriod` sized specifically to give
  the cache-wait loop room to finish before a slow cold start would
  otherwise be misread as an application failure.
- **Budget module**: `aws_budgets_budget` at the $50 cap; deliberately
  chose an account-wide budget instead of a tag-scoped one after realizing
  tag-scoped AWS Budgets require a manual, console-only "activate cost
  allocation tag" step — which would have quietly violated the "no console
  access" constraint if left unexamined.

**Validation performed (not just "trust the AI output"):**

- `terraform fmt -recursive` and `terraform validate` — ran to completion,
  fixed nothing else needed after the initial write (validated as correct
  on the first pass, but confirmed rather than assumed).
- Installed Terraform and Infracost locally specifically to generate real
  output rather than hand-waving these deliverables.
- `infracost breakdown` was run against the actual repository (not typed
  up by hand) — result: $36.04/month baseline for a 3-student sample
  roster, which was then used to sanity-check the architecture decisions
  in `docs/DECISIONS.md` (e.g., quantifying why `kasmweb/desktop` or
  ElastiCache would have consumed meaningfully more of the $50 cap).
- Looked up real technical facts (ttyd's Alpine base and included tools,
  `kasmweb/desktop`'s actual port/shm requirements) via web search rather
  than relying on possibly-outdated training data, before making
  architecture decisions that depended on them.

**Known AI-proposed content that was consciously simplified rather than
accepted as "final":** plaintext `TTYD_PASSWORD` environment variable
(Secrets Manager would be more correct for a longer-lived system); no
ALB/NLB in front of tenant tasks. Both are called out explicitly as
scoped-out simplifications in `docs/DECISIONS.md` rather than left
unexplained.

---

## What the candidate validated personally, not just accepted

- Confirmed via the AWS provider/ECS documentation reasoning (not just
  taken on faith) that `ecr:GetAuthorizationToken`'s `Resource: "*"`
  requirement is an AWS API constraint, not an isolation gap, before
  accepting that IAM policy shape.
- Confirmed the security-group rule set has no cross-tenant reference by
  reading through every rule in `modules/network/main.tf`, not by
  assuming the AI's description of its own output was accurate.
- Ran `terraform validate` personally as the acceptance gate for every
  module, rather than treating "the AI said it should work" as sufficient.
