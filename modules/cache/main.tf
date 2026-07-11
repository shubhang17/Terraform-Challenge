# --- Agnostic cache layer ----------------------------------------------------
#
# The assessment intentionally leaves the caching technology unspecified,
# constraining only the runtime contract (CACHE_HOST / CACHE_PORT). We chose
# a single Redis container on ECS Fargate over AWS ElastiCache:
#   - ElastiCache's smallest node (cache.t3.micro, ~$12/mo on-demand) plus
#     a subnet group is disproportionate overhead against a $50 hard cap,
#     especially once tenant app tasks are also running.
#   - A Fargate task gives us the same "fully initialized and accepting
#     connections" guarantee via its own container health check, without
#     provisioning a separate managed-service subsystem.
# See docs/DECISIONS.md for the full trade-off writeup.
resource "aws_iam_role" "cache_execution" {
  name                 = "${var.project_name}-cache-execution"
  path                 = var.iam_role_path
  permissions_boundary = var.iam_permissions_boundary_arn

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "cache_execution_logs" {
  name = "${var.project_name}-cache-execution-logs"
  role = aws_iam_role.cache_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${var.log_group_arn}:*"
    }]
  })
}

resource "aws_ecs_task_definition" "cache" {
  family                   = "${var.project_name}-cache"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.container_cpu
  memory                   = var.container_memory
  execution_role_arn       = aws_iam_role.cache_execution.arn

  container_definitions = jsonencode([
    {
      name  = "cache"
      image = "redis:7-alpine"

      portMappings = [{
        containerPort = var.cache_port
        protocol      = "tcp"
      }]

      # This is what backs the "must be fully initialized and accepting
      # connections" requirement: ECS will not consider this task healthy
      # -- and therefore will not register it in service discovery -- until
      # redis-cli PING actually succeeds against the running server.
      healthCheck = {
        command     = ["CMD-SHELL", "redis-cli ping | grep -q PONG || exit 1"]
        interval    = 10
        timeout     = 5
        retries     = 3
        startPeriod = 20
      }

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = var.log_group_name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "cache"
        }
      }
    }
  ])

  tags = {
    Name = "${var.project_name}-cache"
  }
}

resource "aws_service_discovery_service" "cache" {
  name = "cache"

  dns_config {
    namespace_id = var.service_discovery_namespace_id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}

resource "aws_ecs_service" "cache" {
  name            = "${var.project_name}-cache"
  cluster         = var.cluster_id
  task_definition = aws_ecs_task_definition.cache.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [var.subnet_id]
    security_groups  = [var.security_group_id]
    assign_public_ip = true
  }

  service_registries {
    registry_arn = aws_service_discovery_service.cache.arn
  }
}
