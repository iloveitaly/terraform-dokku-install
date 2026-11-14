output "configuration_applied" {
  description = "Whether Docker daemon configuration completed."
  value       = true
  depends_on  = [terraform_data.docker_daemon_config]
}
output "configuration_hash" {
  description = "Hash of the applied Docker daemon configuration."
  value       = sha256(var.docker_daemon_config)
  depends_on  = [terraform_data.docker_daemon_config]
}
output "resource_id" {
  description = "Identifier of the configuration resource."
  value       = terraform_data.docker_daemon_config.id
}
