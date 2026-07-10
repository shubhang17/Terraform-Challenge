# Per-student basic-auth credential for ttyd. Generated, not hardcoded --
# nobody, including the person reading this file, can derive another
# student's password from it.
resource "random_password" "ttyd" {
  for_each = var.students

  length  = 20
  special = false
}

# --- Per-student IAM: least privilege, not just "it works" ------------------
#
# ecr:GetAuthorizationToken cannot be scoped to a specific resource (it's an
# AWS API constraint, not a gap in this policy) -- but the actual pull
# actions below it are scoped to exactly one repository ARN, and logging
# permissions are scoped to exactly one log group ARN. A compromised task in
# one student's environment cannot pull another student's image or read
# another student's logs even with valid AWS credentials for its own role.
resource "aws_iam_role" "task_execution" {
  for_each = var.students

  name = "${var.project_name}-${each.value.sanitized_id}-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Owner = each.value.sanitized_id
  }
}

resource "aws_iam_role_policy" "task_execution" {
  for_each = var.students

  name = "${var.project_name}-${each.value.sanitized_id}-execution-policy"
  role = aws_iam_role.task_execution[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "EcrAuthTokenIsAccountWideByDesign"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid      = "PullOnlyThisStudentsRepository"
        Effect   = "Allow"
        Action   = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:BatchCheckLayerAvailability"]
        Resource = var.repository_arns[each.key]
      },
      {
        Sid      = "WriteOnlyThisStudentsLogGroup"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${var.tenant_log_group_arns[each.key]}:*"
      }
    ]
  })
}

resource "aws_ecs_task_definition" "app" {
  for_each = var.students

  family                   = "${var.project_name}-${each.value.sanitized_id}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.container_cpu
  memory                   = var.container_memory
  execution_role_arn       = aws_iam_role.task_execution[each.key].arn

  container_definitions = jsonencode([
    {
      name  = "app"
      image = "${var.repository_urls[each.key]}:${var.image_tag}"

      portMappings = [{
        containerPort = var.app_port
        protocol      = "tcp"
      }]

      environment = [
        { name = "CACHE_HOST", value = var.cache_host },
        { name = "CACHE_PORT", value = tostring(var.cache_port) },
        { name = "STUDENT_ID", value = each.value.sanitized_id },
        { name = "TTYD_USER", value = each.value.sanitized_id },
        { name = "TTYD_PASSWORD", value = random_password.ttyd[each.key].result },
      ]

      # startPeriod gives entrypoint.sh room to sit in its cache-wait loop
      # (up to CACHE_WAIT_TIMEOUT_SECONDS, default 60s) before a failed
      # health check counts against the task. The app is only marked
      # healthy once ttyd is genuinely listening, which only happens after
      # entrypoint.sh confirms the cache is reachable -- this is the
      # cold-start / race-condition defense living on the app side, paired
      # with the cache's own healthCheck on the other side.
      healthCheck = {
        command     = ["CMD-SHELL", "wget -q -O - http://localhost:${var.app_port}/ >/dev/null 2>&1 || exit 1"]
        interval    = 15
        timeout     = 5
        retries     = 3
        startPeriod = 90
      }

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = var.tenant_log_group_names[each.key]
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = each.value.sanitized_id
        }
      }
    }
  ])

  tags = {
    Owner = each.value.sanitized_id
  }
}

resource "aws_ecs_service" "app" {
  for_each = var.students

  name            = "${var.project_name}-${each.value.sanitized_id}"
  cluster         = var.cluster_id
  task_definition = aws_ecs_task_definition.app[each.key].arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [var.tenant_subnet_ids[each.key]]
    security_groups  = [var.tenant_security_group_ids[each.key]]
    assign_public_ip = true
  }

  tags = {
    Owner = each.value.sanitized_id
  }
}
