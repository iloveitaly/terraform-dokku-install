output "dokku_hostname" {
  description = "The hostname configured for Dokku."
  value       = var.dokku_hostname
  depends_on  = [terraform_data.ssh_key]
}
output "dokku_version" {
  description = "Requested Dokku version selector. With latest, the installed numeric version is resolved on the server during apply."
  value       = var.dokku_version
  depends_on  = [terraform_data.ssh_key]
}
output "ssh_host" {
  description = "The SSH host where Dokku is installed."
  value       = var.ssh_host
  depends_on  = [terraform_data.ssh_key]
}
output "dokku_installation_id" {
  description = "Identifier of the Dokku installation resource."
  value       = terraform_data.install.id
  depends_on  = [terraform_data.ssh_key]
}
output "dokku_install_stdout" {
  description = "Deprecated: installation output is streamed to the Terraform console and is not stored in state."
  value       = null
}
output "dokku_ssh_key_configured" {
  description = "Whether an SSH public key was configured for Dokku deployments."
  value       = var.dokku_ssh_public_key_path != null
  depends_on  = [terraform_data.ssh_key]
}
output "dokku_ssh_key_name" {
  description = "The name of the configured deploy key, if any."
  value       = var.dokku_ssh_public_key_path != null ? var.dokku_ssh_key_name : null
  depends_on  = [terraform_data.ssh_key]
}
output "dokku_plugins" {
  description = "Legacy plugin list configured for installation."
  value       = var.dokku_plugins
  depends_on  = [terraform_data.ssh_key]
}
output "docker_daemon_config_applied" {
  description = "Whether custom Docker daemon configuration was applied."
  value       = var.docker_daemon_config != null ? module.docker_daemon_config[0].configuration_applied : false
  depends_on  = [terraform_data.ssh_key]
}
output "docker_daemon_config_hash" {
  description = "Hash of the applied Docker daemon configuration, if any."
  value       = var.docker_daemon_config != null ? module.docker_daemon_config[0].configuration_hash : null
  depends_on  = [terraform_data.ssh_key]
}

output "dokku_plugin_definitions" {
  description = "Configured plugins keyed by name, including legacy plugin entries."
  value       = merge([for plugin in local.desired_plugins : { (plugin.name) = { url = plugin.url, revision = plugin.revision } }]...)
  depends_on  = [terraform_data.ssh_key]
}
