output "service_names" {
  value = { for k, s in aws_ecs_service.app : k => s.name }
}

output "ttyd_credentials" {
  description = "Per-student ttyd basic-auth username/password, for the deployment guide / live demo only. Sensitive."
  value = {
    for k, s in var.students : s.sanitized_id => {
      username = s.sanitized_id
      password = random_password.ttyd[k].result
    }
  }
  sensitive = true
}
