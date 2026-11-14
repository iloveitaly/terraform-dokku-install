terraform {
  required_version = ">= 1.10"
}

variable "ssh_host" { type = string }
variable "ssh_user" { type = string }
variable "ssh_known_hosts_path" { type = string }
variable "server_id" { type = string }

module "dokku" {
  source               = "git::https://github.com/iloveitaly/terraform-dokku-install.git?ref=v0.1.0"
  ssh_host             = var.ssh_host
  ssh_user             = var.ssh_user
  ssh_known_hosts_path = var.ssh_known_hosts_path
  server_id            = var.server_id
  # Uses the local SSH agent. An explicit ssh_private_key_path also works.
  dokku_hostname = "dokku.example.com"
  docker_daemon_config = jsonencode({
    log-driver = "json-file"
    log-opts   = { max-size = "10m", max-file = "3" }
  })
}

output "dokku_hostname" {
  value = module.dokku.dokku_hostname
}
