data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  registry_url = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com"

  # Hash every file in the build context so a docker rebuild is only
  # triggered when the mock application source actually changes.
  source_files       = fileset(var.app_source_path, "**")
  build_trigger_hash = md5(join("", [for f in local.source_files : filemd5("${var.app_source_path}/${f}")]))
  local_image_tag    = "cybered-lab-app:${local.build_trigger_hash}"
}

# --- Per-student image isolation ---------------------------------------------
#
# One repository per student rather than one shared repository with
# tag-based access control. IAM policies in modules/tenant_app scope each
# task execution role to exactly one repository ARN, so a compromised or
# misconfigured task in one student's environment cannot even list, let
# alone pull, another student's image.
resource "aws_ecr_repository" "student" {
  for_each = var.students

  name                 = "${var.project_name}/${each.value.sanitized_id}"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Owner = each.value.sanitized_id
  }
}

# Untagged images (left behind by re-pushes) expire quickly so ECR storage
# doesn't quietly accumulate cost -- same "avoid storage leakage" principle
# the assessment applies to log retention.
resource "aws_ecr_lifecycle_policy" "student" {
  for_each = aws_ecr_repository.student

  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Expire untagged images after 3 days"
      selection = {
        tagStatus   = "untagged"
        countType   = "sinceImagePushed"
        countUnit   = "days"
        countNumber = 3
      }
      action = { type = "expire" }
    }]
  })
}

# --- Image factory: build once, promote per-tenant ---------------------------
#
# The mock application is identical for every student, so we build it once
# and push the same artifact into each student's private repository. This
# keeps the "image builds" and "registry isolation" requirements separate
# and honest: the isolation guarantee comes from N distinct repositories +
# scoped IAM, not from N distinct (and needlessly duplicated) builds.
#
# Implemented with local-exec rather than the Docker Terraform provider on
# purpose: it only assumes `docker` and `aws` CLIs on the machine running
# `terraform apply` (a safe assumption for a DevOps lab terminal), and
# avoids provider-level registry-auth configuration that we cannot dry-run
# before the live session. See docs/DECISIONS.md.
resource "null_resource" "docker_login" {
  triggers = {
    registry = local.registry_url
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      aws ecr get-login-password --region ${data.aws_region.current.name} \
        | docker login --username AWS --password-stdin ${local.registry_url}
    EOT
  }
}

resource "null_resource" "build_image" {
  triggers = {
    source_hash = local.build_trigger_hash
  }

  provisioner "local-exec" {
    command = "docker build -t ${local.local_image_tag} ${var.app_source_path}"
  }
}

resource "null_resource" "push_image" {
  for_each = aws_ecr_repository.student

  depends_on = [null_resource.docker_login, null_resource.build_image]

  triggers = {
    repository_url = each.value.repository_url
    source_hash    = local.build_trigger_hash
    image_tag      = var.image_tag
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      docker tag ${local.local_image_tag} ${each.value.repository_url}:${var.image_tag}
      docker push ${each.value.repository_url}:${var.image_tag}
    EOT
  }
}
