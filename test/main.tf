locals {
  ssh_private_key_path = "~/.ssh/brotandgames_automation_id_rsa"
  ssh_public_key_path  = "~/.ssh/brotandgames_automation_id_rsa.pub" # Add public key path
  fqdn                 = "dokku.yourhost.com"
  ssh_host             = "192.168.1.100"
}

module "dokku" {
  source = "../"

  ssh_host             = local.ssh_host
  ssh_user             = "root"
  ssh_private_key_path = local.ssh_private_key_path

  dokku_version  = "0.35.20"
  dokku_hostname = local.fqdn

  # SSH key configuration for Dokku deployments
  dokku_ssh_public_key_path = local.ssh_public_key_path
  dokku_ssh_key_name        = "deployment-key"

  # Install common Dokku plugins using state-aware management
  dokku_plugins = [
    "postgres",
    "redis",
    "mysql",
    "https://github.com/dokku/dokku-letsencrypt.git"
  ]

  # Optional: Remove plugins not in the list (excluding core plugins)
  remove_unlisted_plugins = false
}

output "dokku_info" {
  description = "Information about the Dokku installation"
  value = {
    hostname           = module.dokku.dokku_hostname
    version            = module.dokku.dokku_version
    ssh_host           = module.dokku.ssh_host
    ssh_key_configured = module.dokku.dokku_ssh_key_configured
    ssh_key_name       = module.dokku.dokku_ssh_key_name
    plugins_configured = module.dokku.dokku_plugins
  }
}
