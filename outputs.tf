output "dokku_hostname" {
  description = "The hostname configured for Dokku"
  value       = var.dokku_hostname
}

output "dokku_version" {
  description = "The version of Dokku installed"
  value       = var.dokku_version
}

output "ssh_host" {
  description = "The SSH host where Dokku is installed"
  value       = var.ssh_host
}

output "dokku_installation_id" {
  description = "Unique identifier for this Dokku installation resource. Changes when the installation is re-triggered."
  value       = null_resource.install.id
}

output "dokku_ssh_key_configured" {
  description = "Whether an SSH public key was configured for Dokku deployments"
  value       = var.dokku_ssh_public_key_path != null
}

output "dokku_ssh_key_name" {
  description = "The name of the SSH key configured in Dokku (if any)"
  value       = var.dokku_ssh_public_key_path != null ? var.dokku_ssh_key_name : null
}

output "dokku_plugins" {
  description = "List of Dokku plugins that were configured for installation"
  value       = var.dokku_plugins
}

output "docker_daemon_config_applied" {
  description = "Whether custom Docker daemon configuration was applied"
  value       = var.docker_daemon_config != null ? module.docker_daemon_config[0].configuration_applied : false
}

output "docker_daemon_config_hash" {
  description = "Hash of the applied Docker daemon configuration (if any)"
  value       = var.docker_daemon_config != null ? module.docker_daemon_config[0].configuration_hash : null
}
