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

  # Optional: Custom Docker daemon configuration
  # Example: Enable containerd snapshotter and configure logging
  docker_daemon_config = jsonencode({
    features = {
      containerd-snapshotter = true
    }
    log-driver = "json-file"
    log-opts = {
      max-size = "10m"
      max-file = "3"
    }
    storage-driver = "overlay2"
  })
}

output "dokku_info" {
  description = "Information about the Dokku installation"
  value = {
    hostname                     = module.dokku.dokku_hostname
    version                      = module.dokku.dokku_version
    ssh_host                     = module.dokku.ssh_host
    ssh_key_configured           = module.dokku.dokku_ssh_key_configured
    ssh_key_name                 = module.dokku.dokku_ssh_key_name
    plugins_configured           = module.dokku.dokku_plugins
    docker_daemon_config_applied = module.dokku.docker_daemon_config_applied
    docker_daemon_config_hash    = module.dokku.docker_daemon_config_hash
  }
}
