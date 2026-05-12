output "configuration_applied" {
  description = "Whether the Docker daemon configuration was successfully applied"
  value       = true
  depends_on  = [null_resource.docker_daemon_config]
}

output "configuration_hash" {
  description = "Hash of the applied Docker daemon configuration"
  value       = sha256(var.docker_daemon_config)
}

output "resource_id" {
  description = "Unique identifier for this configuration resource"
  value       = null_resource.docker_daemon_config.id
}
