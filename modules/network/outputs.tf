output "vpc_id" {
  value = aws_vpc.lab.id
}

output "tenant_subnet_ids" {
  description = "Map of resource_key -> subnet id, one per student."
  value       = { for k, s in aws_subnet.tenant : k => s.id }
}

output "tenant_security_group_ids" {
  description = "Map of resource_key -> security group id, one per student."
  value       = { for k, sg in aws_security_group.tenant : k => sg.id }
}

output "shared_subnet_id" {
  value = aws_subnet.shared.id
}

output "cache_security_group_id" {
  value = aws_security_group.cache.id
}

output "service_discovery_namespace_id" {
  value = aws_service_discovery_private_dns_namespace.lab.id
}

output "service_discovery_namespace_name" {
  value = aws_service_discovery_private_dns_namespace.lab.name
}
