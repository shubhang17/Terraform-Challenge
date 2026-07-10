output "cache_host" {
  description = "Stable internal DNS name for the cache, injected into every tenant app as CACHE_HOST."
  value       = "${aws_service_discovery_service.cache.name}.${var.service_discovery_namespace_name}"
}

output "service_name" {
  value = aws_service_discovery_service.cache.name
}

output "service_arn" {
  value = aws_service_discovery_service.cache.arn
}
