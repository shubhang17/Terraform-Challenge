# Single shared ECS cluster. Isolation between students happens at the
# network (subnet/security group), registry (per-repo IAM), and log
# (per-group IAM) layers -- not by giving each student their own cluster,
# which would add nothing but overhead here.
resource "aws_ecs_cluster" "lab" {
  name = "${var.project_name}-cluster"

  setting {
    name  = "containerInsights"
    value = "disabled"
  }

  tags = {
    Name = "${var.project_name}-cluster"
  }
}

module "network" {
  source = "./modules/network"

  project_name = var.project_name
  students     = local.students
  vpc_cidr     = var.vpc_cidr
  app_port     = var.app_port
  cache_port   = var.cache_port
}

module "registry" {
  source = "./modules/registry"

  project_name    = var.project_name
  students        = local.students
  app_source_path = "${path.root}/app"
  image_tag       = var.image_tag
}

module "observability" {
  source = "./modules/observability"

  project_name       = var.project_name
  students           = local.students
  log_retention_days = var.log_retention_days
}

module "cache" {
  source = "./modules/cache"

  project_name                     = var.project_name
  aws_region                       = var.aws_region
  cluster_id                       = aws_ecs_cluster.lab.id
  subnet_id                        = module.network.shared_subnet_id
  security_group_id                = module.network.cache_security_group_id
  service_discovery_namespace_id   = module.network.service_discovery_namespace_id
  service_discovery_namespace_name = module.network.service_discovery_namespace_name
  cache_port                       = var.cache_port
  container_cpu                    = var.cache_container_cpu
  container_memory                 = var.cache_container_memory
  log_group_name                   = module.observability.cache_log_group_name
  log_group_arn                    = module.observability.cache_log_group_arn
}

# depends_on the whole registry + cache modules (not just individual
# outputs) so no student's ECS service is ever scheduled before its image
# has actually been pushed to ECR, or before the cache service exists.
module "tenant_app" {
  source = "./modules/tenant_app"

  project_name              = var.project_name
  aws_region                = var.aws_region
  students                  = local.students
  cluster_id                = aws_ecs_cluster.lab.id
  tenant_subnet_ids         = module.network.tenant_subnet_ids
  tenant_security_group_ids = module.network.tenant_security_group_ids
  repository_urls           = module.registry.repository_urls
  repository_arns           = module.registry.repository_arns
  tenant_log_group_names    = module.observability.tenant_log_group_names
  tenant_log_group_arns     = module.observability.tenant_log_group_arns
  image_tag                 = var.image_tag
  app_port                  = var.app_port
  cache_host                = module.cache.cache_host
  cache_port                = var.cache_port
  container_cpu             = var.app_container_cpu
  container_memory          = var.app_container_memory

  depends_on = [module.registry, module.cache]
}

module "budget" {
  source = "./modules/budget"

  project_name        = var.project_name
  budget_limit_usd    = var.budget_limit_usd
  budget_alert_emails = var.budget_alert_emails
}
