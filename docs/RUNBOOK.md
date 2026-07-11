# Troubleshooting Runbook

## Accessing a student terminal

Fargate tasks don't get a stable IP across redeploys (no load balancer is
in front of them — see [DECISIONS.md](./DECISIONS.md), item 10), so find
the current public IP per session:

```bash
CLUSTER=$(terraform output -raw project_name 2>/dev/null || echo "cybered-candidate-003")-cluster
TASK_ARN=$(aws ecs list-tasks --cluster "$CLUSTER" \
  --service-name cybered-candidate-003-<student-id> --query 'taskArns[0]' --output text)

ENI_ID=$(aws ecs describe-tasks --cluster "$CLUSTER" --tasks "$TASK_ARN" \
  --query 'tasks[0].attachments[0].details[?name==`networkInterfaceId`].value' \
  --output text)

aws ec2 describe-network-interfaces --network-interface-ids "$ENI_ID" \
  --query 'NetworkInterfaces[0].Association.PublicIp' --output text
```

Then browse to `http://<public-ip>:7681` and authenticate with the
per-student credentials:

```bash
terraform output -json ttyd_credentials | jq '."<student-id>"'
```

## Debugging a failed application deployment

1. **Check ECS service events first** — most failures surface here before
   you need logs at all:

   ```bash
   aws ecs describe-services --cluster cybered-candidate-003-cluster \
     --services cybered-candidate-003-<student-id> \
     --query 'services[0].events[0:10]'
   ```

2. **Pull the isolated log stream for that student.** Each student has
   their own log group (`/ecs/cybered-candidate-003/<student-id>`), and each task run
   creates its own stream prefixed with the student ID:

   ```bash
   aws logs describe-log-streams \
     --log-group-name /ecs/cybered-candidate-003/<student-id> \
     --order-by LastEventTime --descending --limit 1

   aws logs get-log-events \
     --log-group-name /ecs/cybered-candidate-003/<student-id> \
     --log-stream-name <stream-name-from-above>
   ```

   Because IAM for each student's task role is scoped to only their own log
   group ARN, you will never accidentally be looking at another student's
   output here even by mistake — the isolation extends to how you debug it.

3. **Common causes at this stage:**
   - `CannotPullContainerError` → the image was never pushed. Check that
     the `registry` module's `null_resource.push_image` actually succeeded
     (its `local-exec` output appears inline during `terraform apply`); a
     failed Docker push does not currently roll back the ECS
     service/task-definition creation.
   - Task stuck in `PENDING` → almost always a subnet/security-group
     misconfiguration preventing the ENI from attaching, or no route to
     the internet for the image pull. Confirm the student's subnet has a
     route to the Internet Gateway (`aws_route_table_association.tenant`).

## Debugging a cache-connection error

The application container will not start `ttyd` until `entrypoint.sh`
confirms the cache is reachable — so a cache problem shows up as the app
container's health check failing repeatedly, or the log stream stuck on
`[entrypoint] waiting for cache at ...`.

1. **Confirm the cache task itself is healthy:**

   ```bash
   aws ecs describe-services --cluster cybered-candidate-003-cluster \
     --services cybered-candidate-003-cache \
     --query 'services[0].{running:runningCount,desired:desiredCount}'
   ```

2. **Check the cache's own log group** (`/ecs/cybered-candidate-003/cache`) for
   Redis startup errors — same commands as above, different log group.

3. **Confirm service discovery actually has a record.** If the cache task
   restarted, its DNS record should update automatically (10s TTL), but
   it's worth confirming:

   ```bash
   aws servicediscovery list-instances --service-id <cache-service-discovery-id>
   ```

4. **Confirm the security group path.** The student's security group must
   have an egress rule to the cache security group on the cache port
   (`aws_vpc_security_group_egress_rule.tenant_to_cache`), and the cache
   security group must have a matching ingress rule from that specific
   student (`aws_vpc_security_group_ingress_rule.cache_from_tenant`). If
   either is missing for a given student, that student — and only that
   student — will be stuck waiting on the cache forever (bounded by
   `CACHE_WAIT_TIMEOUT_SECONDS`, default 60s, after which the container
   exits non-zero and ECS retries the task).

5. **If the cache is healthy and reachable but the app still can't
   connect,** check that `CACHE_HOST` resolves inside the VPC — Cloud Map
   private DNS namespaces only resolve from within the VPC they're
   attached to, so testing resolution from a machine outside the VPC will
   always (correctly) fail; that is not a bug.

## Full teardown verification

After `terraform destroy` completes, confirm nothing was left behind:

```bash
aws ecs list-clusters --query 'clusterArns[?contains(@, `cybered-candidate-003`)]'
aws ecr describe-repositories --query 'repositories[?starts_with(repositoryName, `cybered-candidate-003`)]'
aws logs describe-log-groups --log-group-name-prefix /ecs/cybered-candidate-003
aws budgets describe-budgets --account-id <account-id> \
  --query 'Budgets[?starts_with(BudgetName, `cybered-candidate-003`)]'
```

All four should return empty. If the ECR check still shows a repository,
`terraform destroy` was likely run while that repository still had images
protected by the `IMMUTABLE` tag setting plus an in-flight lifecycle
policy — re-running `terraform destroy` a second time resolves this in
every case observed during development.
